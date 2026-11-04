extends SceneTree
## Headless check of the hotseat screen: loads the scene, plays through setup and mulligans, drives turns,
## and runs every real spell and the special attacks through TargetFlows into the engine.
## Run:  godot --headless -s tests/ui_smoke.gd

var passed: int = 0
var failed: int = 0
var ui
var cards: Dictionary


func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("      failed: ", msg)


## Automatic player: takes the first valid options.
func auto(_title: String, options: Array, min_n: int, _max_n: int) -> Variant:
	var out: Array = []
	for i in mini(min_n, options.size()):
		out.append(options[i].value)
	return out


## The test script is the chooser for TargetFlows in the flow tests.
func choose(title: String, options: Array, min_n: int, max_n: int) -> Variant:
	return auto(title, options, min_n, max_n)


func _initialize() -> void:
	_run()


func _run() -> void:
	cards = CardDB.load_cards()
	var scene: PackedScene = load("res://scenes/main.tscn")
	ui = scene.instantiate()
	root.add_child(ui)
	await process_frame  # lets the scene run its _ready
	ui.auto_chooser = Callable(self, "auto")
	await _test_setup_and_mulligan()
	await _test_bot_turns_render()
	await _test_every_spell_flow()
	await _test_attack_flows()
	await _test_hand_and_champion_clicks()
	_test_card_views()
	print("\n%d UI checks passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _test_setup_and_mulligan() -> void:
	var names: Array = ui.decks.keys()
	ui.start_new_game(names[0], names[1], 5)
	check(ui.game != null and ui.game.players[0].hand.size() == 7, "a game starts with 7-card hands")
	check(ui._cover.visible, "the cover hides the first hand")
	ui._on_reveal()
	check(ui._mull.visible and ui.mulligan_player == 0, "player 0 sees the mulligan screen")
	ui._on_mulligan()
	check(ui.game.players[0].mulligans == 1, "player 0 can mulligan")
	ui._on_keep()
	ui._on_reveal()
	check(ui.mulligan_player == 1, "then player 1")
	ui._on_keep()
	check(ui.mulligan_player == -1 and ui.game.turn == 1, "after both keep, the game starts")
	check(ui._cover.visible, "the first turn starts behind the cover")
	ui._on_reveal()
	check(ui.viewer == ui.game.active and not ui._cover.visible, "revealing shows the active player's turn")
	check(not ui._btn_end.disabled, "End turn is enabled")


func _test_bot_turns_render() -> void:
	var g: Game = ui.game
	for i in 30:
		if g.finished:
			break
		SimpleBot.take_turn(g, g.active)
		ui.viewer = g.active
		ui._cover.visible = false
		ui.refresh()
	check(ui._opp_box.get_child_count() > 0 and ui._me_box.get_child_count() > 0, "the boards render after many turns")
	check(ui._log.get_parsed_text().length() > 100, "the log fills up")


func _fresh_state() -> Game:
	var filler: Array = []
	for i in 60:
		filler.append(cards["syranite"])
	var g := Game.new()
	g.setup([filler.duplicate(), filler.duplicate()], 3, 0)
	g.start()
	g.players[0].turns_taken = 2
	g.players[1].turns_taken = 2
	for p in 2:
		g.players[p].hand.clear()
		g.players[p].mana = 10
	var a := g.spawn_champion(0, cards["amustas"])
	a.damage = 60
	g.spawn_champion(0, cards["gob"])
	g.spawn_champion(0, cards["syranite"])
	g.spawn_champion(1, cards["amustas"])
	g.spawn_champion(1, cards["gob"])
	g.spawn_champion(1, cards["syranite"])
	g.players[0].enchantments = [cards["field_medics"]]
	g.players[1].enchantments = [cards["battlements"]]
	g.players[0].discard = [cards["amustas"], cards["heal"]]
	return g


func _test_every_spell_flow() -> void:
	var count: int = 0
	for id in cards:
		var card: Dictionary = cards[id]
		if str(card.kind) != "spell":
			continue
		for ei in card.effects.size():
			var g := _fresh_state()
			g.players[0].hand = [card, cards["syranite"], cards["crimson_wave"], cards["battlements"]]
			var flows := TargetFlows.new(g, self)
			var tf: Dictionary = await flows.spell_target(0, 0, ei)
			check(tf.has("target"), "%s effect %d: the flow builds a target (%s)" % [id, ei, str(tf)])
			if tf.has("target"):
				var res: Dictionary = g.play_spell(0, 0, ei, tf.target)
				check(res.ok, "%s effect %d: the engine accepts it (%s)" % [id, ei, str(res.get("error", ""))])
				count += 1
	check(count == 18, "all 18 spell effects went through (%d)" % count)
	# A flow reports problems instead of crashing: no damaged champion for Mist of Despair.
	var g2 := _fresh_state()
	for c in g2.players[0].champions:
		c.damage = 0
	g2.players[0].hand = [cards["mist_of_despair"]]
	var f2 := TargetFlows.new(g2, self)
	var r2: Dictionary = await f2.spell_target(0, 0, 0)
	check(r2.has("error"), "Mist of Despair without damage counters gives a message")
	var g3 := _fresh_state()
	g3.players[1].castled = true
	g3.players[0].hand = [cards["spirit_chain"]]
	var r3: Dictionary = await TargetFlows.new(g3, self).spell_target(0, 0, 0)
	check(r3.has("error"), "targeting encamped champions gives a message")


func _test_attack_flows() -> void:
	var g := _fresh_state()
	var eo: Champion = g.spawn_champion(0, cards["elite_o"])
	var flows := TargetFlows.new(g, self)
	var tf: Dictionary = await flows.attack_target(0, eo, 0)
	check(tf.target.has("champions") and tf.target.champions.size() == 2, "Dual Spear asks for two champions")
	check(g.attack(0, eo.uid, 0, tf.target).ok, "and the engine accepts them")
	var g2 := _fresh_state()
	var st: Champion = g2.spawn_champion(0, cards["stanter"])
	g2.players[0].hand = [cards["syranite"]]
	var tf2: Dictionary = await TargetFlows.new(g2, self).attack_target(0, st, 0)
	check(tf2.target.has("champion") and not tf2.target.has("discard"), "Staff Attack's discard is optional (auto player skips it)")
	var g3 := _fresh_state()
	var harry: Champion = g3.spawn_champion(0, cards["molten_harry"])
	var tf3: Dictionary = await TargetFlows.new(g3, self).attack_target(0, harry, 1)
	check(tf3.target.is_empty(), "Volcanic Horn needs no target")
	var g4 := _fresh_state()
	g4.players[1].castled = true
	var tf4: Dictionary = await TargetFlows.new(g4, self).attack_target(0, g4.players[0].champions[2], 0)
	check(tf4.target.has("fortress"), "attacking while the opponent is castled targets the Fortress")
	var g5 := _fresh_state()
	var cap: Champion = g5.players[1].champions[0]
	g5.players[0].champions[0].statuses.append({"kind": "duel", "duelist": cap.uid, "turns_left": 1})
	var tf5: Dictionary = await TargetFlows.new(g5, self).attack_target(0, g5.players[0].champions[0], 0)
	check(tf5.target.get("champion", -1) == cap.uid, "a dueled champion is sent at its duelist")
	var g6 := _fresh_state()
	var sac_card: Dictionary = cards["amustas"]
	g6.spawn_champion(0, cards["syranite"])  # enough Red champions to sacrifice
	g6.players[0].hand = [sac_card]
	var sc: Dictionary = await TargetFlows.new(g6, self).summon_choices(0, 0)
	check(sc.has("sacrifices") and sc.sacrifices.size() == 3, "a 3-sacrifice champion asks for 3 sacrifices")
	g6.players[0].summon_discount = 1
	var sc2: Dictionary = await TargetFlows.new(g6, self).summon_choices(0, 0)
	check(sc2.sacrifices.size() == 2, "Mumified lowers the number of sacrifices asked for")


func _test_hand_and_champion_clicks() -> void:
	# Drive the real click handlers on a prepared game, with the automatic player answering the popups.
	var g := _fresh_state()
	ui.game = g
	ui.flows = TargetFlows.new(g, ui)
	ui.viewer = 0
	ui._cover.visible = false
	g.players[0].hand = [cards["war_bear"], cards["heal"], cards["field_medics"]]
	g.players[0].enchantments.clear()
	var r: Dictionary = await ui.play_hand_card(1)
	check(r.ok, "clicking Heal plays it (%s)" % str(r.get("error", "")))
	var r2: Dictionary = await ui.play_hand_card(1)
	check(r2.ok and g.players[0].enchantments.size() == 1, "clicking an enchantment plays it")
	ui.refresh()
	var r3: Dictionary = await ui.play_hand_card(0)
	check(r3.ok, "clicking a champion summons it, sacrificing as asked (%s)" % str(r3.get("error", "")))
	var a: Champion = g.players[0].champions[0]
	var r4: Dictionary = await ui.attack_with(a.uid)
	check(r4.has("ok"), "clicking a champion starts an attack")
	ui._on_end_turn()
	check(g.active == 1 and ui._cover.visible, "End turn passes to the other player behind the cover")
	ui._on_reveal()
	check(ui.viewer == 1, "the next player reveals their turn")
	var heal_g := _fresh_state()
	ui.game = heal_g
	ui.flows = TargetFlows.new(heal_g, ui)
	ui.viewer = 0
	heal_g.next_step(0)
	ui.refresh()
	check(ui._btn_heal.visible, "the Fortress heal button shows in the Summon step")
	ui._on_fortress_heal()
	check(not heal_g.players[0].heal_pending, "using it heals a champion")


func _test_card_views() -> void:
	var made: int = 0
	for id in cards:
		var card: Dictionary = cards[id]
		for width in [210.0, 165.0, 340.0]:
			var v := CardView.create(card, width, null, width < 200.0)
			check(v.size.x == width and v.get_child_count() > 5, "%s draws at width %d" % [id, int(width)])
			v.free()
			made += 1
	check(made == cards.size() * 3, "every card draws in the three sizes")
	var g := _fresh_state()
	var c: Champion = g.players[0].champions[0]
	c.statuses.append({"kind": "poison", "amount": 10})
	var live := CardView.create(c.card, 165.0, c, true, true, true)
	check(live.get_child_count() > 5, "a live board card with statuses draws")
	live.free()
	check(CardView.image_path("gluto") != "", "art is found for Gluto")
	check(CardView.image_path("big_troll") == "", "Big Troll has no art yet and gets a placeholder")
	check(CardView.image_path("elite_o") != "" and CardView.image_path("lava_titan") != "", "Elite-O and Lava Titan art was renamed to match")
