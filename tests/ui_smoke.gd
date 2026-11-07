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
	await _test_first_turn_gnome_and_new_game()
	await _test_early_messages_and_previews()
	await _test_castle_reveal_scroll_and_tags()
	_test_optional_none_row()
	_test_art_fits_box()
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
	check(ui.viewer == ui.game.active and not ui._cover.visible, "the first turn starts straight away, with no hand-over screen")
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
	check(g.active == 1 and not ui._cover.visible and ui.viewer == 1, "End turn passes straight to the other player, no hand-over screen")
	var heal_g := _fresh_state()
	ui.game = heal_g
	ui.flows = TargetFlows.new(heal_g, ui)
	ui.viewer = 0
	heal_g.next_step(0)
	ui.refresh()
	check(ui._btn_heal.visible, "the Fortress heal button shows in the Summon step")
	ui._on_fortress_heal()
	check(not heal_g.players[0].heal_pending, "using it heals a champion")
	# Nothing damaged: no heal button and no prompt
	var full_g := _fresh_state()
	ui.game = full_g
	ui.flows = TargetFlows.new(full_g, ui)
	ui.viewer = 0
	full_g.next_step(0)
	for c in full_g.players[0].champions:
		c.damage = 0
	ui.refresh()
	check(not ui._btn_heal.visible, "no Fortress heal button when no champion is damaged")
	check(not ui._has_damaged_champion(full_g.players[0]), "undamaged champions are not heal targets")


func _run_choose(out: Array, title: String, opts: Array, mn: int, mx: int) -> void:
	out.append(await ui.choose(title, opts, mn, mx))


func _test_optional_none_row() -> void:
	var saved_chooser: Callable = ui.auto_chooser
	ui.auto_chooser = Callable()  # use the real popup
	var opts: Array = [{"label": "A", "value": 10}, {"label": "B", "value": 20}]
	var out: Array = []
	_run_choose(out, "optional", opts, 0, 1)
	check(ui._choice_list.item_count == 3 and ui._choice_list.get_item_text(0).begins_with("None"), "an optional choice has a None row")
	ui._on_choice_ok()
	check(out.size() == 1 and (out[0] as Array).is_empty(), "None is selected by default and chooses nothing")
	var out2: Array = []
	_run_choose(out2, "optional", opts, 0, 1)
	ui._choice_list.select(2)
	ui._on_choice_ok()
	check(out2.size() == 1 and out2[0] == [20], "picking a real row returns its value, not shifted")
	var out3: Array = []
	_run_choose(out3, "required", opts, 1, 1)
	check(ui._choice_list.item_count == 2, "a required choice has no None row")
	ui._choice_list.select(0)
	ui._on_choice_ok()
	check(out3[0] == [10], "required choice still maps correctly")
	ui.auto_chooser = saved_chooser


func _test_card_views() -> void:
	var made: int = 0
	for id in cards:
		var card: Dictionary = cards[id]
		for width in [210.0, 165.0, 340.0]:
			var v := CardView.create(card, width, null, width < 200.0)
			check(v.size.x == width and v.get_child_count() >= 4, "%s draws at width %d" % [id, int(width)])
			v.free()
			made += 1
	check(made == cards.size() * 3, "every card draws in the three sizes")
	var g := _fresh_state()
	var c: Champion = g.players[0].champions[0]
	c.statuses.append({"kind": "poison", "amount": 10})
	var live := CardView.create(c.card, 165.0, c, true, true, true)
	check(live.get_child_count() >= 4, "a live board card with statuses draws")
	live.free()
	check(CardView.image_path("gluto") != "", "art is found for Gluto")
	check(CardView.image_path("big_troll") == "", "Big Troll has no art yet and gets a placeholder")
	check(CardView.image_path("elite_o") != "" and CardView.image_path("lava_titan") != "", "Elite-O and Lava Titan art was renamed to match")


