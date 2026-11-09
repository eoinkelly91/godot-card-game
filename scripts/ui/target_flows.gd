## target_flows.gd - Asks the player for the targets and choices that spells, attacks and summons need, and
## builds the dictionaries the engine expects. It only offers valid choices, so what it returns is accepted
## by the engine (the tests check this for every real spell). The "chooser" is any object with
##   choose(title: String, options: Array, min_n: int, max_n: int) -> Variant
## where options are {"label": String, "value": Variant}; it returns an Array of the chosen values, or null
## if the player cancelled. The hotseat screen is the real chooser; tests use an automatic one.
## Results: {"target": Dictionary} | {"cancelled": true} | {"error": String}
class_name TargetFlows
extends RefCounted

var g: Game
var chooser: Object


func _init(p_game: Game, p_chooser: Object) -> void:
	g = p_game
	chooser = p_chooser


static func _t(target: Dictionary) -> Dictionary:
	return {"target": target}


static func _cancel() -> Dictionary:
	return {"cancelled": true}


static func _err(text: String) -> Dictionary:
	return {"error": text}


func _champs(list: Array, skip: Array = []) -> Array:
	var out: Array = []
	for c in list:
		if not skip.has(c):
			out.append({"label": g.describe_champion(c) + (" (damage %d)" % c.damage if c.damage > 0 else ""), "value": c.uid})
	return out


## One value or null (cancelled).
func _one(title: String, options: Array) -> Variant:
	var res: Variant = await chooser.choose(title, options, 1, 1)
	if res == null or (res as Array).is_empty():
		return null
	return (res as Array)[0]


## An array of values (possibly empty) or null (cancelled).
func _many(title: String, options: Array, min_n: int, max_n: int) -> Variant:
	return await chooser.choose(title, options, min_n, max_n)


func _enemy_champions_ok(p: int) -> String:
	var foe: PlayerState = g.players[1 - p]
	if foe.castled:
		return "The opponent's champions are encamped and cannot be targeted."
	if foe.champions.is_empty():
		return "The opponent has no champions."
	return ""


# ---------------------------------------------------------------- spells

