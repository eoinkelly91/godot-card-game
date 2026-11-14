## hotseat.gd - A two-player hotseat screen for playing the card game by hand on one computer.
## It builds its whole interface in code. All rules come from the engine (Game); this file only shows the
## state and turns clicks into engine calls. The player whose turn it is sees their hand; a "pass the device"
## cover hides it between turns. Choices (targets, sacrifices, discards) are asked through choose(), which
## TargetFlows uses; tests replace it with auto_chooser.
extends Control

const COLORS := {
	"Red": Color(0.62, 0.17, 0.17), "Blue": Color(0.17, 0.32, 0.66),
	"White": Color(0.78, 0.78, 0.74), "Purple": Color(0.42, 0.2, 0.58),
}
const NEUTRAL := Color(0.25, 0.3, 0.28)
const HAND_CARD_W := 245.0  # hand cards are the same size as on the mulligan screen
const BOARD_CARD_W := 140.0
const BOARD_CARD_H := BOARD_CARD_W * 650.0 / 490.0
const ATTACH_STEP := 14.0  # how far each attached card peeks out sideways behind its champion

var game: Game
var cards: Dictionary = {}
var decks: Dictionary = {}
var flows: TargetFlows
var viewer: int = -1            # whose hand is on screen; -1 = nobody (cover screen)
var mulligan_player: int = -1   # during the mulligan stage
var auto_chooser: Callable = Callable()  # tests: (title, options, min_n, max_n) -> Array or null
var busy: bool = false

signal _choice_done(result)

var _opp_box: VBoxContainer
var _me_box: VBoxContainer
var _hand_row: HandFan
var _my_deck_box: VBoxContainer
var _opp_deck_label: Label
var _hand_label: Label
var _status: Label
var _attack_hint: Label
var _start_shown_turn: int = -1
var _turn_label: Label
var _log: RichTextLabel
var _hand_w: float = HAND_CARD_W
var _attachment_room: float = 0.0  # extra row height while any champion on the board has attached cards
var _left_box: VBoxContainer
var _opp_info: RichTextLabel
var _btn_log: Button
var _log_panel: PanelContainer
var _opp_discard_btn: Button
var _my_discard_box: VBoxContainer
var _me_info: RichTextLabel
var _btn_end: Button
var _btn_new: Button
var _setup: Control
var _cover: Control
var _cover_label: Label
var _mull: Control
var _mull_label: Label
var _mull_hand: HBoxContainer
var _mull_btn: Button
var _choice: Control
var _choice_title: Label
var _choice_hint: Label
var _choice_list: CardItemList
var _choice_ok: Button
var _choice_min: int = 1
var _choice_max: int = 1
var _choice_none_row: bool = false
var _end: Control
var _end_label: Label
var _deck0: OptionButton
var _deck1: OptionButton
var _seed: LineEdit


func _ready() -> void:
	cards = CardDB.load_cards()
	decks = CardDB.load_decks()
	_build_ui()
	_show_setup()
	_fit_window()
	_set_cursor(false)


## The mouse pointer is a pointing gauntlet; while a card is being dragged it is a fist.
func _set_cursor(dragging: bool) -> void:
	var pointer: Texture2D = load("res://art/ui/mouse_point.png")
	var fist: Texture2D = load("res://art/ui/mouse_fist.png")
	if pointer == null or fist == null:
		return
	var point_spot := Vector2(pointer.get_width() * 0.33, 2.0)  # the tip of the finger
	var fist_spot := Vector2(fist.get_width() * 0.5, fist.get_height() * 0.4)
	Input.set_custom_mouse_cursor(fist if dragging else pointer, Input.CURSOR_ARROW, fist_spot if dragging else point_spot)
	Input.set_custom_mouse_cursor(pointer, Input.CURSOR_POINTING_HAND, point_spot)  # over buttons
	for shape in [Input.CURSOR_DRAG, Input.CURSOR_CAN_DROP, Input.CURSOR_FORBIDDEN]:
		Input.set_custom_mouse_cursor(fist, shape, fist_spot)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_set_cursor(true)
	elif what == NOTIFICATION_DRAG_END:
		_set_cursor(false)


## Opens the window as big as the screen allows (the layout is designed at 1740 x 980 and scaled up; a 4K screen gets ~2x).
## F11 switches full screen on and off.
func _fit_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var base := Vector2(1740, 980)
	var screen: int = DisplayServer.window_get_current_screen()
	var area: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	var factor: float = minf(3.0, minf(float(area.size.x) / base.x, float(area.size.y) / base.y) * 0.95)  # as big as the screen allows
	var win: Window = get_window()
	win.size = Vector2i(base * factor)
	win.position = area.position + (area.size - win.size) / 2


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		var win: Window = get_window()
		win.mode = Window.MODE_WINDOWED if win.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


