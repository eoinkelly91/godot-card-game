## summon.gd - The Summon step: the Fortress heal, summoning a champion (one per turn; mana and
## sacrifice costs; White sacrifices any color, other colors their own; damage carry-over; placed in the
## encampment area while castled), and playing enchantments. Nothing here is allowed on a first turn
## except summoning.
class_name SummonRules
extends RefCounted


## slot: the board slot (0-5) the card was dropped on, or -1 to let the game choose.
static func summon(g: Game, p: int, hand_index: int, sacrifice_uids: Array = [], discount_on: String = "", slot: int = -1) -> Dictionary:
	var chk: Dictionary = TurnRules.require_turn(g, p)  # summoning is possible at any time during your turn
	if not chk.ok:
		return chk
	var ps: PlayerState = g.players[p]
	if LockRules.is_locked(g, p, "summon"):
		return g._fail("You cannot summon this turn.")
	if ps.summons_this_turn >= g.summons_allowed(p):
		return g._fail("You already summoned %s this turn." % ("two champions" if g.summons_allowed(p) > 1 else "a champion"))
	if hand_index < 0 or hand_index >= ps.hand.size():
		return g._fail("Bad hand index.")
	var card: Dictionary = ps.hand[hand_index]
	if str(card.get("kind", "")) != "champion":
		return g._fail("That is not a champion card.")

	var req: Dictionary = card.get("summon", {})
	var mana_cost: int = int(req.get("mana", 0))
	var sac_count: int = int(req.get("sacrifice", 0))
	if ps.summon_discount > 0:
		var on: String = discount_on if discount_on != "" else ("sacrifice" if sac_count > 0 else "mana")
		if on == "sacrifice":
			sac_count = maxi(0, sac_count - ps.summon_discount)
		else:
			mana_cost = maxi(0, mana_cost - ps.summon_discount)
	if ps.mana < mana_cost:
		return g._fail("Not enough banked mana (%d needed)." % mana_cost)

	var sacrificed: Array[Champion] = []
	if sac_count > 0:
		if sacrifice_uids.size() != sac_count:
			return g._fail("This champion needs exactly %d sacrificed champion(s)." % sac_count)
		for uid in sacrifice_uids:
			var sac: Champion = g._champion_of(ps, int(uid))
			if sac == null or sacrificed.has(sac):
				return g._fail("Bad sacrifice choice.")
			# White can sacrifice any color; every other color sacrifices its own color.
			var any_color: bool = sac.has_ability() and bool(sac.card.ability.get("sacrifice_as_any_color", false))
			if str(card.get("color", "")) != "White" and not any_color and sac.color() != str(card.get("color", "")):
				return g._fail("Sacrifices must be %s champions." % card.get("color", ""))
			if sac.attacked_this_turn:
				return g._fail("%s has just attacked and cannot be sacrificed." % sac.card_name())
			sacrificed.append(sac)
	elif ps.champions.size() >= int(g.rules.board_limit):
		return g._fail("Your play area is full.")
	elif slot >= 0 and (slot >= int(g.rules.board_limit) or ps.slot_champion(slot) != null):
		return g._fail("That slot is already taken.")

	# Pay and resolve.
	ps.mana -= mana_cost
	ps.hand.remove_at(hand_index)
	var carried: int = 0
	var freed: Array = []
	if not sacrificed.is_empty():
		for sac in sacrificed:
			freed.append(sac.slot)
			carried += sac.damage  # every damage counter carries over
			ps.champions.erase(sac)
			ps.discard.append(sac.card)  # sacrificing awards no points to anyone
			DamageRules.release_attached(g, sac)
			g._log("P%d sacrifices %s." % [p, sac.describe()])
		# The new champion takes the slot it was dropped on if that is free (the dropped-on slot of a sacrificed
		# champion counts as free); otherwise the first empty slot; on a full board, the first sacrificed champion's slot.
		if slot < 0 or (ps.slot_champion(slot) != null):
			slot = -1
			for s in int(g.rules.board_limit):
				if ps.slot_champion(s) == null and not freed.has(s):  # slots that were empty before the sacrifice
					slot = s
					break
			if slot < 0:
				slot = int(freed[0])
	var champion: Champion = g.spawn_champion(p, card, slot)
	champion.summoned_turn = g.turn  # a freshly summoned champion cannot attack on its first turn
	HpRules.recalc(g)  # Super Shrink and the like apply to the new champion at once, before carried-over damage is counted
	champion.damage = mini(carried, champion.max_hp())  # damage counters carry over permanently
	ps.summoned_this_turn = true
	ps.summons_this_turn += 1  # sacrifice summons use up a summon too
	var where: String = "the encampment area" if ps.castled else "the active play area"
	g._log("P%d summons %s into %s." % [p, champion.describe(), where])
	if champion.is_destroyed():
		g._log("Carried-over damage destroys %s immediately." % champion.card_name())
		DamageRules.destroy_champion(g, champion, 1 - p, false)  # carried-over damage still scores a point for the opponent
	return g._ok({"uid": champion.uid})