func spell_target(p: int, hand_index: int, effect_index: int) -> Dictionary:
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	var card: Dictionary = me.hand[hand_index]
	var effect: Dictionary = card.effects[effect_index]
	var op: String = str(effect.get("op", ""))
	match op:
		"lock", "draw", "gain_mana", "buff_attack", "drain_mana", "drain_mana_per_card", "gain_mana_per_enchantment", "opponent_discards", \
		"summon_discount", "wizardry_draw", "type_attack_bonus", "reduce_enemy_attacks", "damage_all_enemies", "shuffle_weak_champions":
			return _t({})
		"attach":  # Warrior Idol, Fusion, Power Source: one of your own champions (encamped ones too)
			if me.champions.is_empty():
				return _err("You have no champions to attach this card to.")
			var at: Variant = await _one("Attach %s to which of your champions?" % str(card.get("name", "this card")), _champs(me.champions))
			return _cancel() if at == null else _t({"champion": at})
		"mystery_remove":
			var carrying: Array = foe.champions.filter(func(c: Champion) -> bool: return not c.attached.is_empty())
			if foe.castled:
				return _err("The opponent's champions are encamped and cannot be targeted.")
			if carrying.is_empty():
				return _err("None of the opponent's champions has a card attached.")
			var mv: Variant = await _one("Remove the attached cards from which champion?", _champs(carrying))
			return _cancel() if mv == null else _t({"champion": mv})
		"return_card":  # Galachs Will: a spell (effect 1) or an enchantment (effect 2) from your discard pile
			var want: String = str(effect.get("kind", "spell"))
			var opts4: Array = []
			for i in me.discard.size():
				if str(me.discard[i].get("kind", "")) == want:
					opts4.append({"label": str(me.discard[i].get("name", "?")), "value": i})
			if opts4.is_empty():
				return _err("You have no %s cards in your discard pile." % want)
			var rcd: Variant = await _one("Return which %s to your hand?" % want, opts4)
			return _cancel() if rcd == null else _t({"discard_index": rcd})
		"damage":
			if foe.castled or foe.champions.is_empty():
				return _t({"fortress": 1 - p})
			var d: Variant = await _one("Damage which champion?", _champs(foe.champions))
			return _cancel() if d == null else _t({"champion": d})
		"poison", "no_attack":
			var err: String = _enemy_champions_ok(p)
			if err != "":
				return _err(err)
			var e: Variant = await _one("Which enemy champion?", _champs(foe.champions))
			return _cancel() if e == null else _t({"champion": e})
		"heal", "cleanse", "bonus_damage":
			if me.champions.is_empty():
				return _err("You have no champions.")
			var title: String = "Which of your champions?"
			if op == "bonus_damage":
				title = "Which champion gets +%d on its next attack this turn?" % int(effect.get("amount", 0))
			var pool: Array = me.champions
			if op == "bonus_damage":  # only champions that can attack this turn (not just summoned, chained, encamped)
				pool = me.champions.filter(func(c: Champion) -> bool: return Preflight.attack_problem(g, p, c) == "")
				if pool.is_empty():
					return _err("None of your champions can attack this turn, so the bonus would be wasted.")
			var h: Variant = await _one(title, _champs(pool))
			return _cancel() if h == null else _t({"champion": h})
		"move_counters":
			return await _move_counters(p, int(effect.get("count", 3)))
		"remove_enchantment":
			if foe.enchantments.is_empty():
				return _err("The opponent has no enchantments.")
			var opts: Array = []
			for i in foe.enchantments.size():
				opts.append({"label": str(foe.enchantments[i].get("name", "?")), "value": i})
			var r: Variant = await _one("Remove which enchantment?", opts)
			return _cancel() if r == null else _t({"enchantment": r})
		"move_all_damage":
			var damaged: Array = []
			for c in me.champions:
				if c.damage > 0:
					damaged.append(c)
			if damaged.is_empty() or me.champions.size() < 2:
				return _err("You need a damaged champion and another champion to receive the damage.")
			var from_uid: Variant = await _one("Take all the damage from which champion?", _champs(damaged))
			if from_uid == null:
				return _cancel()
			var from_c: Champion = g._champion_of(me, int(from_uid))
			var to_uid: Variant = await _one("Move it onto which champion? (all damage counters move)", _champs(me.champions, [from_c]))
			return _cancel() if to_uid == null else _t({"from": from_uid, "to": to_uid})
		"damage_many":
			var err2: String = _enemy_champions_ok(p)
			if err2 != "":
				return _err(err2)
			var need: int = mini(int(effect.get("targets", 3)), foe.champions.size())
			var picked: Variant = await _many("Pick %d different enemy champion(s)" % need, _champs(foe.champions), need, need)
			return _cancel() if picked == null else _t({"champions": picked})
		"repair_fortress":
			var cards: Array = _hand_options(me, hand_index, "")
			var chosen: Variant = await _many("Discard how many cards? Each repairs the Fortress by %d." % int(effect.get("per_card", 50)), cards, 0, cards.size())
			return _cancel() if chosen == null else _t({"discard_indices": chosen})
		"return_champion":
			var opts2: Array = []
			for i in me.discard.size():
				if str(me.discard[i].get("kind", "")) == "champion":
					opts2.append({"label": str(me.discard[i].get("name", "?")), "value": i})
			if opts2.is_empty():
				return _err("You have no champion cards in your discard pile.")
			var rc: Variant = await _one("Return which champion to your hand?", opts2)
			return _cancel() if rc == null else _t({"discard_index": rc})
		"discard_spells_for_mana":
			var spells: Array = _hand_options(me, hand_index, "spell")
			var chosen2: Variant = await _many("Discard which spells? Each gives %d mana." % int(effect.get("per_card", 2)), spells, 0, spells.size())
			return _cancel() if chosen2 == null else _t({"discard_indices": chosen2})
		"discard_enchantment_for_mana":
			var opts3: Array = []
			for i in me.enchantments.size():
				opts3.append({"label": "In play: " + str(me.enchantments[i].get("name", "?")), "value": {"enchantment": i}})
			for i in me.hand.size():
				if i != hand_index and str(me.hand[i].get("kind", "")) == "enchantment":
					opts3.append({"label": "In hand: " + str(me.hand[i].get("name", "?")), "value": {"hand_index": i}})
			if opts3.is_empty():
				return _err("You have no enchantment to discard.")
			var re: Variant = await _one("Discard which enchantment? (+%d mana)" % int(effect.get("amount", 5)), opts3)
			return _cancel() if re == null else _t(re)
		"rearrange_top":
			var n: int = mini(int(effect.get("count", 5)), me.deck.size())
			if n < 2:
				return _t({})
			var remaining: Array = []
			for i in n:
				remaining.append({"label": str(me.deck[me.deck.size() - 1 - i].get("name", "?")), "value": i})
			var order: Array = []
			while remaining.size() > 1:
				var next_card: Variant = await _one("Card number %d from the top (the rest follow)" % (order.size() + 1), remaining)
				if next_card == null:
					return _cancel()
				order.append(next_card)
				for j in remaining.size():
					if remaining[j].value == next_card:
						remaining.remove_at(j)
						break
			order.append(remaining[0].value)
			return _t({"order": order})
	return _err("This spell effect is not supported by the screen yet: " + op)


## Hand cards as options, never the spell being played; kind "" = every card.
func _hand_options(me: PlayerState, played_index: int, kind: String) -> Array:
	var out: Array = []
	for i in me.hand.size():
		if i == played_index:
			continue
		if kind == "" or str(me.hand[i].get("kind", "")) == kind:
			out.append({"label": str(me.hand[i].get("name", "?")), "value": i})
	return out