func _test_first_turn_gnome_and_new_game() -> void:
	var g := _fresh_state()
	g.players[0].turns_taken = 1  # this is player 0's first turn
	ui.game = g
	ui.flows = TargetFlows.new(g, ui)
	ui.viewer = 0
	ui._cover.visible = false
	g.next_step(0)
	ui.refresh()
	check(not ui._btn_next.visible, "no 'To Attack step' button on a first turn")
	ui._status.text = ""
	await ui._on_own_champion(g.players[0].champions[0].uid)
	check(ui._status.text.contains("first turn") and not g.players[0].colors_used.has("Red"), "clicking a champion on a first turn only explains why it cannot attack")
	g.players[0].turns_taken = 2
	ui.refresh()
	check(ui._btn_next.visible, "the Attack step button is there on later turns")
	check(not ui._btn_new.visible, "no New game button during a game")
	g.finished = true
	ui.refresh()
	check(ui._btn_new.visible, "a finished game shows a New game button")
	g.finished = false
	# Gnome is not offered to an attacker with too many HP.
	var g2 := _fresh_state()
	g2.players[1].champions.clear()
	var gnome: Champion = g2.spawn_champion(1, cards["gnome"])
	var other: Champion = g2.spawn_champion(1, cards["syranite"])
	var big: Champion = g2.players[0].champions[0]  # Amustas, 150 HP
	var tf: Dictionary = await TargetFlows.new(g2, self).attack_target(0, big, 0)
	check(tf.target.get("champion", -1) == other.uid, "Gnome is not in the list for a champion with over 60 HP")
	g2.players[1].champions.erase(other)
	var tf2: Dictionary = await TargetFlows.new(g2, self).attack_target(0, big, 0)
	check(tf2.has("error"), "if Gnome is the only champion, the message says this champion cannot attack it")


func _find_texture_rect(n: Node) -> TextureRect:
	if n is TextureRect:
		return n
	for c in n.get_children():
		var r: TextureRect = _find_texture_rect(c)
		if r != null:
			return r
	return null


func _test_art_fits_box() -> void:
	var v := CardView.create(cards["gluto"], 300.0)
	var tr: TextureRect = _find_texture_rect(v)
	check(tr != null, "Gluto's card has a picture")
	if tr != null:
		var holder: Control = tr.get_parent()
		check(absf(tr.size.x - holder.size.x) < 2.0 and absf(tr.size.y - holder.size.y) < 2.0, "the picture is sized to its box, not to its pixel size (%s vs %s)" % [str(tr.size), str(holder.size)])
		check(tr.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "the whole picture is shown")
	v.free()


func _test_early_messages_and_previews() -> void:
	# Ramaire: the spell is refused before any menu.
	var g := _fresh_state()
	g.spawn_champion(1, cards["ramaire"])
	g.players[0].hand = [cards["heal"]]
	check("Ramaire" in Preflight.spell_problem(g, 0, 0), "Ramaire's lock is explained before any menu")
	# Chained champion, HP threshold, colour already used, ability-only
	var g2 := _fresh_state()
	var mine: Champion = g2.players[0].champions[0]
	mine.statuses.append({"kind": "no_attack", "turns_left": 1})
	check("chained" in Preflight.attack_problem(g2, 0, mine, -1), "a chained champion cannot attack, said up front")
	var g3 := _fresh_state()
	var raider: Champion = g3.spawn_champion(0, cards["dark_raider"])
	raider.damage = 40  # 20 HP left, needs 40
	check("needs 40 HP" in Preflight.attack_problem(g3, 0, raider, -1), "an HP threshold the champion no longer meets is explained up front")
	var g4 := _fresh_state()
	var red1: Champion = g4.players[0].champions[0]
	var red2: Champion = g4.spawn_champion(0, cards["syranite"])
	g4.next_step(0)
	g4.next_step(0)
	check(g4.attack(0, red1.uid, 0, {"champion": g4.players[1].champions[0].uid}).ok, "first Red attack works")
	check("already attacked with Red" in Preflight.attack_problem(g4, 0, red2, -1), "a second Red champion is refused up front")
	var txt: String = Preflight.attackers_text(g4, 0)
	check(txt.contains("Already attacked with: Red"), "the hint lists the colours already used (%s)" % txt)
	var g5 := _fresh_state()
	var hb: Champion = g5.spawn_champion(0, cards["harmlobeast"])
	check("only an ability" in Preflight.attack_problem(g5, 0, hb, -1), "an ability-only champion is refused up front")
	# Grimn's saved bonus shows in the preview
	var g6 := _fresh_state()
	var grimn: Champion = g6.spawn_champion(0, cards["grimn"])
	check(DamageRules.preview(g6, grimn, grimn.card.attacks[0]) == 20, "Grimn's Gnaw previews 20 normally")
	grimn.statuses.append({"kind": "stored_bonus", "amount": 20})
	check(DamageRules.preview(g6, grimn, grimn.card.attacks[0]) == 40, "and 40 with the saved bonus")
	var v := CardView.create(grimn.card, 165.0, grimn, true, false, false, g6)
	check(v.get_child_count() >= 4, "Grimn's live card draws with the preview")
	v.free()
	# Infest and Ring of Greed are not attacks on a champion: no target menu
	var g7 := _fresh_state()
	var mar: Champion = g7.spawn_champion(0, cards["maragret"])
	var t7: Dictionary = await TargetFlows.new(g7, self).attack_target(0, mar, 1)
	check(t7.target.is_empty(), "Infest asks for no champion")
	var g8 := _fresh_state()
	var pg: Champion = g8.spawn_champion(0, cards["poglass"])
	var t8: Dictionary = await TargetFlows.new(g8, self).attack_target(0, pg, 1)
	check(t8.target.is_empty(), "Ring of Greed asks for no champion")
	# Summon problems up front
	var g9 := _fresh_state()
	g9.next_step(0)
	g9.players[0].summoned_this_turn = true
	g9.players[0].hand = [cards["gob"]]
	check("already summoned" in Preflight.summon_problem(g9, 0, 0), "a second summon is refused up front")


