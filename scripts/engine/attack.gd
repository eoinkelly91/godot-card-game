## attack.gd - The Attack step: spells (free, any number, before or after attacking), attacks (one per
## color per turn, Fortress targeting rules, castling and encampment rules, attached spells, reactions,
## fizzling). Champions in the encampment area cannot attack and cannot be targeted by the opponent's
## attacks or spells. Nothing here is allowed on a first turn.
class_name AttackRules
extends RefCounted


## Plays a spell on its own (not attached to an attack). Spells are free: any number, before or after
## your attacks, only in your Attack step.
## target: {"champion": uid} or {"fortress": player_index}, depending on the effect.
static func play_spell(g: Game, p: int, hand_index: int, effect_index: int, target: Dictionary = {}) -> Dictionary:
	var chk: Dictionary = TurnRules.require_step(g, p, Game.Step.ATTACK)
	if not chk.ok:
		return chk
	var ps: PlayerState = g.players[p]
	if ps.is_first_turn():
		return g._fail("You cannot play spells on your first turn.")
	if LockRules.is_locked(g, p, "spell"):
		return g._fail("Your spells are locked.")
	if hand_index < 0 or hand_index >= ps.hand.size():
		return g._fail("Bad hand index.")
	var card: Dictionary = ps.hand[hand_index]
	if str(card.get("kind", "")) != "spell":
		return g._fail("That is not a spell.")
	var effects: Array = card.get("effects", [])
	if effect_index < 0 or effect_index >= effects.size():
		return g._fail("Bad effect index.")
	var effect: Dictionary = effects[effect_index]

	# Validate the target BEFORE the card is consumed.
	var op: String = str(effect.get("op", ""))
	var target_champion: Champion = null
	match op:
		"heal":
			target_champion = g._champion_of(ps, int(target.get("champion", -1)))
			if target_champion == null:
				return g._fail("Heal needs one of your own champions as target.")
		"damage", "poison":
			if target.has("champion"):
				target_champion = g._find_champion(int(target.champion))
				if target_champion == null:
					return g._fail("Target champion not found.")
				if target_champion.owner != p and g.players[target_champion.owner].castled:
					return g._fail("Encamped champions cannot be targeted.")
			elif target.has("fortress") and op == "damage":
				var fi: int = int(target.fortress)
				if fi < 0 or fi > 1:
					return g._fail("Bad fortress index.")
			else:
				return g._fail("This effect needs a champion target.")
			if op == "poison" and target_champion.owner == p:
				return g._fail("Poison needs an enemy champion.")
		"bonus_damage":
			return g._fail("This effect only works when attached to an attack.")
		"lock", "draw", "gain_mana", "buff_attack":
			pass
		_:
			return g._fail("Unknown spell effect: " + op)

	ps.hand.remove_at(hand_index)
	ps.discard.append(card)
	g.spells_this_turn += 1
	g._log("P%d casts %s (effect %d)." % [p, card.get("name", "?"), effect_index + 1])

	match op:
		"heal":
			target_champion.damage = maxi(0, target_champion.damage - int(effect.get("amount", 0)))
		"damage":
			var total: float = DamageRules.apply_enchantments(float(effect.get("amount", 0)), ps, [], "", true)
			var dmg: int = DamageRules.round_down_10(total)
			if target_champion != null:
				DamageRules.damage_champion(g, target_champion, dmg, p)
			else:
				DamageRules.damage_fortress(g, int(target.fortress), dmg)
		"poison":
			StatusRules.apply_poison(g, target_champion, int(effect.get("amount", 10)), int(effect.get("turns", 1)), p)
		"buff_attack":
			StatusRules.add_attack_buff(g, p, int(effect.get("amount", 0)), int(effect.get("turns", 1)))
		"lock":
			LockRules.add(g, 1 - p, str(effect.get("what", "")), int(effect.get("turns", 1)))
		"draw":
			for i in int(effect.get("amount", 1)):
				if ps.deck.is_empty():
					g._finish(1 - p, "Decking out")
					break
				ps.hand.append(ps.deck.pop_back())
		"gain_mana":
			ps.mana += int(effect.get("amount", 0))
	g._check_win()
	return g._ok()


