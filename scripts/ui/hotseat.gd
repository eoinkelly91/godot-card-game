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
const HAND_CARD_W := 140.0
const BOARD_CARD_W := 108.0
const BOARD_CARD_H := BOARD_CARD_W * 650.0 / 490.0

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
var _hand_row: HBoxContainer
var _hand_scroll: ScrollContainer
var _hand_label: Label
var _status: Label
var _attack_hint: Label
var _heal_prompted_turn: int = -1
var _start_shown_turn: int = -1
var _turn_label: Label
var _log: RichTextLabel
var _opp_info: Label
var _me_info: Label
var _btn_next: Button
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
var _choice_list: ItemList
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
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 8)
	outer.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	cols.add_child(left)

	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 18)
	left.add_child(_turn_label)
	# Board, like the mock-up: opponent's two rows on top, yours below. Each player has an ACTIVE row and an
	# ENCAMPED row; the champions and the Fortress group (discard pile, Fortress, enchantments) swap when castled.
	_opp_info = _info_label()
	left.add_child(_opp_info)
	_opp_box = VBoxContainer.new()
	_opp_box.add_theme_constant_override("separation", 3)
	left.add_child(_opp_box)
	_me_box = VBoxContainer.new()
	_me_box.add_theme_constant_override("separation", 3)
	left.add_child(_me_box)
	_me_info = _info_label()
	left.add_child(_me_info)

	_attack_hint = Label.new()
	_attack_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attack_hint.add_theme_font_size_override("font_size", 13)
	_attack_hint.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	left.add_child(_attack_hint)
	_hand_label = Label.new()
	_hand_label.add_theme_font_size_override("font_size", 14)
	left.add_child(_hand_label)
	_hand_scroll = ScrollContainer.new()
	_hand_scroll.custom_minimum_size = Vector2(0, HAND_CARD_W * 650.0 / 490.0 + 24.0)
	_hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS  # the bar stays (hidden when not needed)
	_hand_scroll.gui_input.connect(_on_hand_gui_input)
	_hand_scroll.resized.connect(_fix_hand_scroll)
	left.add_child(_hand_scroll)
	_hand_row = HBoxContainer.new()
	_hand_row.add_theme_constant_override("separation", 6)
	_hand_scroll.add_child(_hand_row)

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	cols.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var lt := Label.new()
	lt.text = "Events"
	lt.add_theme_font_size_override("font_size", 16)
	rv.add_child(lt)
	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.fit_content = false
	rv.add_child(_log)
	var legend := Label.new()
	legend.text = "Hover a card for its full text. Click your Fortress at the start of your turn to castle or heal; click a champion to attack, a hand card to play it."
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_theme_font_size_override("font_size", 11)
	rv.add_child(legend)
	_btn_next = _button("To Attack step", _on_next_step)
	_btn_end = _button("END TURN", _on_end_turn)
	_btn_end.custom_minimum_size = Vector2(0, 44)
	_btn_new = _button("New game", _show_setup)
	for b in [_btn_next, _btn_end, _btn_new]:
		rv.add_child(b)

	_status = Label.new()  # the messages bar
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	outer.add_child(_status)

	_build_overlays()


func _info_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 13)
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
	var mb := _centered_box(_mull, 1560)  # 7 cards fit without scrolling
	_mull_label = Label.new()
	_mull_label.add_theme_font_size_override("font_size", 20)
	mb.add_child(_mull_label)
	var ms := ScrollContainer.new()
	ms.custom_minimum_size = Vector2(0, HAND_CARD_W * 650.0 / 490.0 + 24.0)
	ms.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mb.add_child(ms)
	_mull_hand = HBoxContainer.new()
	ms.add_child(_mull_hand)
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
	_choice_list = ItemList.new()
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
	var fort: Dictionary = CardDB.default_fortress(cards)
	game.setup([CardDB.build_deck(cards, decks[deck0]), CardDB.build_deck(cards, decks[deck1])], seed_value, -1, [fort, fort])
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
	for card in ps.hand:
		_mull_hand.add_child(CardView.create(card, HAND_CARD_W))


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
	if game.step == Game.Step.CASTLE and not ps.castled and Preflight.castle_problem(game, p) != "":
		# Nothing to decide in the Castle step: the start-of-turn triggers (Fortress, poison, abilities) happen now.
		game.next_step(p)
		_show_start_of_turn()
	elif game.step == Game.Step.CASTLE:
		_status.text = "Castle step: click your Fortress to castle or uncastle, or just play a card or attack to carry on (the Fortress, poison and start-of-turn abilities trigger then)."
	refresh()
	call_deferred("_prompt_heal_if_needed")


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
		c.queue_free()


var _log_seen: int = 0


