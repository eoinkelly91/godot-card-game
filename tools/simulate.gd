extends SceneTree
## Bot-vs-bot simulation for rough balance numbers and crash hunting.
## Run:  godot --headless -s tools/simulate.gd -- games=200 seed=1 verbose=0
## Prints how often each deck/seat wins and how games end. Tweak Game.DEFAULT_RULES and re-run.


func _init() -> void:
	var args := _parse_args()
	var games: int = int(args.get("games", 100))
	var seed_base: int = int(args.get("seed", 1))
	var verbose: bool = int(args.get("verbose", 0)) == 1
	var cards := CardDB.load_cards()
	var decks := CardDB.load_decks()
	var names: Array = decks.keys()
	if names.size() < 2:
		push_error("Need at least two decks in data/decks.json")
		quit(1)
		return

	var wins := {"deck0": 0, "deck1": 0, "draw": 0}
	var seat_wins := {"first": 0, "second": 0}
	var reasons := {}
	var total_turns := 0
	var castled_games := 0
	for n in games:
		var g := Game.new()
		g.setup([CardDB.build_deck(cards, decks[names[0]]), CardDB.build_deck(cards, decks[names[1]])], seed_base + n)
		g.start()
		var steps := 0
		while not g.finished and steps < 20000:
			steps += 1
			SimpleBot.take_turn(g, g.active)
		if not g.finished:
			push_error("Game %d did not finish (stuck?)" % n)
			print("\n".join(g.log_lines.slice(-30)))
			quit(1)
			return
		total_turns += g.turn
		castled_games += int(g.players[0].castles_used > 0 or g.players[1].castles_used > 0)
		reasons[g.win_reason] = int(reasons.get(g.win_reason, 0)) + 1
		if g.winner == 2:
			wins.draw += 1
		else:
			wins["deck%d" % g.winner] += 1
			seat_wins["first" if g.winner == g.first_player else "second"] += 1
		if verbose:
			print("\n".join(g.log_lines))
			print("==== game %d: %s ====" % [n, g.win_reason])

	print("Games: %d   avg turns (each player's turn counts): %.1f" % [games, float(total_turns) / games])
	print("%s wins: %d   %s wins: %d   draws: %d" % [names[0], wins.deck0, names[1], wins.deck1, wins.draw])
	print("First seat wins: %d   second seat wins: %d" % [seat_wins.first, seat_wins.second])
	print("Games where someone castled: %d" % castled_games)
	print("How games ended: ", reasons)
	quit(0)


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			out[kv[0]] = kv[1]
	return out