# ================================================================ building the interface

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var outer := VBoxContainer.new()  # the board and the events column, with the messages bar along the bottom
	outer.add_theme_constant_override("separation", 3)
	margin.add_child(outer)
	var left := VBoxContainer.new()
	_left_box = left
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	outer.add_child(left)

	var top := HBoxContainer.new()  # the turn line, and the LOG button in the top right corner
	left.add_child(top)
	_turn_label = Label.new()
	_turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_label.add_theme_font_size_override("font_size", 18)
	top.add_child(_turn_label)
	_btn_log = _button("LOG", _toggle_log)
	top.add_child(_btn_log)
	# Board, like the mock-up: each player has ONE row (champions, Fortress, enchantments). The opponent is on top,
	# you are below, and your discard pile sits beside your hand. The opponent's discard pile has a button
	# next to their info.
	var opp_head := HBoxContainer.new()
	left.add_child(opp_head)
	_opp_info = _info_label()
	_opp_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	opp_head.add_child(_opp_info)
	_opp_discard_btn = _button("Opponents Discard Pile", _on_view_opp_discard)
	opp_head.add_child(_opp_discard_btn)
	_opp_deck_label = Label.new()
	_opp_deck_label.add_theme_font_size_override("font_size", 13)
	opp_head.add_child(_opp_deck_label)
	_opp_box = VBoxContainer.new()
	left.add_child(_opp_box)
	_me_box = VBoxContainer.new()
	left.add_child(_me_box)
	_me_info = _info_label()  # below the play area, above the hand
	left.add_child(_me_info)
	_attack_hint = Label.new()  # directly under the "Player N (YOUR TURN)" bar
	_attack_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attack_hint.add_theme_font_size_override("font_size", 13)
	_attack_hint.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	left.add_child(_attack_hint)
	_hand_label = Label.new()  # no longer shown (the board info line has the mana)
	_hand_label.visible = false
	left.add_child(_hand_label)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	left.add_child(bottom)
	_my_deck_box = VBoxContainer.new()  # the deck, beside the hand
	bottom.add_child(_my_deck_box)
	_hand_row = HandFan.new()
	_hand_row.card_w = _hand_w
	_hand_row.card_h = _hand_w * 650.0 / 490.0
	_hand_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand_row.custom_minimum_size = Vector2(0, _hand_row.card_h + 30.0)
	bottom.add_child(_hand_row)
	var side := VBoxContainer.new()  # to the right of the hand: the discard pile, with END TURN underneath
	side.add_theme_constant_override("separation", 4)
	bottom.add_child(side)
	_my_discard_box = VBoxContainer.new()
	side.add_child(_my_discard_box)
	_btn_end = _button("END TURN", _on_end_turn)
	_btn_end.custom_minimum_size = Vector2(0, 40)
	side.add_child(_btn_end)
	_btn_new = _button("New game", _show_setup)
	side.add_child(_btn_new)

	_status = Label.new()  # the messages bar
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	outer.add_child(_status)

	# The events log: a panel that slides over the right-hand side of the screen, toggled with LOG / X.
	_log_panel = PanelContainer.new()
	_log_panel.anchor_left = 0.68
	_log_panel.anchor_right = 1.0
	_log_panel.anchor_top = 0.0
	_log_panel.anchor_bottom = 1.0
	_log_panel.offset_top = 6.0
	_log_panel.offset_bottom = -34.0
	_log_panel.offset_right = -6.0
	_log_panel.visible = false
	_log_panel.z_index = 900
	var lsb := StyleBoxFlat.new()  # solid, so the board behind it does not show through the text
	lsb.bg_color = Color(0.05, 0.06, 0.09)
	lsb.set_border_width_all(2)
	lsb.border_color = Color(0.35, 0.37, 0.45)
	lsb.set_content_margin_all(8)
	_log_panel.add_theme_stylebox_override("panel", lsb)
	add_child(_log_panel)
	var lv := VBoxContainer.new()
	_log_panel.add_child(lv)
	var lh := HBoxContainer.new()
	lv.add_child(lh)
	var lt := Label.new()
	lt.text = "EVENTS LOG"
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lt.add_theme_font_size_override("font_size", 18)
	lh.add_child(lt)
	lh.add_child(_button("X", _toggle_log))
	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.fit_content = false
	lv.add_child(_log)

	_build_overlays()


func _toggle_log() -> void:
	_log_panel.visible = not _log_panel.visible


func _info_label() -> RichTextLabel:
	var l := RichTextLabel.new()  # rich text so "SUMMONING AVAILABLE" can be yellow
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_size_override("normal_font_size", 13)
	return l


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


func _overlay(parent: Control, dim: float) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.z_index = 1000  # above the hand, whose cards are drawn with a z_index
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	parent.add_child(root)
	root.visible = false
	return root