func refresh() -> void:
	if game == null:
		return
	var p: int = game.active
	_turn_label.text = "Turn %d · Player %d · %s step%s" % [game.turn, p, ["Castle", "Summon", "Attack"][game.step], "  (game over)" if game.finished else ""]
	var mine: bool = viewer == p and not game.finished and not _cover.visible
	_render_board(_opp_box, _opp_info, 1 - p, false, true)
	_render_board(_me_box, _me_info, p, true, false)
	_render_hand()
	var ps: PlayerState = game.players[p]
	var first_turn: bool = ps.is_first_turn()  # a player's first turn is only draw and summon: no attack step
	_btn_next.visible = mine and game.step == Game.Step.SUMMON and not first_turn
	_btn_next.disabled = not mine
	_btn_new.visible = game.finished
	_btn_end.disabled = not mine
	_attack_hint.text = Preflight.attackers_text(game, p) if mine and game.step != Game.Step.CASTLE else ""
	while _log_seen < game.log_lines.size():
		_log.append_text(game.log_lines[_log_seen] + "\n")
		_log_seen += 1
	if game.finished and not _end.visible and not _cover.visible:
		_end_label.text = "Draw: %s" % game.win_reason if game.winner == 2 else "Player %d wins!\n%s" % [game.winner, game.win_reason]
		_end.visible = true


## One player's two rows. Not castled: champions in the ACTIVE row, the Fortress group (discard pile, Fortress,
## enchantments) in the ENCAMPED row. Castled: they swap. The opponent's encamped row is on top, yours is at the bottom.
func _render_board(box: VBoxContainer, info: Label, p: int, is_active: bool, top_is_encamped: bool) -> void:
	_clear(box)
	var ps: PlayerState = game.players[p]
	info.text = "Player %d%s   Mana %d   Deck %d   Hand %d   Kills %d/%d   Castles used %d/%d   Enchantments %d/%d%s" % [
		p, "  (YOUR TURN)" if is_active else "", ps.mana, ps.deck.size(), ps.hand.size(), ps.kills,
		int(game.rules.annihilation_goal), ps.castles_used, int(game.rules.castles_per_game),
		ps.enchantments.size(), int(game.rules.enchantment_limit),
		"   [CASTLED: Fortress in front, champions encamped]" if ps.castled else ""]
	var champs_row: PanelContainer = _zone_row(_champion_flow(ps, is_active), ps.castled)
	var fort_row: PanelContainer = _zone_row(_fortress_group(ps, p, is_active), not ps.castled)
	var active_row: PanelContainer = fort_row if ps.castled else champs_row
	var encamped_row: PanelContainer = champs_row if ps.castled else fort_row
	if top_is_encamped:
		box.add_child(encamped_row)
		box.add_child(active_row)
	else:
		box.add_child(active_row)
		box.add_child(encamped_row)


func _zone_row(content: Control, encamped: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, BOARD_CARD_H + 10.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09) if encamped else Color(0.11, 0.12, 0.18)
	sb.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	return panel


func _champion_flow(ps: PlayerState, is_active: bool) -> Control:
	# Own scroll area: a crowded row scrolls instead of pushing the hand off the bottom of the window.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	scroll.add_child(flow)
	if ps.champions.is_empty():
		var none := Label.new()
		none.text = "(no champions)"
		none.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		flow.add_child(none)
	for c in ps.champions:
		var v := CardView.create(c.card, BOARD_CARD_W, c, true, c.attacked_this_turn and is_active, ps.castled, game)
		if is_active:
			v.pressed.connect(_on_own_champion.bind(c.uid))
		flow.add_child(v)
	return scroll


## Discard pile, a gap (where the encamped champions could sit later), the Fortress card and the enchantments.
func _fortress_group(ps: PlayerState, p: int, is_active: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_discard_pile(ps, p))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var mine: bool = is_active and viewer == p and not game.finished and not _cover.visible
	var glow: bool = mine and not _fortress_options().is_empty()  # yellow border: the Fortress has something to offer
	var fv := CardView.create(fortress_card(ps), BOARD_CARD_W, null, true, glow, false, game)
	if is_active:  # clicking the enemy Fortress does nothing
		fv.pressed.connect(_on_fortress_clicked)
	row.add_child(fv)
	row.add_child(_enchantment_area(ps))
	return row


## The Fortress as a card: its definition plus the HP it has right now.
func fortress_card(ps: PlayerState) -> Dictionary:
	var f: Dictionary = ps.fortress_def.duplicate()
	f["kind"] = "fortress"
	if not f.has("name"):
		f["name"] = "Fortress"
	if not f.has("id"):
		f["id"] = "fortress"
	if not f.has("text"):
		f["text"] = ["Heal one of your champions by %d HP" % int(f.get("heal", 20)), "The player receives %d Mana at the start of their turn." % int(f.get("mana_per_turn", 1))]
	f["hp"] = int(f.get("hp", 500))
	f["hp_now"] = ps.fortress_hp
	return f