func _test_castle_reveal_scroll_and_tags() -> void:
	# Castle button: needs exactly one active champion
	var g := _fresh_state()  # three champions each
	ui.game = g
	ui.flows = TargetFlows.new(g, ui)
	ui.viewer = 0
	ui._cover.visible = false
	ui.refresh()
	check(ui._btn_castle.disabled and "exactly 1" in ui._btn_castle.tooltip_text, "the Castle button is off with 3 champions and says why")
	g.players[0].champions.resize(1)
	ui.refresh()
	check(not ui._btn_castle.disabled, "the Castle button is on with exactly one champion")
	# Revealing a turn with nothing to decide runs the start-of-turn triggers (poison!) straight away
	var g2 := _fresh_state()
	var t: Champion = g2.players[0].champions[0]
	g2.players[0].enchantments.clear()  # (the fresh state has Field Medics, which would heal the poison away)
	StatusRules.apply_poison(g2, t, 10, -1, 1)
	var dmg_before: int = t.damage
	ui.game = g2
	ui.flows = TargetFlows.new(g2, ui)
	ui._start_shown_turn = -1
	ui._cover_for_mulligan = false
	ui._cover.visible = true
	ui._on_reveal()
	check(g2.step == Game.Step.SUMMON and t.damage == dmg_before + 10, "revealing the turn ticks the poison at once")
	check(ui._status.text.begins_with("Start of turn:") and "10" in ui._status.text, "and the status line says what happened (%s)" % ui._status.text.left(80))
	# With a castle choice available the turn waits in the Castle step
	var g3 := _fresh_state()
	g3.players[0].champions.resize(1)
	ui.game = g3
	ui.flows = TargetFlows.new(g3, ui)
	ui._cover.visible = true
	ui._on_reveal()
	check(g3.step == Game.Step.CASTLE and "Castle step" in ui._status.text, "with a castle possible, the turn waits in the Castle step")
	# The hand's scroll bar is always shown and a smaller hand starts at the left edge
	check(ui._hand_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_ALWAYS, "the hand scroll bar is always shown")
	# Status tags are spelled out
	var g4 := _fresh_state()
	var grimn: Champion = g4.spawn_champion(0, cards["grimn"])
	StatusRules.apply_poison(g4, grimn, 10, -1, 1)
	grimn.statuses.append({"kind": "stored_bonus", "amount": 20})
	var v := CardView.create(grimn.card, 340.0, grimn, false, false, false, g4)
	var texts: Array = []
	for it in v._layer.items:
		texts.append(str(it.text))
	check(texts.any(func(x: String) -> bool: return "POISONED: 10 DMG PER TURN" in x and "GNAW +20 DMG" in x), "the card says 'Poisoned: 10 DMG per turn' and 'Gnaw +20 DMG' (%s)" % str(texts.filter(func(x): return "POISONED" in x)))
	check(not texts.any(func(x: String) -> bool: return x.begins_with("DMG ")), "the confusing 'DMG 10' tag is gone")
	v.free()