func _centered_box(root: Control, width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.add_child(box)
	panel.add_child(m)
	return box


func _build_overlays() -> void:
	# Setup
	_setup = _overlay(self, 0.92)
	var sb := _centered_box(_setup, 460)
	var title := Label.new()
	title.text = "Tactical Card Game - hotseat"
	title.add_theme_font_size_override("font_size", 24)
	sb.add_child(title)
	_deck0 = OptionButton.new()
	_deck1 = OptionButton.new()
	var names: Array = decks.keys()
	for n in names:
		_deck0.add_item(str(n))
		_deck1.add_item(str(n))
	if names.size() > 1:
		_deck1.select(1)
	for pair in [["Player 0 deck", _deck0], ["Player 1 deck", _deck1]]:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = pair[0]
		l.custom_minimum_size = Vector2(130, 0)
		row.add_child(l)
		pair[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pair[1])
		sb.add_child(row)
	var srow := HBoxContainer.new()
	var sl := Label.new()
	sl.text = "Seed (optional)"
	sl.custom_minimum_size = Vector2(130, 0)
	srow.add_child(sl)
	_seed = LineEdit.new()
	_seed.placeholder_text = "blank = random"
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(_seed)
	sb.add_child(srow)
	sb.add_child(_button("Start game", _on_start_pressed))

	# Cover between turns
	_cover = _overlay(self, 1.0)
	var cb := _centered_box(_cover, 420)
	_cover_label = Label.new()
	_cover_label.add_theme_font_size_override("font_size", 22)
	_cover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cb.add_child(_cover_label)
	cb.add_child(_button("Show my turn", _on_reveal))

	# Mulligan
	_mull = _overlay(self, 1.0)
	var mb := _centered_box(_mull, 1500)
	_mull_label = Label.new()
	_mull_label.add_theme_font_size_override("font_size", 20)
	mb.add_child(_mull_label)
	_mull_hand = HBoxContainer.new()  # every card on screen at once: the cards are sized to fit (see _show_mulligan)
	_mull_hand.add_theme_constant_override("separation", 6)
	_mull_hand.alignment = BoxContainer.ALIGNMENT_CENTER
	mb.add_child(_mull_hand)
	var mrow := HBoxContainer.new()
	mrow.add_child(_button("Keep this hand", _on_keep))
	_mull_btn = _button("Mulligan", _on_mulligan)
	mrow.add_child(_mull_btn)
	mb.add_child(mrow)

	# Choice popup
	_choice = _overlay(self, 0.6)
	var chb := _centered_box(_choice, 560)
	_choice_title = Label.new()
	_choice_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choice_title.add_theme_font_size_override("font_size", 18)
	chb.add_child(_choice_title)
	_choice_list = CardItemList.new()
	_choice_list.custom_minimum_size = Vector2(0, 260)
	_choice_list.allow_reselect = true
	chb.add_child(_choice_list)
	_choice_hint = Label.new()
	_choice_hint.add_theme_font_size_override("font_size", 12)
	chb.add_child(_choice_hint)
	var crow := HBoxContainer.new()
	_choice_ok = _button("OK", _on_choice_ok)
	crow.add_child(_choice_ok)
	crow.add_child(_button("Cancel", func() -> void: _choice_done.emit(null)))
	chb.add_child(crow)

	# End of game
	_end = _overlay(self, 0.8)
	var eb := _centered_box(_end, 440)
	_end_label = Label.new()
	_end_label.add_theme_font_size_override("font_size", 22)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eb.add_child(_end_label)
	eb.add_child(_button("Look at the board", func() -> void: _end.visible = false))
	eb.add_child(_button("New game", _show_setup))


# ================================================================ choice popup (used by TargetFlows)

## Options: Array of {"label", "value", "disabled"?}. Returns an Array of chosen values, or null if cancelled.
## min_n = 0 and max_n = 0 shows a read-only list.
func choose(title: String, options: Array, min_n: int = 1, max_n: int = 1) -> Variant:
	if auto_chooser.is_valid():
		return auto_chooser.call(title, options, min_n, max_n)
	_choice_title.text = title
	_choice_min = min_n
	_choice_max = max_n
	_choice_list.clear()
	_choice_list.cards.clear()
	_choice_list.select_mode = ItemList.SELECT_MULTI if max_n > 1 else ItemList.SELECT_SINGLE
	# When choosing is optional (min 0), add an explicit "None" row at the top (index shift handled on return).
	var none_row: bool = min_n == 0 and max_n > 0
	_choice_none_row = none_row
	if none_row:
		_choice_list.add_item("None (skip)")
		_choice_list.select(0)
	for o in options:
		var idx: int = _choice_list.add_item(str(o.label))
		_choice_list.set_item_disabled(idx, bool(o.get("disabled", false)))
		if o.has("tooltip"):
			_choice_list.set_item_tooltip(idx, str(o.tooltip))
		elif o.has("card"):  # hovering the row shows the card itself
			_choice_list.cards[idx] = o.card
			_choice_list.set_item_tooltip(idx, "card:%d" % idx)
	if max_n == 0:
		_choice_hint.text = "Read only."
	elif min_n == max_n:
		_choice_hint.text = "Choose %d." % min_n
	else:
		_choice_hint.text = "Choose %d to %d (click again to unselect)." % [min_n, max_n]
	_choice_ok.text = "Close" if max_n == 0 else "OK"
	_choice.visible = true
	var res: Variant = await _choice_done
	_choice.visible = false
	if res == null:
		return null
	var out: Array = []
	for i in res:
		if none_row:
			if int(i) == 0:
				continue  # the "None" row means nothing chosen
			out.append(options[int(i) - 1].value)
		else:
			out.append(options[i].value)
	return out


func _on_choice_ok() -> void:
	var sel: Array = Array(_choice_list.get_selected_items())
	if _choice_none_row:
		sel = sel.filter(func(i: int) -> bool: return i != 0)  # the "None" row is not a real choice
	if _choice_max == 0:
		_choice_done.emit([])
		return
	if sel.size() < _choice_min or sel.size() > _choice_max:
		_choice_hint.text = "Please choose between %d and %d." % [_choice_min, _choice_max]
		return
	_choice_done.emit(sel)


# ================================================================ starting a game

func _show_setup() -> void:
	for o in [_cover, _mull, _end, _choice]:
		o.visible = false
	_setup.visible = true


func _on_start_pressed() -> void:
	var names: Array = decks.keys()
	var s: int = int(_seed.text) if _seed.text.is_valid_int() else 0
	start_new_game(str(names[_deck0.selected]), str(names[_deck1.selected]), s)


func start_new_game(deck0: String, deck1: String, seed_value: int = 0) -> void:
	_setup.visible = false
	game = Game.new()
	# Each deck's Fortress card is played automatically at the start
	game.setup([CardDB.build_deck(cards, decks[deck0]), CardDB.build_deck(cards, decks[deck1])], seed_value, -1,
			[CardDB.deck_fortress(cards, decks[deck0]), CardDB.deck_fortress(cards, decks[deck1])])
	flows = TargetFlows.new(game, self)
	viewer = -1
	_status.text = ""
	_start_shown_turn = -1
	_log.clear()
	_log_seen = 0
	_next_mulligan(0)


func _next_mulligan(p: int) -> void:
	mulligan_player = p
	if p > 1:
		mulligan_player = -1
		_mull.visible = false
		game.start()
		_begin_turn_cover()
		return
	_show_cover("Mulligans: Player %d, take the device." % p, true)


func _show_mulligan_hand() -> void:
	var p: int = mulligan_player
	var ps: PlayerState = game.players[p]
	_mull.visible = true
	_mull_label.text = "Player %d: keep this hand or mulligan? (free mulligans left: %d)" % [p, int(game.rules.max_mulligans) - ps.mulligans]
	_mull_btn.disabled = ps.mulligans >= int(game.rules.max_mulligans)
	for c in _mull_hand.get_children():
		c.queue_free()
	var n: int = maxi(1, ps.hand.size())  # size the cards so that the whole hand fits on screen without scrolling
	var avail: float = maxf(400.0, get_viewport_rect().size.x - 80.0)
	var w: float = clampf((avail - 6.0 * float(n - 1)) / float(n), 120.0, HAND_CARD_W)
	for card in ps.hand:
		_mull_hand.add_child(CardView.create(card, w))


func _on_keep() -> void:
	_next_mulligan(mulligan_player + 1)


func _on_mulligan() -> void:
	game.mulligan(mulligan_player)
	_show_mulligan_hand()


# ================================================================ cover screen between turns

var _cover_for_mulligan: bool = false


func _show_cover(text: String, for_mulligan: bool = false) -> void:
	_cover_for_mulligan = for_mulligan
	_cover_label.text = text
	_cover.visible = true
	_mull.visible = false
	viewer = -1
	if game != null:
		refresh()


func _begin_turn_cover() -> void:
	if game.finished:
		refresh()
		return
	# No "take the device" screen between turns: the next player's turn starts immediately.
	_cover_for_mulligan = false
	_on_reveal()


func _on_reveal() -> void:
	_cover.visible = false
	if _cover_for_mulligan:
		_show_mulligan_hand()
		return
	viewer = game.active
	var p: int = game.active
	var ps: PlayerState = game.players[p]
	_show_start_of_turn()  # poison, abilities and the Fortress already happened when the turn began
	if not _fortress_options().is_empty():
		_status.text += "  |  Click your Fortress to castle or uncastle."
	refresh()
	call_deferred("_prompt_minotaur")


## Shows what the start-of-turn triggers did (poison damage, coin flips, Fortress mana...) in the status line.
func _show_start_of_turn() -> void:
	if game.start_summary_turn != game.turn or _start_shown_turn == game.turn:
		return
	_start_shown_turn = game.turn
	var lines: Array = []
	for line in game.start_summary:
		lines.append(str(line))
	_status.text = "Start of turn:  " + "  •  ".join(lines)


# ================================================================ drawing the board

func _card_button(card: Dictionary, selected: bool, min_size: Vector2, handler: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = min_size
	b.text = _card_text(card)
	b.tooltip_text = _card_full_text(card)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style(b, _card_color(card), selected)
	if handler.is_valid():
		b.pressed.connect(handler)
	return b


func _card_color(card: Dictionary) -> Color:
	return COLORS.get(str(card.get("color", "")), NEUTRAL)


func _style(b: Button, base: Color, selected: bool) -> void:
	var is_light: bool = base.get_luminance() > 0.5
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = base.lightened(0.12) if state == "hover" else base
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(4 if selected else 1)
		sb.border_color = Color(1, 0.9, 0.3) if selected else base.lightened(0.35)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, sb)
	var fc := Color(0.08, 0.08, 0.1) if is_light else Color(0.96, 0.96, 0.96)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(key, fc)
	b.add_theme_font_size_override("font_size", 13)


func _atk_label(atk: Dictionary) -> String:
	var dmg_text: String = str(int(atk.get("damage", 0))) if int(atk.get("damage", 0)) > 0 else "-"
	if atk.has("coins"):
		dmg_text = "%dX%d" % [int(atk.coins.count), int(atk.coins.per_heads_damage)]
	var s: String = "%s %s" % [atk.get("name", "?"), dmg_text]
	if int(atk.get("mana_cost", 0)) > 0:
		s += " (%d mana)" % int(atk.mana_cost)
	if atk.has("requires"):
		s += " (needs HP %d+)" % int(atk.requires.get("self_hp_at_least", 0))
	return s


func _card_text(card: Dictionary) -> String:
	var kind: String = str(card.get("kind", ""))
	var lines: Array = [str(card.get("name", "?"))]
	if kind == "champion":
		lines.append("%s %s %s · HP %d" % [card.get("color", ""), card.get("class", ""), card.get("type", ""), int(card.get("hp", 0))])
		var req: Dictionary = card.get("summon", {})
		if int(req.get("sacrifice", 0)) > 0:
			lines.append("Summon: sacrifice %d" % int(req.sacrifice))
		elif int(req.get("mana", 0)) > 0:
			lines.append("Summon: %d mana" % int(req.mana))
		for atk in card.get("attacks", []):
			lines.append("• " + _atk_label(atk))
		if card.has("ability"):
			lines.append("Ability")
	else:
		lines.append("%s · cost %d" % [kind.capitalize(), int(card.get("cost", 0))])
		for t in card.get("text", []):
			lines.append("• " + str(t))
	return "\n".join(lines)


func _card_full_text(card: Dictionary) -> String:
	var lines: Array = [_card_text(card)]
	if str(card.get("kind", "")) == "champion":
		for atk in card.get("attacks", []):
			if atk.has("text"):
				lines.append("%s: %s" % [atk.name, atk.text])
		if card.has("ability"):
			lines.append("Ability: " + str(card.ability.get("text", "")))
	return "\n".join(lines)


func _champion_text(c: Champion) -> String:
	var lines: Array = ["%s%s" % [c.card_name(), "  [Encamped]" if game.players[c.owner].castled else ""]]
	lines.append("%s %s %s" % [c.color(), c.champion_class(), c.champion_type()])
	lines.append("HP %d / %d" % [c.current_hp(), c.max_hp()])
	for atk in c.card.attacks:
		var ok: bool = not atk.has("requires") or c.current_hp() >= int(atk.requires.get("self_hp_at_least", 0))
		lines.append(("• " if ok else "✗ ") + _atk_label(atk))
	if c.has_ability():
		lines.append("Ability: " + str(c.card.ability.get("text", "")).left(70))
	for st in c.statuses:
		lines.append("[%s]" % _status_text(st))
	return "\n".join(lines)


func _status_text(st: Dictionary) -> String:
	match str(st.kind):
		"poison":
			return "Poisoned %d" % int(st.get("amount", 10))
		"protected":
			return "Protected"
		"no_attack":
			return "Cannot attack"
		"duel":
			return "Duel"
		"next_attack_bonus":
			return "Next attack +%d" % int(st.get("amount", 0))
		"stored_bonus":
			return "Gnaw +%d" % int(st.get("amount", 0))
	return str(st.kind)


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)  # detach at once: a node that is only queued for deletion still takes up layout space
		c.queue_free()