## target: {"champion": uid} or {"fortress": enemy_index}. The Fortress can be attacked when it is
## castled (in the active play area) or when its owner has no champions; otherwise it is immune.
## spell_picks: [{"hand_index": i, "effect_index": j}, ...] in the order they execute.
## enchant_order: indices into your enchantment list (defaults to the order they were played).
static func attack(g: Game, p: int, attacker_uid: int, attack_index: int, target: Dictionary,
		spell_picks: Array = [], enchant_order: Array = []) -> Dictionary:
	var chk: Dictionary = TurnRules.require_step(g, p, Game.Step.ATTACK)
	if not chk.ok:
		return chk
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	if me.is_first_turn():
		return g._fail("You cannot attack on your first turn.")
	if LockRules.is_locked(g, p, "attack"):
		return g._fail("Your attacks are locked.")
	if me.castled:
		return g._fail("Your champions are encamped and cannot attack.")

	var attacker: Champion = g._champion_of(me, attacker_uid)
	if attacker == null:
		return g._fail("Pick one of your own champions to attack with.")
	var attacks: Array = attacker.card.get("attacks", [])
	if attack_index < 0 or attack_index >= attacks.size():
		return g._fail("Bad attack index.")
	var atk: Dictionary = attacks[attack_index]
	if attacker.color() in me.colors_used:
		return g._fail("You already attacked with %s this turn." % attacker.color())
	var req_err: String = _requirement_error(attacker, atk)
	if req_err != "":
		return g._fail(req_err)
	var mana_cost: int = int(atk.get("mana_cost", 0))
	if me.mana < mana_cost:
		return g._fail("Not enough banked mana (%d needed)." % mana_cost)

	var target_champion: Champion = null
	if bool(atk.get("no_target", false)):
		target = {}  # attacks that hit every enemy champion need no target
	elif target.has("champion"):
		target_champion = g._champion_of(foe, int(target.champion))
		if target_champion == null:
			return g._fail("Target must be an enemy champion.")
		if foe.castled:
			return g._fail("Encamped champions cannot be targeted; only the Fortress can be attacked.")
	elif target.has("fortress"):
		if not foe.castled and foe.champions.size() > 0:
			return g._fail("The Fortress is immune while its owner controls a champion in the active play area.")
	elif not bool(atk.get("no_target", false)):
		return g._fail("No target given.")

	# Validate attached spells.
	var picked: Array = []   # [{card, hand_index}]
	var seen: Array = []
	var spell_bonus: int = 0
	if LockRules.is_locked(g, p, "spell") and not spell_picks.is_empty():
		return g._fail("Your spells are locked.")
	for pick in spell_picks:
		var hi: int = int(pick.get("hand_index", -1))
		var ei: int = int(pick.get("effect_index", 0))
		if hi < 0 or hi >= me.hand.size() or hi in seen:
			return g._fail("Bad spell pick.")
		var scard: Dictionary = me.hand[hi]
		if str(scard.get("kind", "")) != "spell":
			return g._fail("Only spells can be attached.")
		var seffects: Array = scard.get("effects", [])
		if ei < 0 or ei >= seffects.size():
			return g._fail("Bad spell effect index.")
		var seffect: Dictionary = seffects[ei]
		var sop: String = str(seffect.get("op", ""))
		if sop != "bonus_damage" and sop != "damage":
			return g._fail("%s cannot be attached to an attack." % scard.get("name", "That spell"))
		spell_bonus += int(seffect.get("amount", 0))
		seen.append(hi)
		picked.append({"card": scard, "hand_index": hi})

	# Commit: pay, mark the color used (even if the attack fizzles), use up the spells.
	me.mana -= mana_cost
	me.colors_used.append(attacker.color())
	var drop: Array = seen.duplicate()
	drop.sort()
	drop.reverse()
	for hi in drop:
		me.hand.remove_at(hi)
	for entry in picked:
		me.discard.append(entry.card)
	var tname: String = target_champion.describe() if target_champion != null else \
			("every enemy champion" if bool(atk.get("no_target", false)) else "P%d's Fortress" % (1 - p))
	g._log("P%d attacks %s with %s (%s)." % [p, tname, attacker.describe(), atk.get("name", "attack")])

	# Reactions resolve completely before the attack lands.
	var spell_flag: bool = (not picked.is_empty()) or g.spells_this_turn > 0
	var negated: bool = ReactionRules.run(g, p, attacker, atk, spell_flag)
	# Champion abilities that react to being attacked (damage back to the attacker) resolve before the attack lands.
	if target_champion != null and target_champion.has_ability() and not g.finished:
		var tab: Dictionary = target_champion.card.ability
		if tab.has("when_attacked_damage_attacker") and me.champions.has(attacker):
			DamageRules.damage_champion(g, attacker, int(tab.when_attacked_damage_attacker), 1 - p)
	var target_gone: bool = target_champion != null and not foe.champions.has(target_champion)
	var attacker_gone: bool = not me.champions.has(attacker)
	if g.finished:
		return g._ok({"damage": 0, "fizzled": true})
	if negated or target_gone or attacker_gone:
		g._log("The attack fizzles. %s is still used this turn." % attacker.color())
		return g._ok({"damage": 0, "fizzled": true})

	var coins: Dictionary = AttackEffects.coin_damage(g, atk)
	if bool(coins.fizzle):
		g._log("The attack does nothing. %s is still used this turn." % attacker.color())
		return g._ok({"damage": 0, "fizzled": true})
	var dmg: int = DamageRules.calc(g, attacker, atk, target_champion, spell_bonus, enchant_order, int(coins.extra))
	# Defensive abilities of the target champion.
	if target_champion != null and target_champion.has_ability():
		var tab2: Dictionary = target_champion.card.ability
		if tab2.has("negate_if_damage_over") and dmg > int(tab2.negate_if_damage_over):
			g._log("%s prevents the attack (it would do %d)." % [target_champion.card_name(), dmg])
			return g._ok({"damage": 0, "fizzled": true})
		if tab2.has("immune_to_attackers_max_hp_over") and attacker.max_hp() > int(tab2.immune_to_attackers_max_hp_over):
			g._log("%s cannot be damaged by a champion with over %d HP." % [target_champion.card_name(), int(tab2.immune_to_attackers_max_hp_over)])
			dmg = 0
	if target_champion != null:
		DamageRules.damage_champion(g, target_champion, dmg, p)
	elif not bool(atk.get("no_target", false)):
		DamageRules.damage_fortress(g, 1 - p, dmg)
	if target_champion != null and target_champion.has_ability() and me.champions.has(attacker):
		var tab3: Dictionary = target_champion.card.ability
		if tab3.has("when_hit_over_damage_attacker") and dmg > int(tab3.when_hit_over_damage_attacker.over):
			DamageRules.damage_champion(g, attacker, int(tab3.when_hit_over_damage_attacker.amount), 1 - p)
	if not g.finished:
		AttackEffects.after_damage(g, p, attacker, atk, target_champion)
	g._check_win()
	return g._ok({"damage": dmg, "fizzled": false})


## Attacks are standard (no cost), mana (mana_cost) or HP threshold (requires); a card never combines
## a mana cost with an HP threshold.
static func _requirement_error(attacker: Champion, atk: Dictionary) -> String:
	var req: Dictionary = atk.get("requires", {})
	if req.has("self_hp_at_most") and attacker.current_hp() > int(req.self_hp_at_most):
		return "Needs the attacker at %d HP or less." % int(req.self_hp_at_most)
	if req.has("self_hp_at_least") and attacker.current_hp() < int(req.self_hp_at_least):
		return "Needs the attacker at %d HP or more." % int(req.self_hp_at_least)
	return ""