func _move_counters(p: int, count: int) -> Dictionary:
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	var err: String = _enemy_champions_ok(p)
	if err != "":
		return _err(err)
	var remaining: int = count
	var taken: Dictionary = {}
	var moves: Array = []
	for _i in count:
		if remaining <= 0:
			break
		var from_opts: Array = []
		for c in me.champions:
			var free: int = int(c.damage / 10) - int(taken.get(c.uid, 0))
			if free > 0:
				from_opts.append({"label": "%s (%d counters)" % [g.describe_champion(c), free], "value": c.uid})
		if from_opts.is_empty():
			break
		if not moves.is_empty():
			from_opts.append({"label": "(done)", "value": -1})
		var from_uid: Variant = await _one("Take counters from which champion? (%d left to move)" % remaining, from_opts)
		if from_uid == null:
			return _cancel()
		if int(from_uid) == -1:
			break
		var to_uid: Variant = await _one("Give them to which enemy champion?", _champs(foe.champions))
		if to_uid == null:
			return _cancel()
		var from_c: Champion = g._champion_of(me, int(from_uid))
		var avail: int = mini(remaining, int(from_c.damage / 10) - int(taken.get(from_c.uid, 0)))
		var n_opts: Array = []
		for n in range(1, avail + 1):
			n_opts.append({"label": "%d counter(s)" % n, "value": n})
		var n_pick: Variant = await _one("How many counters?", n_opts)
		if n_pick == null:
			return _cancel()
		taken[from_c.uid] = int(taken.get(from_c.uid, 0)) + int(n_pick)
		remaining -= int(n_pick)
		moves.append({"from": from_uid, "to": to_uid, "counters": int(n_pick)})
	if moves.is_empty():
		return _err("You have no damage counters to move.")
	return _t({"moves": moves})


# ---------------------------------------------------------------- attacks

func attack_target(p: int, attacker: Champion, atk_index: int) -> Dictionary:
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	var atk: Dictionary = attacker.card.attacks[atk_index]
	var target: Dictionary = {}
	if bool(atk.get("no_target", false)):
		return _t({})
	if foe.castled or foe.champions.is_empty():
		target = {"fortress": 1 - p}
	else:
		var legal: Array = []  # champions this attacker is allowed to attack (not Gnome if it has too much HP)
		for fc in foe.champions:
			if not (fc.has_ability() and fc.card.ability.has("immune_to_attackers_max_hp_over") \
					and attacker.max_hp() > int(fc.card.ability.immune_to_attackers_max_hp_over)):
				legal.append(fc)
		if legal.is_empty():
			return _err("%s cannot attack the opponent's champions (it has too many HP for Gnome)." % attacker.card_name())
		var forced: Champion = null  # Duel: the dueled champion must attack its duelist
		for st in attacker.statuses:
			if str(st.kind) == "duel":
				forced = g._champion_of(foe, int(st.duelist))
		if forced != null:
			target = {"champion": forced.uid}
		elif int(atk.get("multi_target", 0)) > 1 and legal.size() >= 2:
			var need: int = mini(int(atk.multi_target), legal.size())
			var picked: Variant = await _many("%s: pick %d different champions" % [atk.get("name", "Attack"), need], _champs(legal), need, need)
			if picked == null:
				return _cancel()
			target = {"champions": picked}
		else:
			var one: Variant = await _one("Attack which champion?", _champs(legal))
			if one == null:
				return _cancel()
			target = {"champion": one}
	if atk.has("optional_discard_bonus") and not me.hand.is_empty():
		var opts: Array = _hand_options(me, -1, "")
		var d: Variant = await _many("Discard a card for +%d damage? (pick none to skip)" % int(atk.optional_discard_bonus), opts, 0, 1)
		if d == null:
			return _cancel()
		if not (d as Array).is_empty():
			target["discard"] = (d as Array)[0]
	return _t(target)


# ---------------------------------------------------------------- summoning

## Returns {"sacrifices": Array} | {"cancelled": true} | {"error": ...}
func summon_choices(p: int, hand_index: int) -> Dictionary:
	var me: PlayerState = g.players[p]
	var card: Dictionary = me.hand[hand_index]
	var need: int = int(card.get("summon", {}).get("sacrifice", 0))
	if need > 0:
		need = maxi(0, need - me.summon_discount)
	if need == 0:
		return {"sacrifices": []}
	var pool: Array = []
	for c in me.champions:
		var any_color: bool = c.has_ability() and bool(c.card.ability.get("sacrifice_as_any_color", false))
		if str(card.get("color", "")) == "White" or any_color or c.color() == str(card.get("color", "")):
			pool.append(c)
	if pool.size() < need:
		return _err("You need %d champion(s) of the right color to sacrifice." % need)
	var picked: Variant = await _many("Sacrifice %d champion(s) for %s (their damage carries over)" % [need, card.get("name", "?")], _champs(pool), need, need)
	return _cancel() if picked == null else {"sacrifices": picked}