var _log_seen: int = 0


func refresh() -> void:
	if game == null:
		return
	var p: int = game.active
	_turn_label.text = "Turn %d · Player %d%s" % [game.turn, p, "  (game over)" if game.finished else ""]
	var mine: bool = viewer == p and not game.finished and not _cover.visible
	_render_board(_opp_box, _opp_info, 1 - p, false)
	_render_board(_me_box, _me_info, p, true)
	_opp_discard_btn.text = "Opponents Discard Pile (%d)" % game.players[1 - p].discard.size()
	_clear(_my_deck_box)
	_my_deck_box.add_child(_deck_pile(game.players[p], _hand_w - 18.0))  # the same size as the discard pile
	_opp_deck_label.text = "   Opponent's deck: %d" % game.players[1 - p].deck.size()
	_clear(_my_discard_box)
	_my_discard_box.add_child(_discard_pile(game.players[p], p, _hand_w - 18.0))  # as tall as the hand, with END TURN under it
	_render_hand()
	var ps: PlayerState = game.players[p]
	_btn_new.visible = game.finished
	_btn_end.disabled = not mine
	_update_end_turn_highlight(mine)
	_attack_hint.text = Preflight.attackers_text(game, p) if mine else ""
	while _log_seen < game.log_lines.size():
		_log.append_text(game.log_lines[_log_seen] + "\n")
		_log_seen += 1
	if game.finished and not _end.visible and not _cover.visible:
		_end_label.text = "Draw: %s" % game.win_reason if game.winner == 2 else "Player %d wins!\n%s" % [game.winner, game.win_reason]
		_end.visible = true