static func play_enchantment(g: Game, p: int, hand_index: int) -> Dictionary:
	var chk: Dictionary = TurnRules.require_turn(g, p)  # like spells: any time during your turn after the Castle step
	if not chk.ok:
		return chk
	var ps: PlayerState = g.players[p]
	if ps.is_first_turn():
		return g._fail("You cannot play enchantments on your first turn.")
	if hand_index < 0 or hand_index >= ps.hand.size():
		return g._fail("Bad hand index.")
	var card: Dictionary = ps.hand[hand_index]
	if str(card.get("kind", "")) != "enchantment":
		return g._fail("That is not an enchantment.")
	if LockRules.is_locked(g, p, "enchantment"):
		return g._fail("Your enchantments are locked.")
	if ps.enchantments.size() >= int(g.rules.enchantment_limit):
		return g._fail("You already have the maximum number of enchantments.")
	var cost: int = int(card.get("cost", 0))
	if ps.mana < cost:
		return g._fail("Not enough banked mana (%d needed)." % cost)
	ps.mana -= cost
	ps.hand.remove_at(hand_index)
	ps.enchantments.append(_running(card))
	g._log("P%d plays enchantment %s." % [p, card.get("name", "?")])
	return g._ok()


## The enchantment as it sits in play: a copy with its remaining turns (the sheet's TURNS).
static func _running(card: Dictionary) -> Dictionary:
	var e: Dictionary = card.duplicate()
	if card.has("turns"):  # a card without TURNS stays in play until removed
		e["turns_left"] = int(card.turns)
	return e


## Plays an enchantment from the hand over one already in play when all enchantment slots are full: the old one is discarded.
static func replace_enchantment(g: Game, p: int, hand_index: int, replace_index: int) -> Dictionary:
	var ps: PlayerState = g.players[p]
	if replace_index < 0 or replace_index >= ps.enchantments.size():
		return g._fail("Pick one of your enchantments to replace.")
	if hand_index < 0 or hand_index >= ps.hand.size() or str(ps.hand[hand_index].get("kind", "")) != "enchantment":
		return g._fail("That is not an enchantment.")
	var chk: String = Preflight.enchantment_problem(g, p, hand_index, true)
	if chk != "":
		return g._fail(chk)
	var old: Dictionary = ps.enchantments[replace_index]
	ps.enchantments.remove_at(replace_index)
	ps.discard.append(g.enchantment_as_card(old))
	g._log("P%d replaces enchantment %s." % [p, old.get("name", "?")])
	var r: Dictionary = play_enchantment(g, p, hand_index)
	if not r.ok:  # cannot happen after the check above, but never lose the old card silently
		ps.enchantments.insert(replace_index, old)
		ps.discard.erase(g.enchantment_as_card(old))
	return r
