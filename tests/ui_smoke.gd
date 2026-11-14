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
	await _test_fortress_card_and_board()
	await _test_drag_and_drop_and_new_display()
	await _test_second_batch()
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
	g.rules.castle_locked_turns = 0  # these tests are about the screen, not the 5-turn castling lock
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
			g.players[0].discard = [cards["battlements"], cards["heal"], cards["syranite"]]  # for Galachs Will and Archaeology
			if not g.players[1].champions.is_empty():  # for Mystery: a card attached to an enemy champion
				g.players[1].champions[0].attached = [cards["fusion"].duplicate()]
			var flows := TargetFlows.new(g, self)
			var tf: Dictionary = await flows.spell_target(0, 0, ei)
			check(tf.has("target"), "%s effect %d: the flow builds a target (%s)" % [id, ei, str(tf)])
			if tf.has("target"):
				var res: Dictionary = g.play_spell(0, 0, ei, tf.target)
				check(res.ok, "%s effect %d: the engine accepts it (%s)" % [id, ei, str(res.get("error", ""))])
				count += 1
	check(count == 33, "all 33 spell effects went through (%d)" % count)
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
	# There is no Fortress heal any more: in the Summon step the Fortress offers nothing
	var heal_g := _fresh_state()
	ui.game = heal_g
	ui.flows = TargetFlows.new(heal_g, ui)
	ui.viewer = 0
	heal_g.next_step(0)
	ui.refresh()
	check(ui._fortress_options().is_empty(), "the Fortress offers nothing in the Summon step (no Fortress heal)")
	var full_g := _fresh_state()
	ui.game = full_g
	ui.flows = TargetFlows.new(full_g, ui)
	ui.viewer = 0
	full_g.next_step(0)
	for c in full_g.players[0].champions:
		c.damage = 0
	ui.refresh()
	check(ui._fortress_options().is_empty(), "still nothing to click")


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
	check(ui._me_info.text.contains("SUMMONING AVAILABLE"), "the info line says summoning is available in the Summon step")
	ui._status.text = ""
	await ui._on_own_champion(g.players[0].champions[0].uid)
	check(ui._status.text.contains("first turn") and not g.players[0].colors_used.has("Red"), "clicking a champion on a first turn only explains why it cannot attack")
	g.players[0].turns_taken = 2
	ui.refresh()
	check(not ui._me_info.text.contains("CASTLED"), "no castled text when not castled")
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
	# Warlord: the spell is refused before any menu; Ramaire does the same for enchantments.
	var g := _fresh_state()
	g.spawn_champion(1, cards["warlord"])
	g.players[0].hand = [cards["heal"]]
	check("Warlord" in Preflight.spell_problem(g, 0, 0), "Warlord's lock is explained before any menu")
	g.spawn_champion(1, cards["ramaire"])
	g.players[0].hand = [cards["field_medics"]]
	g.players[0].mana = 10
	g.players[0].turns_taken = 2
	check("Ramaire" in Preflight.enchantment_problem(g, 0, 0), "Ramaire's lock on enchantments is explained")
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
	g9.players[0].summons_this_turn = 1
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
	check(ui._fortress_options().is_empty() and "exactly 1" in Preflight.castle_problem(g, 0), "the Fortress offers no castling with 3 champions, and says why")
	g.players[0].champions.resize(1)
	ui.refresh()
	var copts: Array = ui._fortress_options()
	check(copts.size() == 1 and copts[0].value == "castle", "the Fortress offers just Castle with exactly one champion (Cancel closes the menu)")
	# Revealing a turn with nothing to decide runs the start-of-turn triggers (poison!) straight away
	var g2 := _fresh_state()
	var t: Champion = g2.players[0].champions[0]
	g2.players[0].enchantments.clear()  # (the fresh state has Field Medics, which would heal the poison away)
	StatusRules.apply_poison(g2, t, 10, -1, 1)
	var dmg_before: int = t.damage
	TurnRules._run_start_triggers(g2, 0)  # the poison ticks as the turn begins
	ui.game = g2
	ui.flows = TargetFlows.new(g2, ui)
	ui._start_shown_turn = -1
	ui._cover_for_mulligan = false
	ui._cover.visible = true
	ui._on_reveal()
	check(g2.step == Game.Step.OPEN and t.damage == dmg_before + 10, "the poison ticked at the very start of the turn")
	check(ui._status.text.begins_with("Start of turn:") and "10" in ui._status.text, "and the status line says what happened (%s)" % ui._status.text.left(80))
	# With a castle choice available the turn waits in the Castle step
	var g3 := _fresh_state()
	g3.players[0].champions.resize(1)
	ui.game = g3
	ui.flows = TargetFlows.new(g3, ui)
	ui._cover.visible = true
	ui._on_reveal()
	check(g3.step == Game.Step.OPEN and "Click your Fortress" in ui._status.text, "with a castle possible, the turn waits in the Castle step and says to click the Fortress")
	# The hand's scroll bar is always shown and a smaller hand starts at the left edge
	check(ui._hand_row is HandFan, "the hand is a fan of cards (no scrolling)")
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