## One player's row: the play area (champions, encamped ones faded and asleep), then the Fortress, then the
## enchantment area. The play area and the enchantment area are where hand cards are dropped.
func _render_board(box: VBoxContainer, info: RichTextLabel, p: int, is_active: bool) -> void:
	_clear(box)
	var ps: PlayerState = game.players[p]
	var summoning: bool = is_active and _summoning_available(ps)
	info.text = "Player %d%s   Mana %d   Hand %d   Kills %d/%d   Castles used %d/%d%s%s" % [
		p, "  (YOUR TURN)" if is_active else "", ps.mana, ps.hand.size(), ps.kills,
		int(game.rules.annihilation_goal), ps.castles_used, int(game.rules.castles_per_game),
		("   [color=#ffd940]SUMMONING AVAILABLE%s[/color]" % _summons_suffix(ps)) if summoning else "",
		("   [CASTLED: Fortress vulnerable to attack, champions encamped, turns remaining:%d]" % maxi(0, int(game.rules.max_castled_turns) - ps.castled_turns)) if ps.castled else ""]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var play := _area_zone(Color(0.11, 0.12, 0.18), {"kind": "play", "owner": p})  # champions are dropped here
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.add_child(_champion_flow(ps, is_active))
	row.add_child(play)
	var divider := VSeparator.new()  # a thin line, with space on both sides, between the play area and the Fortress
	divider.custom_minimum_size = Vector2(22, 0)
	row.add_child(divider)
	var mine: bool = is_active and viewer == p and not game.finished and not _cover.visible
	var glow: bool = mine and not ps.castled and not _fortress_options().is_empty()  # yellow border: the Fortress has something to offer
	var fv := CardView.create(fortress_card(ps), BOARD_CARD_W, null, true, glow, ps.castled, game)
	if is_active:  # clicking the enemy Fortress does nothing
		fv.pressed.connect(_on_fortress_clicked)
	_wire_drop(fv, {"kind": "board", "owner": p})
	row.add_child(fv)
	var ench := _area_zone(Color(0.1, 0.15, 0.12), {"kind": "ench", "owner": p})  # enchantments are dropped here
	ench.custom_minimum_size = Vector2(3.0 * (BOARD_CARD_W + 6.0) + 6.0, BOARD_CARD_H + 10.0)
	ench.add_child(_enchantment_area(ps))
	row.add_child(ench)
	box.add_child(row)


## A panel that accepts dragged cards, outlined in yellow while a card that may land there is over it.
func _area_zone(color: Color, target: Dictionary) -> DropZone:
	var panel := DropZone.new()
	panel.custom_minimum_size = Vector2(0, BOARD_CARD_H + 10.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_content_margin_all(4)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.set_border_width_all(4)
	hover.border_color = Color(1.0, 0.9, 0.25)
	panel.normal_style = sb
	panel.hover_style = hover
	panel.add_theme_stylebox_override("panel", sb)
	_wire_drop(panel, target)
	return panel


## The champions of one player, in a row. Each champion is also a drop target (it counts as the play area).
func _champion_flow(ps: PlayerState, is_active: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for c in ps.champions:
		var v := CardView.create(c.card, BOARD_CARD_W, c, true, c.attacked_this_turn and is_active, ps.castled, game, Color(0.95, 0.15, 0.15))  # red once it has attacked
		if is_active:
			v.pressed.connect(_on_own_champion.bind(c.uid))
		_wire_drop(v, {"kind": "play", "owner": ps.index})
		row.add_child(_stack_with_attachments(c, v))
	return row


## A champion with attached cards is drawn in front of them, at the same height: the attached cards sit behind it
## and peek out to the right, one step for each card. (Hover the champion to see everything in full.)
func _stack_with_attachments(c: Champion, view: CardView) -> Control:
	var n: int = c.attached.size()
	if n == 0:
		return view
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BOARD_CARD_W + ATTACH_STEP * n, BOARD_CARD_H)
	for i in range(n - 1, -1, -1):  # the furthest back is drawn first
		var back: CardView = CardView.create(c.attached[i], BOARD_CARD_W, null, true)
		back.position = Vector2(ATTACH_STEP * (i + 1), 0.0)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(back)
	view.position = Vector2.ZERO
	view.size = view.custom_minimum_size
	holder.add_child(view)
	return holder


## The Fortress as a card: its definition plus the HP it has right now.
func fortress_card(ps: PlayerState) -> Dictionary:
	var f: Dictionary = ps.fortress_def.duplicate()
	f["kind"] = "fortress"
	if not f.has("name"):
		f["name"] = "Fortress"
	if not f.has("id"):
		f["id"] = "fortress"
	if not f.has("text"):
		f["text"] = []
	f["hp"] = int(f.get("hp", 500))
	f["hp_now"] = ps.fortress_hp
	return f


## The deck: the card back (art/ui/card_background.png) as a stack, with the number of cards in it.
func _deck_pile(ps: PlayerState, width: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, width * 650.0 / 490.0)
	var back: Texture2D = load("res://art/ui/card_background.png")
	var layers: int = mini(3, ps.deck.size())
	for i in range(layers - 1, -1, -1):  # a little stack: the lower cards peek out
		var r := TextureRect.new()
		r.texture = back
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.position = Vector2(float(i) * 3.0, float(i) * -3.0)
		r.size = Vector2(width - 8.0, width * 650.0 / 490.0 - 8.0) + Vector2(0, 8)
		r.position += Vector2(0, 8)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.modulate = Color(1, 1, 1) if i == 0 else Color(0.6, 0.6, 0.65)
		holder.add_child(r)
	if layers == 0:
		var empty := Panel.new()
		empty.set_anchors_preset(Control.PRESET_FULL_RECT)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(empty)
	var l := Label.new()
	l.text = "Deck\n(%d)" % ps.deck.size()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(l)
	return holder


## The discard pile: the top card faded, so it is not mistaken for anything in play. Click to browse it.
func _discard_pile(ps: PlayerState, p: int, width: float = BOARD_CARD_W) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, width * 650.0 / 490.0)
	if ps.discard.is_empty():
		var empty := Panel.new()
		empty.set_anchors_preset(Control.PRESET_FULL_RECT)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(empty)
	else:
		var top := CardView.create(ps.discard[ps.discard.size() - 1], width, null, true)
		top.modulate = Color(1, 1, 1, 0.3)
		top.tooltip_text = ""
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(top)
	var b := Button.new()
	b.flat = true
	b.text = "Discard\n(%d)" % ps.discard.size()
	b.add_theme_font_size_override("font_size", 16)
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.pressed.connect(_on_view_discard.bind(p))
	holder.add_child(b)
	return holder


