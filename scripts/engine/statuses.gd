## statuses.gd - Ongoing effects other than locks: poison on champions, attack buffs on a player, and
## start-of-turn abilities and enchantment effects. Everything here runs in the start-of-turn step
## (or at end of turn for buff durations). Poison keeps working on champions that are encamped:
## only NEW effects from the opponent are blocked from reaching them (see attack.gd and damage.gd).
class_name StatusRules
extends RefCounted


## "+amount damage on this player's attacks for N of their turns", starting with the turn it is played.
static func add_attack_buff(g: Game, p: int, amount: int, turns: int) -> void:
	g.players[p].buffs.append({"kind": "attack", "amount": amount, "turns_left": turns})
	g._log("P%d's attacks get +%d for %d turn(s)." % [p, amount, turns])


static func attack_bonus(ps: PlayerState) -> int:
	var total: int = 0
	for b in ps.buffs:
		if str(b.kind) == "attack":
			total += int(b.amount)
	return total


static func end_of_turn(_g: Game, p: int) -> void:
	var ps: PlayerState = _g.players[p]
	for b in ps.buffs.duplicate():
		b.turns_left = int(b.turns_left) - 1
		if int(b.turns_left) <= 0:
			ps.buffs.erase(b)
	for champion in ps.champions:
		for st in champion.statuses.duplicate():
			var kind: String = str(st.kind)
			if kind == "next_attack_bonus":  # unused bonuses do not carry over
				champion.statuses.erase(st)
			elif kind == "stored_bonus":  # Grimn: a saved bonus lasts one turn
				champion.statuses.erase(st)
			elif kind == "no_attack" or kind == "duel":  # count their owner's own turns
				st.turns_left = int(st.turns_left) - 1
				if int(st.turns_left) <= 0:
					champion.statuses.erase(st)
		# Grimn: a champion that did not attack this turn saves a bonus for its next attack.
		if champion.has_ability() and champion.card.ability.has("stored_bonus_if_idle") and not champion.attacked_this_turn:
			champion.statuses.append({"kind": "stored_bonus", "amount": int(champion.card.ability.stored_bonus_if_idle)})
			_g._log("%s did not attack: its next attack does +%d damage." % [champion.card_name(), int(champion.card.ability.stored_bonus_if_idle)])


static func apply_poison(g: Game, target: Champion, amount: int, turns: int, source: int) -> void:
	for st in target.statuses:  # a poisoned champion cannot be poisoned again
		if str(st.kind) == "poison":
			g._log("%s is already poisoned, so it cannot be poisoned again." % target.describe())
			return
	target.statuses.append({"kind": "poison", "amount": amount, "turns_left": turns, "source": source})
	if turns < 0:
		g._log("%s is poisoned (%d damage every turn until it is removed)." % [target.describe(), amount])
	else:
		g._log("%s is poisoned (%d damage for %d turns)." % [target.describe(), amount, turns])


## Start of player p's turn: poison ticks, then start-of-turn abilities and enchantment effects.
static func run_start_of_turn(g: Game, p: int) -> void:
	var ps: PlayerState = g.players[p]
	for champion in ps.champions:
		for st in champion.statuses.duplicate():
			if str(st.kind) == "protected":  # "prevent all damage until your next turn" ends here
				champion.statuses.erase(st)
	for champion in ps.champions.duplicate():
		for st in champion.statuses.duplicate():
			if str(st.kind) != "poison" or not ps.champions.has(champion):
				continue
			# Existing effects continue even while encamped, so this bypasses encampment immunity.
			DamageRules.damage_champion(g, champion, int(st.amount), int(st.source), true)
			if int(st.turns_left) > 0:  # turns_left -1 means "until the champion is destroyed or it is removed"
				st.turns_left = int(st.turns_left) - 1
				if int(st.turns_left) <= 0:
					champion.statuses.erase(st)
	for champion in ps.champions.duplicate():
		if champion.has_ability() and str(champion.card.ability.get("trigger", "")) == "start_of_turn":
			_apply_simple_effect(g, p, champion, champion.card.ability)
	# The Fortress ability triggers at the same time as the enchantments.
	if typeof(ps.fortress_def.get("start_of_turn")) == TYPE_DICTIONARY and not LockRules.is_locked(g, p, "fortress"):
		_apply_simple_effect(g, p, null, ps.fortress_def.start_of_turn)
	for ench in ps.enchantments.duplicate():
		if typeof(ench.get("start_of_turn")) == TYPE_DICTIONARY:
			_apply_simple_effect(g, p, null, ench.start_of_turn)


## Simple passive effects: gain_mana, draw, heal_self (champions only).
static func _apply_simple_effect(g: Game, p: int, champion: Champion, eff: Dictionary) -> void:
	var ps: PlayerState = g.players[p]
	match str(eff.get("op", "")):
		"gain_mana":
			ps.mana += int(eff.get("amount", 0))
		"draw":
			for i in int(eff.get("amount", 1)):
				if ps.deck.is_empty():
					g._finish(1 - p, "Decking out")
					return
				ps.hand.append(ps.deck.pop_back())
		"heal_all_active":  # the Castle: heal every ACTIVE champion (encamped ones are asleep)
			for c in ps.active_champions():
				c.damage = maxi(0, c.damage - int(eff.get("amount", 0)))
			g._log("P%d's Fortress heals the active champions by %d." % [p, int(eff.get("amount", 0))])
		"coin_draw":  # Pirate Cove: flip a coin, on heads draw
			if g.flip_coin():
				g._log("Coin: Heads, P%d's Fortress draws a card." % p)
				for i in int(eff.get("count", 1)):
					if ps.deck.is_empty():
						g._finish(1 - p, "Decking out")
						return
					ps.hand.append(ps.deck.pop_back())
			else:
				g._log("Coin: Tails, P%d's Fortress draws nothing." % p)
		"heal_all":  # heal every champion you control (active and encamped)
			for c in ps.champions:
				c.damage = maxi(0, c.damage - int(eff.get("amount", 0)))
			g._log("P%d's champions are healed by %d." % [p, int(eff.get("amount", 0))])
		"gain_mana_per_champion":
			var gained: int = ps.champions.size() * int(eff.get("amount", 1))
			ps.mana += gained
			g._log("P%d gains %d mana." % [p, gained])
		"fortress_damage_per_active_champion":  # not an attack, so it ignores the Fortress's immunity
			DamageRules.damage_fortress(g, 1 - p, ps.active_champions().size() * int(eff.get("amount", 10)))
		"coin_protect":  # flip a coin; heads: prevent all damage to this champion until your next turn
			if champion != null and g.flip_coin():
				champion.statuses.append({"kind": "protected"})
				g._log("%s is protected until its owner's next turn." % champion.card_name())
			else:
				g._log("P%d's coin lands Tails." % p)
		"coin_lock":  # flip a coin; heads: lock the opponent from "what" for "turns" of their turns
			if g.flip_coin():
				LockRules.add(g, 1 - p, str(eff.get("what", "")), int(eff.get("turns", 1)))
			else:
				g._log("P%d's coin lands Tails." % p)
		"heal_self":
			if champion != null:
				champion.damage = maxi(0, champion.damage - int(eff.get("amount", 0)))
