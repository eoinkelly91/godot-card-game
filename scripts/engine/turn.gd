## turn.gd - The turn sequence. Players simply take turns. A turn is: (forced uncastle, then) draw,
## start-of-turn triggers (Fortress mana, poison, abilities, enchantments), castle/uncastle choice (the Fortress
## heal can be used now too), summon step, attack step, end of turn (hand limit). Also castling itself, the first-turn restrictions, and the automatic
## advance from one step to the next (calling a later step's action moves earlier steps along first).
class_name TurnRules
extends RefCounted


## Starts the turn of g.active.
static func begin(g: Game) -> void:
	g.turn += 1
	if g.turn > int(g.rules.max_turns):
		g._finish(2, "Turn limit reached")
		return
	var p: int = g.active
	var ps: PlayerState = g.players[p]
	ps.reset_for_turn()
	ps.turns_taken += 1
	g.phase = Game.Phase.PLAYING
	g.step = Game.Step.OPEN
	g.spells_this_turn = 0
	g._log("--- Turn %d: Player %d ---" % [g.turn, p])
	if ps.mana >= int(g.rules.economic_goal):
		g._finish(p, "Economic Victory")
		return
	# A castle that has run out ends at the very start of the turn, before drawing.
	if ps.castled:
		if ps.castled_turns >= int(g.rules.max_castled_turns):
			_uncastle(g, p)
			g._log("P%d's castle has run out: the Fortress and encamped champions switch back." % p)
		else:
			ps.castled_turns += 1
	var skip_draw: bool = ps.is_first_turn() and p == g.first_player and bool(g.rules.first_player_skips_first_draw)
	if LockRules.is_locked(g, p, "draw"):
		skip_draw = true
		g._log("P%d cannot draw this turn." % p)
	if not skip_draw:
		var draws: int = int(g.rules.castled_draws) if ps.castled else 1  # castled players draw extra cards
		for i in draws:
			if ps.deck.is_empty():
				g._finish(1 - p, "Decking out")
				return
			ps.hand.append(ps.deck.pop_back())
		g._log("P%d draws %s." % [p, "a card" if draws == 1 else "%d cards (castled)" % draws])
	_run_start_triggers(g, p)  # poison, abilities and the Fortress come first, before any castling decision


# ---------------------------------------------------------------- castling (step 2)

static func castle(g: Game, p: int) -> Dictionary:
	var chk: Dictionary = require_turn(g, p)
	if not chk.ok:
		return chk
	if g.step == Game.Step.ATTACKED:
		return g._fail("You cannot castle after attacking this turn.")
	var ps: PlayerState = g.players[p]
	if ps.is_first_turn():
		return g._fail("You cannot castle on your first turn.")
	var lock: String = castle_lock_text(g, ps)
	if lock != "":
		return g._fail(lock)
	if ps.castled:
		return g._fail("You are already castled.")
	if ps.castles_used >= int(g.rules.castles_per_game):
		return g._fail("You have already used your castle this game.")
	var active: int = ps.active_champions().size()
	if active != int(g.rules.castle_active_champions):
		return g._fail("You can only castle with exactly %d champion in the active play area (you have %d)." % [int(g.rules.castle_active_champions), active])
	ps.castled = true
	ps.castles_used += 1
	ps.castled_turns = 1
	g._log("P%d castles: the Fortress moves to the active play area and the champions are encamped." % p)
	return g._ok()


static func uncastle(g: Game, p: int) -> Dictionary:
	var chk: Dictionary = require_turn(g, p)
	if not chk.ok:
		return chk
	if g.step == Game.Step.ATTACKED:
		return g._fail("You cannot uncastle after attacking this turn.")
	if not g.players[p].castled:
		return g._fail("You are not castled.")
	_uncastle(g, p)
	g._log("P%d uncastles." % p)
	return g._ok()


static func _uncastle(g: Game, p: int) -> void:
	g.players[p].castled = false
	g.players[p].castled_turns = 0


# ---------------------------------------------------------------- steps

## Starts attacking (this closes the castle option for the turn). Attacking does this by itself.
static func next_step(g: Game, p: int) -> Dictionary:
	var chk: Dictionary = require_turn(g, p)
	if not chk.ok:
		return chk
	if g.step == Game.Step.ATTACKED:
		return g._fail("You have already started attacking this turn.")
	_enter_attack_step(g, p)
	return g._ok()