## The enchantments in play, side by side. Right-click one of your own to remove it.
func _enchantment_area(ps: PlayerState) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in ps.enchantments.size():
		var v := CardView.create(ps.enchantments[i], BOARD_CARD_W, null, true)
		if ps.index == game.active:
			v.right_pressed.connect(_on_enchantment_right_click.bind(i))  # right-click: remove it
		_wire_drop(v, {"kind": "ench", "owner": ps.index})
		row.add_child(v)
	return row



func _render_hand() -> void:
	_hand_row.set_views([])
	var p: int = game.active
	if viewer != p or _cover.visible:
		_hand_label.text = "Hand hidden"
		return
	var ps: PlayerState = game.players[p]
	_hand_label.text = "Your hand (%d cards) · Mana %d · Colors that attacked this turn: %s" % [ps.hand.size(), ps.mana, ", ".join(ps.colors_used) if not ps.colors_used.is_empty() else "none"]
	var views: Array = []
	for i in ps.hand.size():
		var v := CardView.create(ps.hand[i], _hand_w)
		v.drag_data = {"hand_index": i, "kind": str(ps.hand[i].get("kind", "")), "player": p}  # drag it onto the board
		v.pressed.connect(_on_hand_card.bind(i))
		views.append(v)
	_hand_row.set_views(views)


func ps_hand_width() -> float:
	var n: int = game.players[game.active].hand.size() if game != null else 0
	return float(n) * (_hand_w + 6.0)


# ================================================================ actions

func _my_turn() -> bool:
	return game != null and not game.finished and viewer == game.active and not busy


func _report(res: Dictionary) -> bool:
	if res.ok:
		_status.text = ""
		_show_start_of_turn()
	else:
		_status.text = str(res.error)
	refresh()
	return bool(res.ok)


## What clicking your own Fortress offers right now: castle or uncastle in the Castle step (Cancel just closes it).
## (There is no Fortress heal any more: the Fortress ability triggers by itself at the start of the turn.)
func _fortress_options() -> Array:
	var opts: Array = []
	if game == null or game.finished:
		return opts
	var p: int = game.active
	var ps: PlayerState = game.players[p]
	if game.step == Game.Step.OPEN:
		if ps.castled:
			opts.append({"label": "Uncastle: bring your champions back into play", "value": "uncastle"})
		elif Preflight.castle_problem(game, p) == "":
			opts.append({"label": "Castle: your champions are encamped, you draw 2 cards a turn", "value": "castle"})
	return opts


## The same condition as the "SUMMONING AVAILABLE" text.
func _summoning_available(ps: PlayerState) -> bool:
	return not game.finished and ps.summons_this_turn < game.summons_allowed(ps.index)  # summoning works at any time during your turn


## " (2)" while castled (two summons left), " (1)" when one of the two is left; nothing when it is the usual single summon.
func _summons_suffix(ps: PlayerState) -> String:
	if game.summons_allowed(ps.index) <= 1:
		return ""
	return " (%d)" % (game.summons_allowed(ps.index) - ps.summons_this_turn)


var _minotaur_prompted_turn: int = -1


## Minotaur: at the start of your turn, choose a card attached to an opponent's champion to discard.
func _prompt_minotaur() -> void:
	if game == null or game.finished or busy:
		return
	var p: int = game.active
	if viewer != p or _cover.visible or game.players[p].pending_minotaur <= 0 or _minotaur_prompted_turn == game.turn:
		return
	_minotaur_prompted_turn = game.turn
	busy = true
	while game.players[p].pending_minotaur > 0:
		var opts: Array = []
		for c in game.players[1 - p].champions:
			for i in c.attached.size():
				opts.append({"label": "%s (on %s)" % [str(c.attached[i].get("name", "?")), game.describe_champion(c)], "value": "%d:%d" % [c.uid, i]})
		if opts.is_empty():
			break
		var pick: Variant = await choose("Minotaur: discard which attached card?", opts, 1, 1)
		if pick == null or (pick as Array).is_empty():
			break
		var parts: PackedStringArray = str((pick as Array)[0]).split(":")
		_report(game.minotaur_discard(p, int(parts[0]), int(parts[1])))
	busy = false
	refresh()


## True when this player has nothing more to do: no champion can attack and no spell or enchantment can be played.
func _nothing_left_to_do() -> bool:
	if game == null or game.finished:
		return false
	var p: int = game.active
	var ps: PlayerState = game.players[p]
	if _summoning_available(ps):
		return false
	for c in ps.champions:
		if Preflight.attack_problem(game, p, c) == "":
			return false
	if not ps.is_first_turn():
		for card in ps.hand:
			var kind: String = str(card.get("kind", ""))
			if kind == "spell" and not LockRules.is_locked(game, p, "spell") and int(card.get("cost", 0)) <= ps.mana:
				return false
			if kind == "enchantment" and not LockRules.is_locked(game, p, "enchantment") and int(card.get("cost", 0)) <= ps.mana:
				return false  # (with every enchantment slot full it can still replace one)
	return true


## END TURN gets a yellow border when there is nothing left to do this turn.
func _update_end_turn_highlight(mine: bool) -> void:
	if mine and _nothing_left_to_do():
		for state in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.2, 0.22, 0.28) if state != "hover" else Color(0.27, 0.29, 0.36)
			sb.set_border_width_all(4)
			sb.border_color = Color(1.0, 0.9, 0.25)
			sb.set_corner_radius_all(3)
			_btn_end.add_theme_stylebox_override(state, sb)
	else:
		for state in ["normal", "hover", "pressed"]:
			_btn_end.remove_theme_stylebox_override(state)