func _test_fortress_card_and_board() -> void:
	var g := _fresh_state()
	g.players[0].champions.resize(1)
	ui.game = g
	ui.flows = TargetFlows.new(g, ui)
	ui.viewer = 0
	ui._cover.visible = false
	ui.refresh()
	check(ui._btn_log != null and not ui._log_panel.visible, "the events log starts hidden behind the LOG button")
	ui._toggle_log()
	check(ui._log_panel.visible, "LOG opens the events log")
	ui._toggle_log()
	var fc: Dictionary = ui.fortress_card(g.players[0])
	check(str(fc.kind) == "fortress" and int(fc.hp) == 500 and int(fc.hp_now) == 500, "the Fortress card knows its name and HP")
	var view := CardView.create(fc, 340.0, null, false)
	check(view != null and CardView.SPELL_COLOR == view._base_color(), "a Fortress card has the same background colour as a spell")
	# Clicking the Fortress and choosing Castle castles, then carries on to the Summon step
	ui.auto_chooser = func(_t: String, o: Array, _mn: int, _mx: int) -> Variant: return [o[0].value]
	await ui._on_fortress_clicked()
	check(g.players[0].castled and g.step == Game.Step.OPEN, "choosing Castle from the Fortress menu castles and starts the turn")
	# Castled: one row per player; the champion is asleep (faded) and the Fortress has an orange border
	var rows: Array = ui._me_box.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	check(rows.size() == 1, "each player has a single row (champions, Fortress, enchantments)")
	ui.refresh()
	check(ui._me_info.text.contains("CASTLED: Fortress vulnerable to attack, champions encamped, turns remaining:2"), "a castled player's info line explains the castle and the turns remaining")
	# Hand limit: ending the turn with 12 cards asks for 2 discards first
	var hl := _fresh_state()
	ui.game = hl
	ui.flows = TargetFlows.new(hl, ui)
	ui.viewer = 0
	hl.next_step(0)
	for i in 12:
		hl.players[0].hand.append(cards["syranite"])
	var asked: Array = [0]
	ui.auto_chooser = func(t: String, o: Array, _mn: int, _mx: int) -> Variant:
		asked[0] += 1
		return [0]
	await ui._on_end_turn()
	check(asked[0] == 2 and hl.active == 1 and hl.players[0].hand.size() == 10, "ending the turn with 12 cards asks for 2 discards, then ends")
	ui.auto_chooser = Callable(self, "auto")
	# END TURN is highlighted when nothing is left to do
	var nl := _fresh_state()
	ui.game = nl
	ui.flows = TargetFlows.new(nl, ui)
	ui.viewer = 0
	nl.next_step(0)
	nl.players[0].hand.clear()
	ui.refresh()
	check(not ui._nothing_left_to_do() and not ui._btn_end.has_theme_stylebox_override("normal"), "END TURN is not highlighted while summoning is available")
	check(ui._me_info.text.contains("[color=#ffd940]SUMMONING AVAILABLE"), "SUMMONING AVAILABLE is yellow")
	nl.players[0].summons_this_turn = 1
	for c in nl.players[0].champions:
		c.attacked_this_turn = true
	nl.players[0].colors_used = ["Red", "Blue", "White", "Purple"]
	ui.refresh()
	check(ui._nothing_left_to_do() and ui._btn_end.has_theme_stylebox_override("normal"), "END TURN gets a yellow border when there is nothing left to do")
	nl.players[0].colors_used = []
	ui.refresh()
	check(not ui._nothing_left_to_do() and not ui._btn_end.has_theme_stylebox_override("normal"), "and loses it when a champion can attack again")
	# Castle lock message from the Fortress click
	var lk := _fresh_state()
	lk.rules.castle_locked_turns = 5
	lk.players[0].champions.resize(1)
	lk.players[0].turns_taken = 3
	ui.game = lk
	ui.flows = TargetFlows.new(lk, ui)
	ui.viewer = 0
	ui.auto_chooser = func(_t: String, _o: Array, _mn: int, _mx: int) -> Variant: return []
	await ui._on_fortress_clicked()
	check("3 turns from now" in ui._status.text, "clicking the Fortress says how many turns until you can castle")
	ui.auto_chooser = Callable(self, "auto")
	# A champion summoned this turn sleeps (Zzz); the info row says class and type
	var newbie: Champion = lk.players[0].champions[0]
	newbie.summoned_turn = lk.turn
	var nv := CardView.create(newbie.card, 150.0, newbie, true, false, false, lk)
	check(nv.modulate.a < 0.8, "a champion summoned this turn is faded and asleep")
	# No steps: the title is just the turn and player, and summoning stays available until you summon
	check(not ui._turn_label.text.contains("step"), "the turn title no longer names a step")
	var ns := _fresh_state()
	ui.game = ns
	ui.flows = TargetFlows.new(ns, ui)
	ui.viewer = 0
	ns.players[0].champions.resize(1)
	ns.attack(0, ns.players[0].champions[0].uid, 0, {"champion": ns.players[1].champions[0].uid} if not ns.players[1].champions.is_empty() else {})
	ui.refresh()
	check(ui._me_info.text.contains("SUMMONING AVAILABLE"), "summoning is still available after attacking")
	check(ui._fortress_options().is_empty(), "the Fortress offers nothing to click once you have attacked")
	# Two champions with the same name get (1) and (2)
	var dup := _fresh_state()
	var d1 := dup.spawn_champion(0, cards["pog"])
	var d2 := dup.spawn_champion(0, cards["pog"])
	check(dup.champion_tag(d1) == " (1)" and dup.champion_tag(d2) == " (2)" and dup.champion_tag(dup.players[0].champions[0]) == "", "same-named champions are numbered, others are not")
	check("(2)" in dup.describe_champion(d2), "menus show the same (2)")
	var fcv := CardView.create(ui.fortress_card(dup.players[0]), 150.0, null, true)
	check(fcv != null, "the Fortress card builds with HP text")
	# Attached cards: the champion is stacked on top of them, and the hover shows everything
	var st := _fresh_state()
	var holder_champ: Champion = st.players[0].champions[0]
	holder_champ.attached = [cards["warrior_idol"].duplicate(), cards["fusion"].duplicate()]
	ui.game = st
	ui.flows = TargetFlows.new(st, ui)
	var stack: Control = ui._stack_with_attachments(holder_champ, CardView.create(holder_champ.card, 150.0, holder_champ, true, false, false, st))
	check(stack.get_child_count() == 3, "a champion with 2 attached cards is stacked on 2 cards")
	var tip: Object = CardView.create(holder_champ.card, 150.0, holder_champ, true, false, false, st)._make_custom_tooltip("")
	check(tip is HBoxContainer and (tip as HBoxContainer).get_child_count() >= 3, "hovering shows the champion, its attached cards and the attack explanation")
	var gaia_view := CardView.create(cards["gaia"], 300.0, null, false)
	check(gaia_view._mana_summon() and not CardView.create(cards["syranite"], 300.0, null, false)._mana_summon(), "a mana summon cost gets the blue number, others do not")
	var sleeper := CardView.create(g.players[0].champions[0].card, 128.0, g.players[0].champions[0], true, false, true, g)
	check(sleeper.modulate.a < 0.8, "an encamped champion is faded")
	ui.auto_chooser = Callable(self, "auto")
	# The enemy Fortress does nothing when clicked: no handler is connected for the inactive player
	var fv := CardView.create(ui.fortress_card(g.players[1]), 108.0, null, true)
	check(fv.pressed.get_connections().is_empty(), "an enemy Fortress card has no click action")


