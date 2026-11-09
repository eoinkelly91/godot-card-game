## game.gd - The Game object and the public API. Holds all match state (players, whose turn it is, the
## current step of the turn, locks, log), sets up a match (decks, hands, mulligans, coin flip), and decides
## when the game is won. The actual rules live in the files next to this one:
##   turn.gd       turn sequence, castling, first-turn rules, step order
##   summon.gd     Summon step: Fortress heal, summoning, sacrifices, enchantments
##   attack.gd     Attack step: spells, attacks, targeting, encampment rules
##   damage.gd     damage order, applying damage, destroying champions
##   reactions.gd  reactions to attacks
##   locks.gd      locks (summon, spells, attacks, ...) counted in the affected player's turns
##   statuses.gd   poison, attack buffs, start-of-turn abilities
## Every player action returns {"ok": true, ...} or {"ok": false, "error": "..."}.
## Rule numbers live in `rules` (DEFAULT_RULES) so they can be tweaked during playtesting.
class_name Game
extends RefCounted

signal logged(text: String)

enum Phase { SETUP, PLAYING, ENDED }
# A turn has no steps any more: it is simply the player's turn. The only thing tracked is whether the player has
# started attacking (castling is only possible before the first attack of the turn).
enum Step { OPEN, ATTACKED }

const DEFAULT_RULES := {
	"start_hand": 7,
	"start_mana": 3,
	"max_mulligans": 2,
	"board_limit": 6,                        # champions in the active play area, and in the encampment area
	"enchantment_limit": 3,
	"annihilation_goal": 10,
	"economic_goal": 30,
	"max_hand_size": 10,                     # more cards than this at the end of your turn: you discard down to it
	"castles_per_game": 1,
	"castle_locked_turns": 5,                # no castling during a player's first N own turns
	"castle_active_champions": 1,            # you may only castle with exactly this many champions in the active play area
	"castled_draws": 2,                      # cards drawn at the start of a turn while castled (1 otherwise)
	"max_castled_turns": 3,                  # own turns, counting the turn you castle on
	"first_player_skips_first_draw": false,
	"max_turns": 400,                        # safety net for simulations (counts every player's turn)
	"fortress": {"hp": 500},   # the default Fortress; a deck's Fortress card replaces it (hp and its ability)
	"mana_per_turn": 1,        # every player always gets this much mana at the start of their turn
}

var rules: Dictionary = {}
var rng := RandomNumberGenerator.new()
var players: Array[PlayerState] = []
var turn: int = 0               # counts every player's turn
var active: int = 0             # whose turn it is
var first_player: int = 0
var phase: int = Phase.SETUP
var step: int = Step.OPEN
var spells_this_turn: int = 0
var start_summary: Array = []      # log lines from the start-of-turn triggers of the current turn
var start_summary_turn: int = -1
var finished: bool = false
var winner: int = -1            # 0 or 1; 2 = draw
var win_reason: String = ""
var locks: Array = []           # {"player", "what", "turns_left"}
var log_lines: Array[String] = []
var forced_coins: Array = []    # tests: true/false results consumed by flip_coin() before real randomness
var _next_uid: int = 1


func _init(p_rules: Dictionary = {}) -> void:
	rules = DEFAULT_RULES.duplicate(true)
	for key in p_rules:
		if key == "fortress":
			(rules["fortress"] as Dictionary).merge(p_rules[key], true)
		else:
			rules[key] = p_rules[key]


# ---------------------------------------------------------------- setup

## decks: Array of two Arrays of card dictionaries. first_player -1 = coin flip.
func setup(decks: Array, seed_value: int = 0, p_first_player: int = -1, fortress_defs: Array = []) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	players.clear()
	locks.clear()
	for i in 2:
		var ps := PlayerState.new(i)
		var fdef: Dictionary = (rules["fortress"] as Dictionary).duplicate()
		if i < fortress_defs.size():
			fdef.merge(fortress_defs[i], true)
		ps.fortress_def = fdef
		ps.fortress_hp = int(fdef.get("hp", 500))
		ps.mana = int(rules.start_mana)
		ps.deck = (decks[i] as Array).duplicate()
		_shuffle(ps.deck)
		_draw_raw(ps, int(rules.start_hand))
		players.append(ps)
	first_player = p_first_player if p_first_player >= 0 else rng.randi_range(0, 1)
	active = first_player
	phase = Phase.SETUP
	finished = false
	winner = -1
	_log("Player %d wins the coin flip and goes first." % first_player)


func mulligan(p: int) -> Dictionary:
	if phase != Phase.SETUP:
		return _fail("Mulligans are only available during setup.")
	var ps := players[p]
	if ps.mulligans >= int(rules.max_mulligans):
		return _fail("No mulligans left; you must keep this hand.")
	ps.mulligans += 1
	ps.deck.append_array(ps.hand)
	ps.hand.clear()
	_shuffle(ps.deck)
	_draw_raw(ps, int(rules.start_hand))
	return _ok()


func start() -> void:
	turn = 0
	active = first_player
	TurnRules.begin(self)


# ---------------------------------------------------------------- player actions (delegates)
# A turn: [forced uncastle], draw, castle/uncastle, start-of-turn triggers, summon step, attack step, end.

func castle(p: int) -> Dictionary:
	return TurnRules.castle(self, p)


## " (1)", " (2)" when a player has several champions with the same name in play, so they can be told apart.
func champion_tag(c: Champion) -> String:
	var same: Array = []
	for other in players[c.owner].champions:
		if other.card_name() == c.card_name():
			same.append(other)
	if same.size() < 2:
		return ""
	return " (%d)" % (same.find(c) + 1)