func _on_fortress_clicked() -> void:
	if not _my_turn():
		return
	var opts: Array = _fortress_options()
	var lock: String = TurnRules.castle_lock_text(game, game.players[game.active])
	if lock != "" and game.step == Game.Step.OPEN and not game.players[game.active].castled:
		_status.text = lock  # how long until this player may castle
	if opts.is_empty():
		var why: String = Preflight.castle_problem(game, game.active) if game.step == Game.Step.OPEN else ""
		_status.text = "Nothing to do with your Fortress right now." + ("  Castling: " + why if why != "" else "")
		return
	busy = true
	var res: Variant = await choose("Your Fortress", opts, 1, 1)
	busy = false
	if res == null or (res as Array).is_empty():
		return
	match str((res as Array)[0]):
		"castle":
			_report(game.castle(game.active))
		"uncastle":
			_report(game.uncastle(game.active))


func _on_castle() -> void:
	if _my_turn():
		_report(game.castle(game.active))


func _on_uncastle() -> void:
	if _my_turn():
		_report(game.uncastle(game.active))


func _on_end_turn() -> void:
	if not _my_turn():
		return
	var ps: PlayerState = game.players[game.active]
	if ps.hand.size() > int(game.rules.max_hand_size):  # hand limit: you must discard down to it first
		busy = true
		while ps.hand.size() > int(game.rules.max_hand_size):
			var opts: Array = []
			for i in ps.hand.size():
				opts.append({"label": str(ps.hand[i].get("name", "?")), "value": i})
			var pick: Variant = await choose("Hand limit (%d): discard %d card(s) before ending your turn" % [int(game.rules.max_hand_size), ps.hand.size() - int(game.rules.max_hand_size)], opts, 1, 1)
			if pick == null or (pick as Array).is_empty():
				busy = false
				refresh()
				return  # cancelled: the turn does not end
			game.discard_hand_card(game.active, int((pick as Array)[0]))
			refresh()
		busy = false
	var res: Dictionary = game.end_turn(game.active)
	_report(res)
	if res.ok and not game.finished:
		_begin_turn_cover()


func _pick_champion(title: String, list: Array) -> Variant:
	var opts: Array = []
	for c in list:
		opts.append({"label": game.describe_champion(c) + (" (damage %d)" % c.damage if c.damage > 0 else ""), "value": c.uid})
	var res: Variant = await choose(title, opts, 1, 1)
	if res == null or (res as Array).is_empty():
		return null
	return (res as Array)[0]


func _on_view_opp_discard() -> void:
	if game != null:
		_on_view_discard(1 - game.active)


func _on_view_discard(p: int) -> void:
	if busy:
		return
	busy = true
	var opts: Array = []
	for card in game.players[p].discard:
		opts.append({"label": "%s (%s)" % [card.get("name", "?"), card.get("kind", "")], "value": 0, "card": card})
	await choose("Player %d's discard pile (%d cards)" % [p, opts.size()], opts, 0, 0)
	busy = false


## Right-click on one of your enchantments in play: offers to remove it (it goes to your discard pile).
func _on_enchantment_right_click(index: int) -> void:
	if not _my_turn():
		return
	var ps: PlayerState = game.players[game.active]
	if index >= ps.enchantments.size():
		return
	var name: String = str(ps.enchantments[index].get("name", "this enchantment"))
	busy = true
	var ans: Variant = await choose("Enchantment: %s" % name, [{"label": "Remove %s (it goes to your discard pile)" % name, "value": "remove"}], 1, 1)
	busy = false
	if ans != null and not (ans as Array).is_empty() and str((ans as Array)[0]) == "remove":
		_report(game.remove_own_enchantment(game.active, index))
	refresh()


## Cards are played by dragging them onto the board, so a plain click only says so.
func _on_hand_card(_i: int) -> void:
	if not _my_turn():
		return
	_status.text = "Drag the card onto the board to play it: champions into a slot, enchantments into an enchantment slot, spells anywhere (onto a champion to target it)."


# ================================================================ drag and drop

## Connects a board control (a DropZone or a CardView) to the drop rules for the given target description.
func _wire_drop(ctrl: Control, target: Dictionary) -> void:
	var check := _can_drop.bind(target)
	var done := _on_drop.bind(target)
	if ctrl is DropZone:
		(ctrl as DropZone).check = check
		(ctrl as DropZone).done = done
	elif ctrl is CardView:
		(ctrl as CardView).drop_check = check
		(ctrl as CardView).drop_do = done


## Whether the dragged hand card may land on this target (this only decides the highlight; the reasons it may
## still be refused are shown in the messages bar when it is dropped).
func _can_drop(data: Variant, target: Dictionary) -> bool:
	if not (data is Dictionary) or not (data as Dictionary).has("hand_index") or not _my_turn():
		return false
	var p: int = game.active
	if int((data as Dictionary).get("player", -1)) != p:
		return false
	match str(data.kind):
		"champion":  # into your own play area (sacrifice summons: anywhere in it; the menu asks who to sacrifice)
			return int(target.get("owner", -1)) == p and str(target.kind) == "play"
		"enchantment":
			return int(target.get("owner", -1)) == p and (str(target.kind) == "ench")
		"spell":
			return true
	return false


func _on_drop(data: Variant, target: Dictionary) -> void:
	if not _can_drop(data, target) or busy:
		return
	busy = true
	await play_hand_card(int(data.hand_index), {"owner": int(target.get("owner", -1))})
	busy = false
	refresh()


