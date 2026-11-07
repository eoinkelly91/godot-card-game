## turn.gd - The turn sequence. Players simply take turns. A turn is: (forced uncastle, then) draw,
## castle/uncastle choice, start-of-turn triggers (Fortress, poison, abilities), summon step,
## attack step, end of turn. Also castling itself, the first-turn restrictions, and the automatic
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
	g.step = Game.Step.CASTLE
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


# ---------------------------------------------------------------- castling (step 2)

static func castle(g: Game, p: int) -> Dictionary:
	var chk: Dictionary = require_step(g, p, Game.Step.CASTLE, false)
	if not chk.ok:
		return chk
	var ps: PlayerState = g.players[p]
	if ps.is_first_turn():
		return g._fail("You cannot castle on your first turn.")
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
	var chk: Dictionary = require_step(g, p, Game.Step.CASTLE, false)
	if not chk.ok:
		return chk
	if not g.players[p].castled:
		return g._fail("You are not castled.")
	_uncastle(g, p)
	g._log("P%d uncastles." % p)
	return g._ok()


static func _uncastle(g: Game, p: int) -> void:
	g.players[p].castled = false
	g.players[p].castled_turns = 0


# ---------------------------------------------------------------- steps

## Moves the turn on one step (castle step -> summon step -> attack step) and returns ok/fail.
static func next_step(g: Game, p: int) -> Dictionary:
	var chk: Dictionary = require_turn(g, p)
	if not chk.ok:
		return chk
	if g.step == Game.Step.CASTLE:
		_enter_summon_step(g, p)
	elif g.step == Game.Step.SUMMON:
		_enter_attack_step(g, p)
	else:
		return g._fail("You are already in the Attack step.")
	return g._ok()


## Step 3: start-of-turn triggers. Nothing triggers on a player's first turn.
static func _enter_summon_step(g: Game, p: int) -> void:
	g.step = Game.Step.SUMMON
	var ps: PlayerState = g.players[p]
	var mark: int = g.log_lines.size()
	g.start_summary_turn = g.turn
	g.start_summary = []
	if ps.is_first_turn():
		g._log("First turn: the Fortress does not trigger.")
		g.start_summary = g.log_lines.slice(mark)
		return
	if not LockRules.is_locked(g, p, "fortress"):
		ps.mana += int(ps.fortress_def.get("mana_per_turn", 1))
		ps.heal_pending = true
	StatusRules.run_start_of_turn(g, p)
	g._check_win()
	g._log("P%d start of turn: mana %d, hand %d." % [p, ps.mana, ps.hand.size()])
	g.start_summary = g.log_lines.slice(mark)


static func _enter_attack_step(g: Game, p: int) -> void:
	g.step = Game.Step.ATTACK
	g.players[p].heal_pending = false


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
		if needed >= Game.Step.SUMMON and g.step == Game.Step.CASTLE:
			_enter_summon_step(g, p)
		if needed == Game.Step.ATTACK and g.step == Game.Step.SUMMON:
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
	if g.step == Game.Step.CASTLE:
		_enter_summon_step(g, p)
		if g.finished:
			return g._ok()
	LockRules.end_of_turn(g, p)
	StatusRules.end_of_turn(g, p)
	g._log("P%d ends their turn." % p)
	g.active = 1 - p
	begin(g)
	return g._ok()
