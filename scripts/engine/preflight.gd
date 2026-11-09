## preflight.gd - Answers "why can't I do this?" BEFORE the player is walked through target menus.
## Each function returns "" when the action looks possible, or a short reason. The engine still does the
## real checking when the action is performed; this just mirrors its common refusals so the screen can say no early.
## Mana is not checked while the turn is still in the Castle step, because the Fortress and start-of-turn
## effects have not paid out yet.
class_name Preflight
extends RefCounted


static func _basic(g: Game, p: int) -> String:
	if g.finished:
		return "The game is over."
	if g.active != p:
		return "It is not your turn."
	return ""


## Attacker-level reasons when atk_index is -1 (also fails if every attack of the champion is unusable);
## reasons for one specific attack otherwise.
static func attack_problem(g: Game, p: int, attacker: Champion, atk_index: int = -1) -> String:
	var basic: String = _basic(g, p)
	if basic != "":
		return basic
	var me: PlayerState = g.players[p]
	if me.is_first_turn():
		return "Nobody can attack on their first turn: only draw and summon."
	if LockRules.is_locked(g, p, "attack"):
		return "Your attacks are locked."
	if me.castled:
		return "Your champions are encamped and cannot attack."
	if attacker.summoned_turn == g.turn:
		return "%s was summoned this turn and cannot attack until your next turn." % attacker.card_name()
	var attacks: Array = attacker.card.get("attacks", [])
	if attacks.is_empty():
		return "%s has no attack (only an ability)." % attacker.card_name()
	for st in attacker.statuses:
		if str(st.kind) == "no_attack":
			return "%s is chained and cannot attack this turn." % attacker.card_name()
	if attacker.color() in me.colors_used:
		var token: bool = false
		for src in me.extra_attacks:
			if int(src) != attacker.uid:
				token = true
		if not token:
			return "You already attacked with %s this turn." % attacker.color()
	if atk_index >= 0:
		return _attack_cost_problem(g, me, attacker, attacks[atk_index])
	var first: String = ""
	for atk in attacks:
		var prob: String = _attack_cost_problem(g, me, attacker, atk)
		if prob == "":
			return ""
		if first == "":
			first = prob
	return first


static func _attack_cost_problem(g: Game, me: PlayerState, attacker: Champion, atk: Dictionary) -> String:
	if atk.has("requires"):
		var need: int = int(atk.requires.get("self_hp_at_least", 0))
		if attacker.current_hp() < need:
			return "%s needs %d HP or more to use %s (it has %d)." % [attacker.card_name(), need, atk.get("name", "this attack"), attacker.current_hp()]
	var mana: int = int(atk.get("mana_cost", 0))
	if me.mana < mana:
		return "%s costs %d mana (you have %d)." % [atk.get("name", "This attack"), mana, me.mana]
	return ""


static func spell_problem(g: Game, p: int, hand_index: int) -> String:
	var basic: String = _basic(g, p)
	if basic != "":
		return basic
	var me: PlayerState = g.players[p]
	if me.is_first_turn():
		return "You cannot play spells on your first turn."
	if LockRules.is_locked(g, p, "spell"):
		for c in g.players[1 - p].champions:
			if c.has_ability() and str(c.card.ability.get("lock_enemy", "")) == "spell":
				return "%s stops you playing spells while it is in play." % c.card_name()
		return "Your spells are locked this turn."
	var cost: int = int(me.hand[hand_index].get("cost", 0))
	if me.mana < cost:
		return "%s costs %d mana (you have %d)." % [me.hand[hand_index].get("name", "This spell"), cost, me.mana]
	return ""


static func summon_problem(g: Game, p: int, hand_index: int) -> String:
	var basic: String = _basic(g, p)
	if basic != "":
		return basic
	var me: PlayerState = g.players[p]
	if LockRules.is_locked(g, p, "summon"):
		return "You cannot summon this turn."
	if me.summoned_this_turn:
		return "You already summoned a champion this turn."
	var req: Dictionary = me.hand[hand_index].get("summon", {})
	var mana: int = int(req.get("mana", 0))
	if int(req.get("sacrifice", 0)) == 0 and me.summon_discount > 0:
		mana = maxi(0, mana - me.summon_discount)
	if me.mana < mana:
		return "%s needs %d mana (you have %d)." % [me.hand[hand_index].get("name", "This champion"), mana, me.mana]
	return ""


static func enchantment_problem(g: Game, p: int, hand_index: int) -> String:
	var basic: String = _basic(g, p)
	if basic != "":
		return basic
	var me: PlayerState = g.players[p]
	if me.is_first_turn():
		return "You cannot play enchantments on your first turn."
	if LockRules.is_locked(g, p, "enchantment"):
		return "Your enchantments are locked."
	if me.enchantments.size() >= int(g.rules.enchantment_limit):
		return "You already have the maximum number of enchantments (%d)." % int(g.rules.enchantment_limit)
	var cost: int = int(me.hand[hand_index].get("cost", 0))
	if me.mana < cost:
		return "%s costs %d mana (you have %d)." % [me.hand[hand_index].get("name", "This enchantment"), cost, me.mana]
	return ""


## Why the Castle button is unavailable ("" if castling is possible right now).
static func castle_problem(g: Game, p: int) -> String:
	var basic: String = _basic(g, p)
	if basic != "":
		return basic
	var me: PlayerState = g.players[p]
	if g.step == Game.Step.ATTACKED:
		return "You cannot castle after attacking this turn."
	if me.is_first_turn():
		return "You cannot castle on your first turn."
	var lock: String = TurnRules.castle_lock_text(g, me)
	if lock != "":
		return lock
	if me.castled:
		return "You are already castled."
	if me.castles_used >= int(g.rules.castles_per_game):
		return "You have already used your castle this game."
	var active: int = me.active_champions().size()
	var need: int = int(g.rules.castle_active_champions)
	if active != need:
		return "You can only castle with exactly %d champion in the active play area (you have %d)." % [need, active]
	return ""


## "Can still attack with: Red (Molten Harry), Blue (Gluto, Mersoilder)" or why nobody can.
static func attackers_text(g: Game, p: int) -> String:
	var me: PlayerState = g.players[p]
	if g.finished or g.active != p:
		return ""
	if me.is_first_turn():
		return "First turn: only draw and summon, no attacks."
	if me.castled:
		return "Your champions are encamped and cannot attack."
	var by_color: Dictionary = {}
	for c in me.champions:
		if attack_problem(g, p, c, -1) == "":
			if not by_color.has(c.color()):
				by_color[c.color()] = []
			by_color[c.color()].append(c.card_name())
	if by_color.is_empty():
		return "No champions left to attack with this turn."
	var parts: Array = []
	for color in by_color:
		parts.append("%s (%s)" % [color, ", ".join(by_color[color])])
	var used: String = ""
	if not me.colors_used.is_empty():
		used = "   Already attacked with: %s." % ", ".join(me.colors_used)
	return "Champions that can still attack: %s.%s" % ["; ".join(parts), used]
