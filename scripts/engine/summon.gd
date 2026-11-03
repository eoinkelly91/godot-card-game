## summon.gd - The Summon step: the Fortress heal, summoning a champion (one per turn; mana and
## sacrifice costs; White sacrifices any color, other colors their own; damage carry-over; placed in the
## encampment area while castled), and playing enchantments. Nothing here is allowed on a first turn
## except summoning.
class_name SummonRules
extends RefCounted


static func fortress_heal(g: Game, p: int, champion_uid: int) -> Dictionary:
	var chk: Dictionary = TurnRules.require_step(g, p, Game.Step.SUMMON)
	if not chk.ok:
		return chk
	var ps: PlayerState = g.players[p]
	if not ps.heal_pending:
		return g._fail("Your Fortress has no heal available.")
	var champion: Champion = g._champion_of(ps, champion_uid)  # encamped champions can be healed too
	if champion == null:
		return g._fail("Pick one of your own champions.")
	champion.damage = maxi(0, champion.damage - int(ps.fortress_def.get("heal", 20)))
	ps.heal_pending = false
	g._log("P%d Fortress heals %s." % [p, champion.describe()])
	return g._ok()


## sacrifice_uids: the champions to sacrifice, for cards whose summon requires sacrifices.
## discount_on: "sacrifice" or "mana" says what Mumified takes one off; by default it is the sacrifices if the
## card needs any, otherwise the mana.
static func summon(g: Game, p: int, hand_index: int, sacrifice_uids: Array = [], discount_on: String = "") -> Dictionary:
	var chk: Dictionary = TurnRules.require_step(g, p, Game.Step.SUMMON)
	if not chk.ok:
		return chk
	var ps: PlayerState = g.players[p]
	if LockRules.is_locked(g, p, "summon"):
		return g._fail("You cannot summon this turn.")
	if ps.summoned_this_turn:
		return g._fail("You already summoned a champion this turn.")
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
			sacrificed.append(sac)
	elif ps.champions.size() >= int(g.rules.board_limit):
		return g._fail("Your play area is full.")

	# Pay and resolve.
	ps.mana -= mana_cost
	ps.hand.remove_at(hand_index)
	var carried: int = 0
	var slot: int = ps.champions.size()
	if not sacrificed.is_empty():
		slot = ps.champions.find(sacrificed[0])
		for sac in sacrificed:
			carried += sac.damage  # every damage counter carries over
			ps.champions.erase(sac)
			ps.discard.append(sac.card)  # sacrificing awards no points to anyone
			g._log("P%d sacrifices %s." % [p, sac.describe()])
		slot = mini(slot, ps.champions.size())
	var champion: Champion = g.spawn_champion(p, card, slot)
	champion.damage = mini(carried, champion.max_hp())  # damage counters carry over permanently
	ps.summoned_this_turn = true  # sacrifice summons use the turn's summon (revisit later)
	var where: String = "the encampment area" if ps.castled else "the active play area"
	g._log("P%d summons %s into %s." % [p, champion.describe(), where])
	if champion.is_destroyed():
		g._log("Carried-over damage destroys %s immediately." % champion.card_name())
		DamageRules.destroy_champion(g, champion, 1 - p, false)  # carried-over damage still scores a point for the opponent
	return g._ok({"uid": champion.uid})


static func play_enchantment(g: Game, p: int, hand_index: int) -> Dictionary:
	var chk: Dictionary = TurnRules.require_step(g, p, Game.Step.SUMMON)
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
	ps.enchantments.append(card)
	g._log("P%d plays enchantment %s." % [p, card.get("name", "?")])
	return g._ok()
