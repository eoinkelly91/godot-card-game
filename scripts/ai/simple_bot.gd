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
	elif ps.castles_used == 0 and not ps.is_first_turn() and foe.champions.size() >= ps.champions.size() + 3:
		g.castle(p)

	# Step 3 and the Summon step.
	g.next_step(p)
	if ps.heal_pending:
		var worst: Champion = null
		for c in ps.champions:
			if c.damage > 0 and (worst == null or c.damage > worst.damage):
				worst = c
		if worst != null:
			g.fortress_heal(p, worst.uid)
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

	# Attack step.
	g.next_step(p)
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
			"buff_attack", "lock", "draw", "gain_mana":
				if str(effect.op) != "buff_attack" or not me.castled:
					g.play_spell(p, i, 0)


## Biggest affordable attack by an unused color, at the weakest legal target. Returns false if none worked.
static func _attack_once(g: Game, p: int) -> bool:
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	var options: Array = []
	for c in me.champions:
		if c.color() in me.colors_used:
			continue
		var attacks: Array = c.card.attacks
		for ai in attacks.size():
			if int(attacks[ai].get("mana_cost", 0)) <= me.mana:
				options.append({"uid": c.uid, "index": ai, "damage": int(attacks[ai].damage)})
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.damage > b.damage)
	var target: Dictionary = {"fortress": 1 - p} if (foe.castled or foe.champions.is_empty()) else {"champion": _weakest(foe).uid}
	for opt in options:
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