## The discard pile: the top card faded, so it is not mistaken for anything in play. Click to browse it.
func _discard_pile(ps: PlayerState, p: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BOARD_CARD_W, BOARD_CARD_H)
	if ps.discard.is_empty():
		var empty := Panel.new()
		empty.set_anchors_preset(Control.PRESET_FULL_RECT)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(empty)
	else:
		var top := CardView.create(ps.discard[ps.discard.size() - 1], BOARD_CARD_W, null, true)
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


func _enchantment_area(ps: PlayerState) -> Control:
	var panel := PanelContainer.new()
	var limit: int = int(game.rules.enchantment_limit)
	panel.custom_minimum_size = Vector2(limit * (BOARD_CARD_W + 6.0), BOARD_CARD_H)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	if ps.enchantments.is_empty():
		var l := Label.new()
		l.text = "Enchantments (0/%d)" % limit
		l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		row.add_child(l)
	for e in ps.enchantments:
		row.add_child(CardView.create(e, BOARD_CARD_W, null, true))
	return panel


func _render_hand() -> void:
	_clear(_hand_row)
	var p: int = game.active
	if viewer != p or _cover.visible:
		_hand_label.text = "Hand hidden"
		return
	var ps: PlayerState = game.players[p]
	_hand_label.text = "Your hand (%d cards) · Mana %d · Colors that attacked this turn: %s" % [ps.hand.size(), ps.mana, ", ".join(ps.colors_used) if not ps.colors_used.is_empty() else "none"]
	for i in ps.hand.size():
		var v := CardView.create(ps.hand[i], HAND_CARD_W)
		v.pressed.connect(_on_hand_card.bind(i))
		_hand_row.add_child(v)
	call_deferred("_fix_hand_scroll")


## After the hand changes: the scroll bar only shows when the hand is wider than the window (its space stays
## reserved, so the layout never jumps), and a hand that fits starts at the left edge.
func _fix_hand_scroll() -> void:
	if _hand_scroll == null or not is_instance_valid(_hand_row) or not is_inside_tree():
		return
	await get_tree().process_frame  # let the old (freed) cards leave the row before measuring it
	if not is_instance_valid(_hand_row):
		return
	var content: float = _hand_row.get_combined_minimum_size().x
	var bar: HScrollBar = _hand_scroll.get_h_scroll_bar()
	if content <= _hand_scroll.size.x:
		_hand_scroll.scroll_horizontal = 0
		bar.modulate.a = 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		_hand_scroll.scroll_horizontal = mini(_hand_scroll.scroll_horizontal, int(content - _hand_scroll.size.x))
		bar.modulate.a = 1.0
		bar.mouse_filter = Control.MOUSE_FILTER_STOP


## The mouse wheel scrolls the hand sideways (a plain wheel normally only scrolls up and down).
func _on_hand_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var step: int = int(HAND_CARD_W)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			_hand_scroll.scroll_horizontal += step
			_hand_scroll.accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			_hand_scroll.scroll_horizontal -= step
			_hand_scroll.accept_event()


func ps_hand_width() -> float:
	var n: int = game.players[game.active].hand.size() if game != null else 0
	return float(n) * (HAND_CARD_W + 6.0)


# ================================================================ actions

func _my_turn() -> bool:
	return game != null and not game.finished and viewer == game.active and not busy


func _report(res: Dictionary) -> bool:
	if res.ok:
		_status.text = ""
		_show_start_of_turn()  # an action that moved the turn on from the Castle step ran the start-of-turn triggers
	else:
		_status.text = str(res.error)
	refresh()
	call_deferred("_prompt_heal_if_needed")
	return bool(res.ok)


## The Fortress heals one champion at the start of the Summon step: ask once per turn (the button stays if skipped).
func _prompt_heal_if_needed() -> void:
	if game == null or not _my_turn() or auto_chooser.is_valid():
		return
	var ps: PlayerState = game.players[game.active]
	if ps.heal_pending and game.step == Game.Step.SUMMON and _has_damaged_champion(ps) and _heal_prompted_turn != game.turn:
		_heal_prompted_turn = game.turn
		await _on_fortress_heal()



## What clicking your own Fortress offers right now: castle / uncastle / carry on in the Castle step, and the
## Fortress heal once the start-of-turn triggers have run. (The mana is added automatically.)
func _fortress_options() -> Array:
	var opts: Array = []
	if game == null or game.finished:
		return opts
	var p: int = game.active
	var ps: PlayerState = game.players[p]
	if game.step == Game.Step.CASTLE:
		if ps.castled:
			opts.append({"label": "Uncastle: bring your champions back into play", "value": "uncastle"})
		elif Preflight.castle_problem(game, p) == "":
			opts.append({"label": "Castle: your champions are encamped, you draw 2 cards a turn", "value": "castle"})
		if not opts.is_empty():
			opts.append({"label": "Carry on without changing anything", "value": "continue"})
	elif game.step == Game.Step.SUMMON and ps.heal_pending and _has_damaged_champion(ps):
		opts.append({"label": "Fortress heal: heal one champion by %d HP" % int(ps.fortress_def.get("heal", 20)), "value": "heal"})
	return opts


