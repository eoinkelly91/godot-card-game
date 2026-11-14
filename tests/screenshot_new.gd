extends SceneTree
## Screenshots of the drag-and-drop board and the new hover panel:  xvfb-run -a godot --rendering-driver vulkan -s tests/screenshot_new.gd

func auto(_t: String, options: Array, min_n: int, _m: int) -> Variant:
	var out: Array = []
	for i in mini(min_n, options.size()):
		out.append(options[i].value)
	return out


func _initialize() -> void:
	_run()


func _run() -> void:
	var cards: Dictionary = CardDB.load_cards()
	var ui = load("res://scenes/main.tscn").instantiate()
	root.add_child(ui)
	root.size = Vector2i(1740, 980)
	await process_frame
	ui.auto_chooser = Callable(self, "auto")
	ui.start_new_game("red_blue", "white_purple", 4)
	ui._on_reveal()
	ui._on_keep()
	ui._on_reveal()
	ui._on_keep()
	var g: Game = ui.game
	for i in 12:
		SimpleBot.take_turn(g, g.active)
	var p: int = g.active
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	foe.enchantments.append(SummonRules._running(cards["super_shrink"]))
	me.enchantments.append(SummonRules._running(cards["field_medics"]))
	StatusRules.add_attack_buff(g, 1 - p, 0, 1)
	g.players[1 - p].buffs.append({"kind": "outgoing_reduction", "amount": 20, "turns_left": 2})
	if me.champions.size() >= 2:
		me.champions[0].attached = [cards["fusion"], cards["power_source"]]
		me.champions[1].attached = [cards["warrior_idol"]] if cards.has("warrior_idol") else [cards["fusion"]]
	ui.viewer = p
	ui._cover.visible = false
	ui.refresh()
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("/tmp/shot_board2.png")
	# the hover card of one of my champions (with a Formation status for the tag)
	if not me.champions.is_empty():
		var c: Champion = me.champions[0]
		c.statuses.append({"kind": "reduce_incoming", "amount": 10, "turns_left": 2, "label": "Formation"})
		HpRules.recalc(g)
		var v: CardView = CardView.create(c.card, 200.0, c, true, false, false, g)
		var tip: Control = v._make_custom_tooltip("x")
		var holder := Control.new()
		var bgc := ColorRect.new()
		bgc.color = Color(0.2, 0.2, 0.25)
		bgc.size = Vector2(1740, 700)
		holder.add_child(bgc)
		holder.add_child(tip)
		ui.add_child(holder)
		holder.z_index = 100
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png("/tmp/shot_tip.png")
	print("done")
	quit()