func _test_drag_and_drop_and_new_display() -> void:
	var g := _fresh_state()
	ui.game = g
	ui.flows = TargetFlows.new(g, ui)
	ui.viewer = 0
	ui._cover.visible = false
	var p0: PlayerState = g.players[0]
	p0.enchantments.clear()
	p0.hand = [cards["gob"], cards["molten_harry"], cards["field_medics"], cards["heal"], cards["fusion"], cards["syranite"]]
	ui.refresh()
	# the attack hint sits directly under the "Player N (YOUR TURN)" bar
	var left: Node = ui._me_info.get_parent()
	check(ui._attack_hint.get_parent() == left and ui._attack_hint.get_index() == ui._me_info.get_index() + 1 and ui._me_box.get_index() < ui._me_info.get_index(), "the info bar and the attackers line sit below the play area, above the hand")
	# a hand card is draggable
	var first: CardView = ui._hand_row.get_views()[0]
	check(first.drag_data is Dictionary and int(first.drag_data.hand_index) == 0, "hand cards carry drag data")
	var d_champ: Dictionary = {"hand_index": 0, "kind": "champion", "player": 0}
	var d_sac: Dictionary = {"hand_index": 1, "kind": "champion", "player": 0}
	var d_ench: Dictionary = {"hand_index": 2, "kind": "enchantment", "player": 0}
	var d_spell: Dictionary = {"hand_index": 3, "kind": "spell", "player": 0}
	check(ui._can_drop(d_champ, {"kind": "play", "owner": 0}), "a champion can be dropped into my play area")
	check(not ui._can_drop(d_champ, {"kind": "play", "owner": 1}), "but not into the opponent's")
	check(not ui._can_drop(d_champ, {"kind": "ench", "owner": 0}), "and not into the enchantment area")
	check(ui._can_drop(d_spell, {"kind": "board", "owner": 1}) and ui._can_drop(d_spell, {"kind": "play", "owner": 0}), "a spell can be dropped anywhere on the board")
	check(ui._can_drop(d_ench, {"kind": "ench", "owner": 0}) and not ui._can_drop(d_ench, {"kind": "play", "owner": 0}), "an enchantment goes only into the enchantment area")
	# a basic champion dropped into the play area is summoned
	var before_n: int = p0.champions.size()
	var r2: Dictionary = await ui.play_hand_card(0, {"owner": 0})
	check(r2.ok and p0.champions.size() == before_n + 1 and p0.champions.back().card_name() == "Gob", "dropped into the play area it is summoned")
	# a full board warns
	g.spawn_champion(0, cards["syranite"])
	g.spawn_champion(0, cards["syranite"])
	check(p0.champions.size() == 6, "board is full")
	p0.summons_this_turn = 0
	var r3: Dictionary = await ui.play_hand_card(4 if p0.hand.size() > 4 else 0, {"owner": 0})
	check(not r3.ok and ui._status.text == "Your play area is full.", "a basic champion on a full board says the play area is full")
	# enchantments: slots full -> replace with a confirmation
	g.rules.enchantment_limit = 1
	p0.enchantments = [SummonRules._running(cards["battlements"])]
	var hi: int = p0.hand.find(cards["field_medics"])
	var r5: Dictionary = await ui.play_hand_card(hi, {"owner": 0})  # the menu asks which to replace (the test chooser takes the first)
	check(r5.ok and p0.enchantments.size() == 1 and str(p0.enchantments[0].id) == "field_medics", "with all enchantment places full, a menu asks which one to replace")
	check(int(p0.enchantments[0].turns_left) == int(cards["field_medics"].turns), "the new enchantment starts with its full turns")
	# castled: summoning available (2)
	p0.castled = true
	p0.summons_this_turn = 0
	ui.refresh()
	check(ui._me_info.text.contains("SUMMONING AVAILABLE (2)"), "castled: SUMMONING AVAILABLE (2)")
	p0.summons_this_turn = 1
	ui.refresh()
	check(ui._me_info.text.contains("SUMMONING AVAILABLE (1)"), "castled with one summon used: (1)")
	p0.summons_this_turn = 2
	ui.refresh()
	check(not ui._me_info.text.contains("SUMMONING AVAILABLE"), "both summons used: no message")
	p0.castled = false
	ui.refresh()
	# the Fortress has no yellow outline while castled
	p0.castled = true
	check(not ui._fortress_options().is_empty(), "a castled player still has the uncastle option")
	ui.refresh()
	var fortress_view: CardView = null
	for n in ui._me_box.find_children("*", "CardView", true, false):
		if str((n as CardView).card.get("kind", "")) == "fortress":
			fortress_view = n
	check(fortress_view != null and fortress_view.encamped and not fortress_view.selected, "castled Fortress: orange border only, no yellow outline")
	p0.castled = false
	# card display: true damage after a reduction, in red, and the turns circle
	var foe_attacker: Champion = g.players[1].champions[1]
	g.players[1].buffs.append({"kind": "outgoing_reduction", "amount": 20, "turns_left": 2})
	var v: CardView = CardView.create(foe_attacker.card, 200.0, foe_attacker, true, false, false, g)
	var texts: Array = []
	for it in v._layer.items:
		texts.append(str(it.text))
	check(texts.has("0"), "an attack reduced to 0 shows 0 on the card")
	var ev: CardView = CardView.create(p0.enchantments[0], 200.0, null, true)
	var circle_found: bool = false
	for it in ev._layer.items:
		if str(it.text) == str(int(p0.enchantments[0].turns_left)):
			circle_found = true
	check(circle_found, "an enchantment card shows its turns in a circle")
	# hover panel: HP breakdown above the attacks, status and reasons below
	g.players[1].enchantments.clear()
	p0.enchantments = [SummonRules._running(cards["super_shrink"])]
	HpRules.recalc(g)
	var tgt: Champion = g.players[1].champions[1]
	var tv: CardView = CardView.create(tgt.card, 200.0, tgt, true, false, false, g)
	var tip: Control = tv._make_custom_tooltip("")
	check(tip is HBoxContainer and tip.get_child(0) is CardView and not (tip.get_child(1) is CardView), "the info panel sits right beside the champion")
	var labels: Array = []
	for l in tip.get_child(1).find_children("*", "Label", true, false):
		labels.append((l as Label).text)
	var hp_at: int = labels.find("-20 from Super Shrink")
	var atk_at: int = -1
	for i in labels.size():
		if "damage" in str(labels[i]) and atk_at < 0 and i > 0:
			atk_at = i
	check(hp_at >= 0 and (atk_at < 0 or hp_at < atk_at), "Super Shrink is listed above the attack information")
	# status: a champion summoned this turn says why it cannot attack, under the attack information
	var fresh: Champion = g.spawn_champion(1, cards["gob"])
	g.active = 1
	fresh.summoned_turn = g.turn
	var fv: CardView = CardView.create(fresh.card, 200.0, fresh, true, false, false, g)
	var tip2: Control = fv._make_custom_tooltip("")
	var l2: Array = []
	for l in tip2.get_child(1).find_children("*", "Label", true, false):
		l2.append((l as Label).text)
	var has_reason: bool = false
	for t in l2:
		if str(t).begins_with("Cannot attack:"):
			has_reason = true
	check(has_reason, "the hover panel says why a champion cannot attack")
	g.active = 0