func _on_fortress_clicked() -> void:
	if not _my_turn():
		return
	var opts: Array = _fortress_options()
	if opts.is_empty():
		var why: String = Preflight.castle_problem(game, game.active) if game.step == Game.Step.CASTLE else ""
		_status.text = "Nothing to do with your Fortress right now." + ("  Castling: " + why if why != "" else "")
		return
	busy = true
	var res: Variant = await choose("Your Fortress", opts, 1, 1)
	busy = false
	if res == null or (res as Array).is_empty():
		return
	match str((res as Array)[0]):
		"castle":
			if _report(game.castle(game.active)):
				_report(game.next_step(game.active))  # nothing else to decide in the Castle step
		"uncastle":
			if _report(game.uncastle(game.active)):
				_report(game.next_step(game.active))
		"continue":
			_report(game.next_step(game.active))
		"heal":
			await _on_fortress_heal()


func _on_castle() -> void:
	if _my_turn():
		_report(game.castle(game.active))


func _on_uncastle() -> void:
	if _my_turn():
		_report(game.uncastle(game.active))


func _on_next_step() -> void:
	if _my_turn():
		_report(game.next_step(game.active))


func _on_end_turn() -> void:
	if not _my_turn():
		return
	var res: Dictionary = game.end_turn(game.active)
	_report(res)
	if res.ok and not game.finished:
		_begin_turn_cover()


func _has_damaged_champion(ps: PlayerState) -> bool:
	for c in ps.champions:
		if c.damage > 0:
			return true
	return false


func _on_fortress_heal() -> void:
	if not _my_turn():
		return
	var p: int = game.active
	var damaged: Array = []
	for c in game.players[p].champions:
		if c.damage > 0:
			damaged.append(c)
	if damaged.is_empty():
		_status.text = "None of your champions is damaged, so the Fortress heal is not needed."
		return
	busy = true
	var uid: Variant = await _pick_champion("Fortress heals which champion? (%d HP)" % int(game.players[p].fortress_def.get("heal", 20)), damaged)
	busy = false
	if uid != null:
		_report(game.fortress_heal(p, int(uid)))


func _pick_champion(title: String, list: Array) -> Variant:
	var opts: Array = []
	for c in list:
		opts.append({"label": c.describe() + (" (damage %d)" % c.damage if c.damage > 0 else ""), "value": c.uid})
	var res: Variant = await choose(title, opts, 1, 1)
	if res == null or (res as Array).is_empty():
		return null
	return (res as Array)[0]


func _on_view_discard(p: int) -> void:
	if busy:
		return
	busy = true
	var opts: Array = []
	for card in game.players[p].discard:
		opts.append({"label": "%s (%s)" % [card.get("name", "?"), card.get("kind", "")], "value": 0})
	await choose("Player %d's discard pile (%d cards)" % [p, opts.size()], opts, 0, 0)
	busy = false


func _on_hand_card(i: int) -> void:
	if not _my_turn():
		return
	busy = true
	await play_hand_card(i)
	busy = false
	refresh()


## Everything that happens when a hand card is clicked: the action menu, then its choices, then the engine call.
func play_hand_card(i: int) -> Dictionary:
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
			problem = Preflight.enchantment_problem(game, p, i)
		"spell":
			problem = Preflight.spell_problem(game, p, i)
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
			res = game.summon(p, i, sc.sacrifices)
	elif kind == "enchantment":
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
		var tf: Dictionary = await flows.spell_target(p, i, effect_index)
		if tf.has("error"):
			res = {"ok": false, "error": tf.error}
		elif tf.has("cancelled"):
			return {"ok": false, "error": ""}
		else:
			res = game.play_spell(p, i, effect_index, tf.target)
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
	var pick: Variant = await choose("%s: which attack?" % c.card_name(), opts, 1, 1)
	if pick == null or (pick as Array).is_empty():
		return {"ok": false, "error": ""}
	var ai2: int = int((pick as Array)[0])
	var tf: Dictionary = await flows.attack_target(p, c, ai2)
	if tf.has("error"):
		_status.text = str(tf.error)
		return {"ok": false, "error": tf.error}
	if tf.has("cancelled"):
		return {"ok": false, "error": ""}
	var res: Dictionary = game.attack(p, uid, ai2, tf.target)
	_report(res)
	return res
