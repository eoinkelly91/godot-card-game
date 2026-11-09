## simple_bot.gd - A deliberately dumb bot that plays a whole turn with legal moves, found by trying them.
## Good enough to smoke-test the rules and to get rough balance numbers from tools/simulate.gd.
## It castles when it is far behind on the board, and uncastles after two castled turns.
class_name SimpleBot
extends RefCounted


static func take_turn(g: Game, p: int) -> void:
	var ps: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]

	# Step 2: castle when far behind (once per game), uncastle voluntarily after two castled turns.
	if ps.castled:
		if ps.castled_turns >= 2:
			g.uncastle(p)
	elif ps.castles_used == 0 and not ps.is_first_turn() and ps.champions.size() == 1 and foe.champions.size() >= 3:
		g.castle(p)  # only possible with exactly one champion in the active play area

	# Summon (the turn has no steps: summoning, spells and enchantments are possible at any time).
	for i in range(ps.hand.size() - 1, -1, -1):
		if i < ps.hand.size() and str(ps.hand[i].get("kind", "")) == "enchantment":
			g.play_enchantment(p, i)
	var order: Array = range(ps.hand.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _champion_value(ps.hand[a]) > _champion_value(ps.hand[b]))
	for i in order:
		if str(ps.hand[i].get("kind", "")) != "champion":
			continue
		if g.summon(p, i, _sacrifices(ps, ps.hand[i])).ok:
			break

	# Attack.
	if ps.is_first_turn():
		g.end_turn(p)
		return
	_cast_spells(g, p)
	if not ps.castled:
		var guard: int = 0
		while guard < 8:
			guard += 1
			if not _attack_once(g, p):
				break
	g.end_turn(p)


static func _cast_spells(g: Game, p: int) -> void:
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	for i in range(me.hand.size() - 1, -1, -1):
		if i >= me.hand.size() or str(me.hand[i].get("kind", "")) != "spell":
			continue
		var effect: Dictionary = me.hand[i].effects[0]
		match str(effect.op):
			"heal":
				for c in me.champions:
					if c.damage > 0:
						g.play_spell(p, i, 0, {"champion": c.uid})
						break
			"damage":
				if not foe.castled and not foe.champions.is_empty():
					g.play_spell(p, i, 0, {"champion": _weakest(foe).uid})
			"poison":
				if not foe.castled and not foe.champions.is_empty():
					g.play_spell(p, i, 0, {"champion": _weakest(foe).uid})
			"cleanse":
				for c in me.champions:
					for st in c.statuses:
						if str(st.kind) == "poison":
							g.play_spell(p, i, 0, {"champion": c.uid})
							break
			"drain_mana":
				if foe.mana >= 2:
					g.play_spell(p, i, 0)
			"no_attack":
				if not foe.castled and not foe.champions.is_empty():
					g.play_spell(p, i, 0, {"champion": _weakest(foe).uid})
			"wizardry_draw":
				g.play_spell(p, i, 0)
			"buff_attack", "lock", "draw", "gain_mana":
				if str(effect.op) != "buff_attack" or not me.castled:
					g.play_spell(p, i, 0)


## Biggest affordable attack by an unused color, at the weakest legal target. Returns false if none worked.
static func _attack_once(g: Game, p: int) -> bool:
	var me: PlayerState = g.players[p]
	var options: Array = []
	for c in me.champions:
		if c.color() in me.colors_used:
			var has_token: bool = false  # Volcanic Horn lets another champion attack again
			for src in me.extra_attacks:
				if int(src) != c.uid:
					has_token = true
			if not has_token:
				continue
		var attacks: Array = c.card.attacks
		for ai in attacks.size():
			if int(attacks[ai].get("mana_cost", 0)) <= me.mana:
				options.append({"uid": c.uid, "index": ai, "damage": int(attacks[ai].damage)})
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.damage > b.damage)
	for opt in options:
		var attacker: Champion = g._champion_of(me, opt.uid)
		var target: Dictionary = _target_for(g, p, attacker, attacker.card.attacks[opt.index])
		var picks: Array = []
		for i in me.hand.size():
			if str(me.hand[i].get("kind", "")) == "spell" and me.hand[i].effects.size() > 1 and me.hand[i].effects[1].op == "bonus_damage":
				picks.append({"hand_index": i, "effect_index": 1})
				break
		var r: Dictionary = g.attack(p, opt.uid, opt.index, target, picks)
		if not r.ok and not picks.is_empty():
			r = g.attack(p, opt.uid, opt.index, target)
		if r.ok:
			return true
	return false


## Picks the target (and options such as a discard) for one attack: Duel forces the duelist, Dual Spear needs two
## champions, Staff Attack discards a spare card when the hand is big.
static func _target_for(g: Game, p: int, attacker: Champion, atk: Dictionary) -> Dictionary:
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	var target: Dictionary = {"fortress": 1 - p}
	var legal: Array = []
	for fc in foe.champions:
		if not (fc.has_ability() and fc.card.ability.has("immune_to_attackers_max_hp_over") \
				and attacker.max_hp() > int(fc.card.ability.immune_to_attackers_max_hp_over)):
			legal.append(fc)
	if not foe.castled and not legal.is_empty():
		var weakest_legal: Champion = legal[0]
		for fc in legal:
			if fc.current_hp() < weakest_legal.current_hp():
				weakest_legal = fc
		target = {"champion": weakest_legal.uid}
		for st in attacker.statuses:
			if str(st.kind) == "duel":
				var duelist: Champion = g._champion_of(foe, int(st.duelist))
				if duelist != null:
					target = {"champion": duelist.uid}
		if int(atk.get("multi_target", 0)) > 1 and legal.size() >= 2:
			var sorted: Array = legal.duplicate()
			sorted.sort_custom(func(a: Champion, b: Champion) -> bool: return a.current_hp() < b.current_hp())
			target = {"champions": [sorted[0].uid, sorted[1].uid]}
	if atk.has("optional_discard_bonus") and me.hand.size() >= 3:
		target["discard"] = me.hand.size() - 1
	return target


static func _sacrifices(ps: PlayerState, card: Dictionary) -> Array:
	var need: int = int(card.get("summon", {}).get("sacrifice", 0))
	var pool: Array = []
	for c in ps.champions:
		if str(card.get("color", "")) == "White" or c.color() == str(card.get("color", "")):
			pool.append(c)
	pool.sort_custom(func(a: Champion, b: Champion) -> bool: return a.max_hp() < b.max_hp())
	var uids: Array = []
	for c in pool.slice(0, need):
		uids.append(c.uid)
	return uids


static func _champion_value(card: Dictionary) -> int:
	return int(card.get("hp", 0)) if str(card.get("kind", "")) == "champion" else -1


static func _weakest(foe: PlayerState) -> Champion:
	var weakest: Champion = null
	for c in foe.champions:
		if weakest == null or c.current_hp() < weakest.current_hp():
			weakest = c
	return weakest