## Everything that happens when a hand card is played: its choices, then the engine call. ctx says where it was
## dropped: {"owner"} is the player whose area it landed on. Every choice (who to sacrifice, which champion a spell
## goes on, which enchantment to replace) is a menu.
func play_hand_card(i: int, ctx: Dictionary = {}) -> Dictionary:
	var p: int = game.active
	var ps: PlayerState = game.players[p]
	var card: Dictionary = ps.hand[i]
	var kind: String = str(card.get("kind", ""))
	var res: Dictionary = {"ok": false, "error": "Nothing happened."}
	var problem: String = ""  # say no BEFORE any menus
	match kind:
		"champion":
			problem = Preflight.summon_problem(game, p, i)
		"enchantment":
			var full: bool = ps.enchantments.size() >= int(game.rules.enchantment_limit)
			problem = Preflight.enchantment_problem(game, p, i, full)  # when full, the menu asks which one to replace
		"spell":
			problem = Preflight.spell_problem(game, p, i)
	if problem == "" and kind == "champion":
		var req: Dictionary = card.get("summon", {})
		var sac_need: int = maxi(0, int(req.get("sacrifice", 0)) - ps.summon_discount) if int(req.get("sacrifice", 0)) > 0 else 0
		if sac_need == 0 and ps.champions.size() >= int(game.rules.board_limit):
			problem = "Your play area is full."
		elif sac_need == 0 and int(ctx.get("slot", -1)) >= 0 and int(ctx.get("champion", -1)) >= 0:
			problem = "That slot is already taken: drop it on an empty slot."
	if problem != "":
		_status.text = problem
		return {"ok": false, "error": problem}
	if kind == "champion":
		var sc: Dictionary = await flows.summon_choices(p, i)
		if sc.has("error"):
			res = {"ok": false, "error": sc.error}
		elif sc.has("cancelled"):
			return {"ok": false, "error": ""}
		else:
			# Warn before carried-over damage would destroy the new champion straight away
			var carried: int = 0
			for uid in sc.sacrifices:
				var sac: Champion = game._champion_of(game.players[p], int(uid))
				if sac != null:
					carried += sac.damage
			var new_hp: int = int(card.get("hp", 0))
			if not ps.castled:  # Super Shrink (and the like) already applies to the champion that is about to arrive
				for e in game.players[1 - p].enchantments:
					new_hp += int(e.get("hp_aura_enemy", 0))
				new_hp = maxi(0, new_hp)
			if carried >= new_hp and new_hp > 0:
				var ok: Variant = await choose(
					"WARNING: %d damage carries over to %s (%d HP). It will be destroyed the moment it is summoned, and your opponent scores an Annihilation point." % [carried, card.get("name", "this champion"), new_hp],
					[{"label": "Summon it anyway", "value": "go"}, {"label": "Cancel", "value": "cancel"}], 1, 1)
				if ok == null or (ok as Array).is_empty() or str((ok as Array)[0]) != "go":
					return {"ok": false, "error": ""}
			res = game.summon(p, i, sc.sacrifices, "", int(ctx.get("slot", -1)))
	elif kind == "enchantment":
		var full2: bool = ps.enchantments.size() >= int(game.rules.enchantment_limit)
		if full2:  # all enchantment places are used: choose which one to replace
			var eopts: Array = []
			for k in ps.enchantments.size():
				var e: Dictionary = ps.enchantments[k]
				eopts.append({"label": "%s (%d turns left)" % [e.get("name", "?"), int(e.get("turns_left", 0))], "value": k, "card": e})
			var pick: Variant = await choose("Replace which enchantment with %s?" % card.get("name", "the new one"), eopts, 1, 1)
			if pick == null or (pick as Array).is_empty():
				return {"ok": false, "error": ""}
			res = game.replace_enchantment(p, i, int((pick as Array)[0]))
		else:
			res = game.play_enchantment(p, i)
	elif kind == "spell":
		var effects: Array = card.effects
		var effect_index: int = 0
		if effects.size() > 1:
			var opts: Array = []
			for e in effects.size():
				opts.append({"label": str(card.text[e]) if card.has("text") and e < card.text.size() else "Effect %d" % (e + 1), "value": e})
			var pick: Variant = await choose("%s: choose ONE effect" % card.get("name", "Spell"), opts, 1, 1)
			if pick == null or (pick as Array).is_empty():
				return {"ok": false, "error": ""}
			effect_index = int((pick as Array)[0])
		var tf: Dictionary = await flows.spell_target(p, i, effect_index, int(ctx.get("champion", -1)))
		if tf.has("error"):
			res = {"ok": false, "error": tf.error}
		elif tf.has("cancelled"):
			return {"ok": false, "error": ""}
		else:
			res = game.play_spell(p, i, effect_index, tf.target)
			if res.ok and not ps.pending_wizardry.is_empty():  # Wizardry: you choose which of the drawn cards to discard
				var opts2: Array = []
				for k in ps.pending_wizardry.size():
					opts2.append({"label": str(ps.pending_wizardry[k].get("name", "?")), "value": k})
				var pick2: Variant = await choose("Wizardry: discard which of the %d cards you drew?" % opts2.size(), opts2, 1, 1)
				game.wizardry_discard(p, int((pick2 as Array)[0]) if pick2 != null and not (pick2 as Array).is_empty() else 0)
	_report(res)
	return res


func _on_own_champion(uid: int) -> void:
	if not _my_turn():
		return
	busy = true
	await attack_with(uid)
	busy = false
	refresh()


func _atk_menu_label(c: Champion, atk: Dictionary) -> String:
	var shown: Dictionary = atk.duplicate()
	if not atk.has("coins"):
		var now: int = DamageRules.preview(game, c, atk)  # includes saved bonuses, so Grimn's Gnaw reads 40
		if now > 0:
			shown["damage"] = now
	return _atk_label(shown)


func attack_with(uid: int) -> Dictionary:
	var p: int = game.active
	var c: Champion = game._champion_of(game.players[p], uid)
	if c == null:
		return {"ok": false, "error": "No such champion."}
	var problem: String = Preflight.attack_problem(game, p, c, -1)  # no menus if this champion cannot attack at all
	if problem != "":
		_status.text = problem
		return {"ok": false, "error": problem}
	var opts: Array = []
	for ai in c.card.attacks.size():
		var atk: Dictionary = c.card.attacks[ai]
		var why: String = Preflight.attack_problem(game, p, c, ai)
		var tip: String = str(atk.get("text", ""))
		opts.append({"label": _atk_menu_label(c, atk) + ("   ✗ " + why if why != "" else ""), "value": ai,
				"tooltip": why if why != "" else tip, "disabled": why != ""})
	var pick: Variant = await choose("%s%s: which attack?" % [c.card_name(), game.champion_tag(c)], opts, 1, 1)
	if pick == null or (pick as Array).is_empty():
		return {"ok": false, "error": ""}
	var ai2: int = int((pick as Array)[0])
	var tf: Dictionary = await flows.attack_target(p, c, ai2)
	if tf.has("error"):
		_status.text = str(tf.error)
		return {"ok": false, "error": tf.error}
	if tf.has("cancelled"):
		return {"ok": false, "error": ""}
	var mark: int = game.log_lines.size()
	var res: Dictionary = game.attack(p, uid, ai2, tf.target)
	_report(res)
	if res.ok:  # show the coin flips this attack made, so a Heads or Tails result is never missed
		var coins: Array = []
		for line in game.log_lines.slice(mark):
			if str(line).begins_with("Coin") or "Heads out of" in str(line):
				coins.append(str(line))
		if not coins.is_empty():
			_status.text = "  ".join(coins)
	return res
