extends SceneTree
## Takes screenshots of the hotseat screen and a card gallery (needs a display; on a server use xvfb-run):
##   godot --rendering-driver vulkan -s tests/screenshot.gd
## Saves user://shot_board.png, user://shot_gallery.png (see the printed paths).

func auto(_t: String, options: Array, min_n: int, _m: int) -> Variant:
	var out: Array = []
	for i in mini(min_n, options.size()):
		out.append(options[i].value)
	return out


func _initialize() -> void:
	_run()


func _run() -> void:
	var cards: Dictionary = CardDB.load_cards()
	# 1. gallery of different card kinds
	var gal := Control.new()
	gal.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	gal.add_child(bg)
	var flow := HFlowContainer.new()
	flow.set_anchors_preset(Control.PRESET_FULL_RECT)
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	gal.add_child(flow)
	for id in ["warlord", "gluto", "war_bear", "harmlobeast", "stanter", "syranite", "psytwist", "amustas", "big_troll", "battle_axe", "field_medics", "mist_of_despair"]:
		flow.add_child(CardView.create(cards[id], 300.0))
	root.add_child(gal)
	root.size = Vector2i(1600, 980)
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("user://shot_gallery.png")
	gal.queue_free()
	await process_frame
	# 2. the real screen mid-game
	var ui = load("res://scenes/main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.auto_chooser = Callable(self, "auto")
	var names: Array = ui.decks.keys()
	ui.start_new_game(names[0], names[1], 4)
	ui._on_reveal()
	ui._on_keep()
	ui._on_reveal()
	ui._on_keep()
	var g: Game = ui.game
	for i in 9:
		SimpleBot.take_turn(g, g.active)
	ui.viewer = g.active
	ui._cover.visible = false
	ui.refresh()
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("user://shot_board.png")
	print("saved to ", OS.get_user_data_dir())
	quit()