## Champion.describe() with the (1)/(2) tag after the name, for menus.
func describe_champion(c: Champion) -> String:
	var d: String = c.describe()
	var t: String = champion_tag(c)
	if t == "":
		return d
	var at: int = d.find(c.card_name())
	if at < 0:
		return d + t
	var end: int = at + c.card_name().length()
	return d.substr(0, end) + t + d.substr(end)


func discard_hand_card(p: int, index: int) -> Dictionary:
	return TurnRules.discard_hand_card(self, p, index)


func uncastle(p: int) -> Dictionary:
	return TurnRules.uncastle(self, p)


## Moves the turn on one step: castle step -> start-of-turn triggers and summon step -> attack step.
## Calling a later step's action does this for you.
func next_step(p: int) -> Dictionary:
	return TurnRules.next_step(self, p)


func summon(p: int, hand_index: int, sacrifice_uids: Array = [], discount_on: String = "") -> Dictionary:
	return SummonRules.summon(self, p, hand_index, sacrifice_uids, discount_on)


func play_enchantment(p: int, hand_index: int) -> Dictionary:
	return SummonRules.play_enchantment(self, p, hand_index)


func play_spell(p: int, hand_index: int, effect_index: int, target: Dictionary = {}) -> Dictionary:
	return AttackRules.play_spell(self, p, hand_index, effect_index, target)


func attack(p: int, attacker_uid: int, attack_index: int, target: Dictionary,
		spell_picks: Array = [], enchant_order: Array = []) -> Dictionary:
	return AttackRules.attack(self, p, attacker_uid, attack_index, target, spell_picks, enchant_order)


func end_turn(p: int) -> Dictionary:
	return TurnRules.end_turn(self, p)


## Passing is the same as ending your turn.
func pass_action(p: int) -> Dictionary:
	return TurnRules.end_turn(self, p)


# ---------------------------------------------------------------- queries and helpers

func calc_damage(attacker: Champion, atk: Dictionary, target: Champion, spell_bonus: int,
		enchant_order: Array = []) -> int:
	return DamageRules.calc(self, attacker, atk, target, spell_bonus, enchant_order)


func add_lock(affected_player: int, what: String, turns: int) -> void:
	LockRules.add(self, affected_player, what, turns)


func _is_locked(p: int, what: String) -> bool:
	return LockRules.is_locked(self, p, what)


## Puts a champion straight onto the board, ignoring costs and limits (used by summon, tests and sims).
func spawn_champion(p: int, card: Dictionary, slot: int = -1) -> Champion:
	var champion := Champion.new(_next_uid, card, p)
	_next_uid += 1
	if slot < 0 or slot > players[p].champions.size():
		players[p].champions.append(champion)
	else:
		players[p].champions.insert(slot, champion)
	return champion


func _champion_of(ps: PlayerState, uid: int) -> Champion:
	for c in ps.champions:
		if c.uid == uid:
			return c
	return null


func _find_champion(uid: int) -> Champion:
	for ps in players:
		var c := _champion_of(ps, uid)
		if c != null:
			return c
	return null


func describe_state() -> String:
	var lines: Array[String] = []
	for ps in players:
		lines.append("P%d%s: fortress %d, mana %d, hand %d, deck %d, discard %d, kills %d" % [
			ps.index, " (castled)" if ps.castled else "", ps.fortress_hp, ps.mana, ps.hand.size(),
			ps.deck.size(), ps.discard.size(), ps.kills])
		for c in ps.champions:
			lines.append("    %s%s" % [c.describe(), " [encamped]" if ps.castled else ""])
		for e in ps.enchantments:
			lines.append("    enchantment: " + str(e.get("name", "?")))
	return "\n".join(lines)


# ---------------------------------------------------------------- win conditions

## Siege (enemy Fortress at 0) and Annihilation (10 enemy champions defeated). Both at once = draw.
## Economic Victory is checked at the very start of a turn (turn.gd); decking out when drawing.
func _check_win() -> void:
	if finished:
		return
	var met: Array = [false, false]
	for i in 2:
		if players[1 - i].fortress_hp <= 0 or players[i].kills >= int(rules.annihilation_goal):
			met[i] = true
	if met[0] and met[1]:
		_finish(2, "Both players met a win condition")
	elif met[0]:
		_finish(0, "Siege or Annihilation")
	elif met[1]:
		_finish(1, "Siege or Annihilation")


func _finish(winner_index: int, reason: String) -> void:
	if finished:
		return
	finished = true
	winner = winner_index
	win_reason = reason
	phase = Phase.ENDED
	if winner_index == 2:
		_log("The game is a draw: %s." % reason)
	else:
		_log("Player %d wins: %s." % [winner_index, reason])


# ---------------------------------------------------------------- internals

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _draw_raw(ps: PlayerState, count: int) -> void:
	for i in count:
		if ps.deck.is_empty():
			return
		ps.hand.append(ps.deck.pop_back())


## Flips one coin: true = Heads. Tests can queue results in forced_coins.
func flip_coin() -> bool:
	if not forced_coins.is_empty():
		return bool(forced_coins.pop_front())
	return rng.randi_range(0, 1) == 1


func _log(text: String) -> void:
	log_lines.append(text)
	logged.emit(text)


var hp_recalc_busy: bool = false


func _ok(extra: Dictionary = {}) -> Dictionary:
	HpRules.recalc(self)  # HP changes (Gaia, Super Shrink, Fusion, Power Source) are applied after every action
	var r: Dictionary = {"ok": true}
	r.merge(extra)
	return r


func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