## Start-of-turn triggers, right after the draw. Every player always gets 1 mana (the draw is above); then the
## Fortress ability, poison, champion abilities and enchantments all trigger together.
static func _run_start_triggers(g: Game, p: int) -> void:
	var ps: PlayerState = g.players[p]
	var mark: int = g.log_lines.size()
	g.start_summary_turn = g.turn
	g.start_summary = []
	ps.mana += int(g.rules.mana_per_turn)
	g._log("P%d gains %d mana." % [p, int(g.rules.mana_per_turn)])
	StatusRules.run_start_of_turn(g, p)
	g._check_win()
	g._log("P%d start of turn: mana %d, hand %d." % [p, ps.mana, ps.hand.size()])
	g.start_summary = g.log_lines.slice(mark)


static func _enter_attack_step(g: Game, p: int) -> void:
	g.step = Game.Step.ATTACKED


## The castle lock counts each player's OWN turns: no castling during your first N turns.
## Returns "" when castling is allowed, otherwise what to tell the player (including how many turns are left).
static func castle_lock_text(g: Game, ps: PlayerState) -> String:
	var locked: int = int(g.rules.castle_locked_turns)
	if ps.turns_taken > locked:
		return ""
	var away: int = locked + 1 - ps.turns_taken  # turns from now until your first castle-able turn (this one counts as 0)
	return "You cannot castle during your first %d turns. This is your turn %d: you can castle from your turn %d, %d turn%s from now." % [
		locked, ps.turns_taken, locked + 1, away, "" if away == 1 else "s"]


## Hand limit: discard one chosen card from your hand.
static func discard_hand_card(g: Game, p: int, index: int) -> Dictionary:
	var chk: Dictionary = require_turn(g, p)
	if not chk.ok:
		return chk
	var ps: PlayerState = g.players[p]
	if index < 0 or index >= ps.hand.size():
		return g._fail("Bad card choice.")
	var card: Dictionary = ps.hand[index]
	ps.hand.remove_at(index)
	ps.discard.append(card)
	g._log("P%d discards %s (hand limit)." % [p, str(card.get("name", "a card"))])
	return g._ok()


static func require_turn(g: Game, p: int) -> Dictionary:
	if g.finished:
		return g._fail("The game is over.")
	if g.phase != Game.Phase.PLAYING or g.active != p:
		return g._fail("It is not your turn.")
	return g._ok()


## Checks that it is p's turn and that the turn is in `needed` step, moving earlier steps along first
## when advance is true (so a bot can simply call summon() without calling next_step()).
static func require_step(g: Game, p: int, needed: int, advance: bool = true) -> Dictionary:
	var chk: Dictionary = require_turn(g, p)
	if not chk.ok:
		return chk
	if advance:
		if needed == Game.Step.ATTACKED and g.step == Game.Step.OPEN:
			_enter_attack_step(g, p)
		if g.finished:
			return g._fail("The game is over.")
	if g.step != needed:
		return g._fail("That is not possible in the current step of your turn.")
	return g._ok()


## Ends the turn (also what passing does). The Fortress still triggers if the turn never got that far.
static func end_turn(g: Game, p: int) -> Dictionary:
	var chk: Dictionary = require_turn(g, p)
	if not chk.ok:
		return chk
	var ps: PlayerState = g.players[p]
	ps.pending_minotaur = 0  # an unused Minotaur discard is lost at the end of the turn
	while ps.hand.size() > int(g.rules.max_hand_size):  # hand limit (a player chooses first, see discard_hand_card)
		var di: int = g.rng.randi_range(0, ps.hand.size() - 1)
		g._log("P%d must discard down to %d cards and discards %s." % [p, int(g.rules.max_hand_size), str(ps.hand[di].get("name", "a card"))])
		ps.discard.append(ps.hand[di])
		ps.hand.remove_at(di)
	LockRules.end_of_turn(g, p)
	StatusRules.end_of_turn(g, p)
	g._log("P%d ends their turn." % p)
	g.active = 1 - p
	begin(g)
	return g._ok()