func _texts_of(v: CardView) -> Array:
	var out: Array = []
	for it in v._layer.items:
		out.append(str(it.text))
	return out


func _hp_color_of(v: CardView) -> Color:
	for it in v._layer.items:
		if str(it.text).ends_with("HP") and "/" in str(it.text):
			return it.color
	return Color(-1, -1, -1)


func _test_second_batch() -> void:
	var g := _fresh_state()
	ui.game = g
	ui.flows = TargetFlows.new(g, ui)
	ui.viewer = 0
	ui._cover.visible = false
	var p0: PlayerState = g.players[0]
	# HP colours: red (net negative), green (net positive), yellow (effects cancel out), plain otherwise
	var tgt: Champion = g.players[1].champions[1]
	var plain: Color = _hp_color_of(CardView.create(tgt.card, 200.0, tgt, true, false, false, g))
	p0.enchantments = [SummonRules._running(cards["super_shrink"])]
	HpRules.recalc(g)
	var red: Color = _hp_color_of(CardView.create(tgt.card, 200.0, tgt, true, false, false, g))
	check(red.r > 0.7 and red.g < 0.3, "HP lowered by Super Shrink is red")
	tgt.hp_effects = [{"text": "from Super Shrink", "delta": -20}, {"text": "from Water Hound", "delta": 30}]
	var green: Color = _hp_color_of(CardView.create(tgt.card, 200.0, tgt, true, false, false, g))
	check(green.g > 0.45 and green.r < 0.2, "-20 and +30 together: the net +10 makes the HP green")
	tgt.hp_effects = [{"text": "from Super Shrink", "delta": -20}, {"text": "from Fusion", "delta": 20}]
	var yellow: Color = _hp_color_of(CardView.create(tgt.card, 200.0, tgt, true, false, false, g))
	check(yellow.r > 0.7 and yellow.g > 0.5 and yellow.b < 0.2, "effects that cancel out: yellow")
	tgt.hp_effects = []
	check(_hp_color_of(CardView.create(tgt.card, 200.0, tgt, true, false, false, g)) == plain, "no effects: normal colour")
	# labels
	var ench_view: CardView = CardView.create(cards["field_medics"], 200.0, null, true)
	check(_texts_of(ench_view).has("(hover for info)"), "enchantments in play say (hover for info)")
	var fv: CardView = CardView.create(ui.fortress_card(p0), 200.0, null, true, false, false, g)
	check(_texts_of(fv).has("EFFECT") and not _texts_of(fv).has("ABILITY"), "the Fortress says EFFECT, not ABILITY")
	# attached cards are behind the champion at the same height, so a slot never changes size
	var c0: Champion = p0.champions[0]
	c0.attached.clear()
	ui.refresh()
	var w0: float = _first_champion_holder().custom_minimum_size.x
	c0.attached = [cards["fusion"], cards["power_source"]]
	ui.refresh()
	var holder: Control = _first_champion_holder()
	check(absf(holder.custom_minimum_size.x - w0 - 2.0 * ui.ATTACH_STEP) < 0.01, "attached cards widen only that champion's space, by a little")
	var backs: Array = holder.get_children().filter(func(n: Node) -> bool: return n is CardView and (n as CardView).live == null)
	check(backs.size() == 2 and (backs[0] as CardView).position.y == 0.0 and (backs[1] as CardView).position.y == 0.0, "attached cards sit at the same height as the champion")
	check(absf(holder.custom_minimum_size.y - ui.BOARD_CARD_H) < 0.01, "stacking adds no height")
	c0.attached.clear()
	# Wizardry asks which drawn card to discard
	p0.hand = [cards["wizardry"]]
	p0.deck = [cards["gob"], cards["syranite"], cards["capeasant"], cards["gorth"]]
	p0.mana = 10
	var drawn_expected: Array = [p0.deck[3], p0.deck[2], p0.deck[1]]
	var r: Dictionary = await ui.play_hand_card(0)
	check(r.ok and p0.pending_wizardry.is_empty() and p0.hand.size() == 2, "Wizardry through the screen: three drawn, one discarded")
	# right-click removal
	p0.enchantments = [SummonRules._running(cards["field_medics"])]
	ui.refresh()
	await ui._on_enchantment_right_click(0)  # the test chooser takes the first option: remove
	check(p0.enchantments.is_empty() and str(p0.discard.back().id) == "field_medics", "right-clicking an enchantment can remove it")
	# Dynamo's text and start-of-turn trigger
	check(str(cards["dynamo"].ability.trigger) == "start_of_turn", "Dynamo's ability triggers at the start of the turn")


func _first_champion_holder() -> Control:
	var play: Node = null
	for z in ui._me_box.find_children("*", "DropZone", true, false):
		if (z as DropZone).get_child_count() > 0 and (z as DropZone).get_child(0) is HBoxContainer and (z as DropZone).size_flags_horizontal == Control.SIZE_EXPAND_FILL:
			play = z
			break
	var row: Node = play.get_child(0)
	var first: Control = row.get_child(0)
	if first is CardView:  # no attached cards: wrap-less view; give it a holder-like size
		return first
	return first
