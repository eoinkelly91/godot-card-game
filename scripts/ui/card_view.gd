## card_view.gd - Draws one card like the layout mock-up: a coloured top bar (cost/"B" + name), the image,
## a white Color / Type / HP row, then the ability (yellow) and attack boxes for a champion, or the effect
## boxes of a spell (grey) or the description of an enchantment (green).
## Everything is positioned from a 490 x 650 design grid and scaled to the width asked for.
## "compact" cards (the board) show only names and numbers; hovering shows the full-size card.
## Art is looked up as res://art/cards/<card id>.jpg (or .png); without it a coloured placeholder is drawn.
class_name CardView
extends Control

signal pressed

const DW := 490.0
const DH := 650.0
const TOP_H := 70.0
const NUM_W := 62.0
const IMG_Y := 70.0
const IMG_H := 163.0
const STAT_Y := 233.0
const STAT_H := 44.0
const BODY_Y := 277.0
const BODY_H := 373.0
const MAX_BOX_H := 187.0
const SIDE_W := 62.0

const CHAMPION_COLORS := {
	"Red": Color(0.72, 0.16, 0.16), "Blue": Color(0.16, 0.34, 0.74),
	"White": Color(0.84, 0.84, 0.8), "Purple": Color(0.46, 0.22, 0.64),
}
const COLOR_WORD := {  # the "Color" word in the stats row, readable on white
	"Red": Color(0.8, 0.12, 0.12), "Blue": Color(0.12, 0.3, 0.85),
	"White": Color(0.35, 0.35, 0.35), "Purple": Color(0.52, 0.18, 0.74),
}
const ENCHANTMENT_COLOR := Color(0.18, 0.5, 0.24)
const SPELL_COLOR := Color(0.5, 0.5, 0.54)
const ABILITY_COLOR := Color(0.98, 0.85, 0.2)
const DARK := Color(0.08, 0.08, 0.1)

static var _bold: FontVariation

var card: Dictionary = {}
var live: Champion = null        # board version: current HP and statuses
var selected: bool = false
var compact: bool = false
var encamped: bool = false
var k: float = 1.0               # design units -> pixels


static func create(p_card: Dictionary, width: float, p_live: Champion = null, p_compact: bool = false,
		p_selected: bool = false, p_encamped: bool = false) -> CardView:
	var v := CardView.new()
	v.card = p_card
	v.live = p_live
	v.compact = p_compact
	v.selected = p_selected
	v.encamped = p_encamped
	v.k = width / DW
	v.custom_minimum_size = Vector2(width, DH * v.k)
	v.size = v.custom_minimum_size
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	v.tooltip_text = str(p_card.get("name", "Card"))
	v._build()
	return v


static func bold_font() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.9
	return _bold


static func image_path(card_id: String) -> String:
	for ext in ["jpg", "png", "jpeg"]:
		var path: String = "res://art/cards/%s.%s" % [card_id, ext]
		if ResourceLoader.exists(path):
			return path
	return ""


## The full-size card shown when hovering.
func _make_custom_tooltip(_for_text: String) -> Object:
	return CardView.create(card, 340.0, live, false, false, encamped)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()


# ---------------------------------------------------------------- colours

func _kind() -> String:
	return str(card.get("kind", "champion"))


func _base_color() -> Color:
	match _kind():
		"enchantment":
			return ENCHANTMENT_COLOR
		"spell":
			return SPELL_COLOR
	return CHAMPION_COLORS.get(str(card.get("color", "")), SPELL_COLOR)


## Text on the card colour: dark on the light White champions, white on the rest.
func _on_base() -> Color:
	return DARK if _base_color().get_luminance() > 0.6 else Color(0.97, 0.97, 0.97)


# ---------------------------------------------------------------- building blocks

func _box(x: float, y: float, w: float, h: float, fill: Color, border: float = 1.0) -> Panel:
	var p := Panel.new()
	p.position = Vector2(x, y) * k
	p.size = Vector2(w, h) * k
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_border_width_all(maxi(1, int(border * k * 2.0)))
	sb.border_color = DARK
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p


func _label(text: String, x: float, y: float, w: float, h: float, px: float, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, bold: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(x, y) * k
	l.size = Vector2(w, h) * k
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", maxi(5, int(px * k)))
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", bold_font())
	add_child(l)
	return l


## Largest font size (design units) that fits the text in the box, estimated from the character count.
func _fit(text: String, w: float, h: float, max_px: float, min_px: float) -> float:
	var px: float = max_px
	while px > min_px:
		var per_line: float = maxf(1.0, floor((w - 12.0) / (px * 0.52)))
		var lines: float = ceil(float(text.length()) / per_line) + 0.3
		if lines * px * 1.22 <= h - 8.0:
			return px
		px -= 1.0
	return min_px


func _rich(bold_part: String, text: String, x: float, y: float, w: float, h: float, color: Color) -> void:
	var full: String = (bold_part + " " + text).strip_edges()
	var px: float = _fit(full, w, h, 24.0, 12.0)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.fit_content = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.clip_contents = true
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = Vector2(x + 6.0, y + 3.0) * k
	r.size = Vector2(w - 12.0, h - 6.0) * k
	r.add_theme_font_override("bold_font", bold_font())
	r.add_theme_font_size_override("normal_font_size", maxi(5, int(px * k)))
	r.add_theme_font_size_override("bold_font_size", maxi(5, int(px * k)))
	r.add_theme_color_override("default_color", color)
	var body: String = text.replace("[", "[lb]")
	r.text = ("[b]%s[/b] %s" % [bold_part.replace("[", "[lb]"), body]) if bold_part != "" else body
	add_child(r)


# ---------------------------------------------------------------- the card

func _build() -> void:
	var base: Color = _base_color()
	var on_base: Color = _on_base()
	var is_champion: bool = _kind() == "champion"
	_box(0, 0, DW, DH, base, 2.0)

	# Top bar: cost / B and the name
	var num_text: String = _top_left_text()
	_label(num_text, 0, 0, NUM_W, TOP_H, 38 if num_text.length() < 3 else 28, on_base)
	var line := ColorRect.new()
	line.color = DARK
	line.position = Vector2(NUM_W - 1.0, 4.0) * k
	line.size = Vector2(2.0 * k, (TOP_H - 8.0) * k)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	var name_text: String = str(card.get("name", "?")).to_upper()
	_label(name_text, NUM_W + 6.0, 0, DW - NUM_W - 12.0, TOP_H, clampf(46.0 - maxf(0.0, name_text.length() - 12.0) * 2.4, 22.0, 40.0), on_base)

	_draw_image(IMG_Y, IMG_H)

	if is_champion:
		_draw_stats_row()
		_draw_champion_body()
	elif _kind() == "enchantment":
		_draw_description_boxes([str(" ".join(card.get("text", [])))], false)
	else:
		_draw_description_boxes(card.get("text", []), true)

	if live != null:
		_draw_live_tags()
	if selected:
		var sel := Panel.new()
		sel.size = size
		sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(maxi(3, int(5.0 * k * 2.0)))
		sb.border_color = Color(1.0, 0.9, 0.25)
		sel.add_theme_stylebox_override("panel", sb)
		add_child(sel)


func _top_left_text() -> String:
	if _kind() != "champion":
		return str(int(card.get("cost", 0)))
	var req: Dictionary = card.get("summon", {})
	if int(req.get("sacrifice", 0)) > 0:
		return str(int(req.sacrifice))  # a symbol for "sacrifices" will be added later
	if int(req.get("mana", 0)) > 0:
		return str(int(req.mana))        # and one for "mana"
	return "B"


func _draw_image(y: float, h: float) -> void:
	var holder := Control.new()
	holder.position = Vector2(0, y) * k
	holder.size = Vector2(DW, h) * k
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var path: String = image_path(str(card.get("id", "")))
	if path != "":
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.size = holder.size
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	else:  # placeholder: a darker tint of the card colour with the card kind in faint letters
		var bg := ColorRect.new()
		bg.color = _base_color().darkened(0.45)
		bg.size = holder.size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(bg)
		var l := Label.new()
		l.text = ("%s IMAGE" % _kind()).to_upper()
		l.size = holder.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", maxi(5, int(26.0 * k)))
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(l)
	var frame := Panel.new()  # thin outline over the image
	frame.size = holder.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(maxi(1, int(2.0 * k)))
	sb.border_color = DARK
	frame.add_theme_stylebox_override("panel", sb)
	holder.add_child(frame)


func _draw_stats_row() -> void:
	var color_name: String = str(card.get("color", ""))
	var white := Color(1, 1, 1)
	_box(0, STAT_Y, 135, STAT_H, white)
	_box(135, STAT_Y, 230, STAT_H, white)
	_box(365, STAT_Y, 125, STAT_H, white)
	var big: float = 1.35 if compact else 1.0  # board cards are small, so their stats are drawn larger
	_label(color_name, 0, STAT_Y, 135, STAT_H, 24 * big, COLOR_WORD.get(color_name, DARK))
	var type_text: String = str(card.get("type", ""))
	_label(type_text, 135, STAT_Y, 230, STAT_H, (24 if type_text.length() < 18 else 17) * big, DARK)
	var hp_text: String = "%dHP" % int(card.get("hp", 0))
	if live != null:
		hp_text = "%d/%dHP" % [live.current_hp(), live.max_hp()]
	# shrink the HP text so "100/100HP" always fits its cell
	var hp_px: float = minf(24.0 * big, (125.0 - 10.0) / (float(hp_text.length()) * 0.6))
	_label(hp_text, 365, STAT_Y, 125, STAT_H, hp_px, DARK)


func _draw_champion_body() -> void:
	var items: Array = []
	if card.has("ability"):
		items.append({"kind": "ability", "text": str(card.ability.get("text", ""))})
	for atk in card.get("attacks", []):
		items.append({"kind": "attack", "atk": atk})
	if items.is_empty():
		return
	var box_h: float = minf(BODY_H / float(items.size()), MAX_BOX_H)
	var y: float = BODY_Y
	for it in items:
		if it.kind == "ability":
			_draw_ability_box(y, box_h, str(it.text))
		else:
			_draw_attack_box(y, box_h, it.atk)
		y += box_h


func _draw_ability_box(y: float, h: float, text: String) -> void:
	_box(0, y, DW, h, ABILITY_COLOR)
	if compact:
		_label("ABILITY", 0, y, DW, h, 30, DARK)
	else:
		_rich("Ability:", text, 0, y, DW, h, DARK)


func _draw_attack_box(y: float, h: float, atk: Dictionary) -> void:
	var white := Color(1, 1, 1)
	var base: Color = _base_color()
	_box(0, y, SIDE_W, h, white)
	_box(SIDE_W, y, DW - SIDE_W * 2.0, h, base)
	_box(DW - SIDE_W, y, SIDE_W, h, white)
	# requirement (left): HP threshold or mana
	var number: String = ""
	var caption: String = ""
	if atk.has("mana_cost"):
		number = str(int(atk.mana_cost))
		caption = "MANA"
	elif atk.has("requires"):
		number = str(int(atk.requires.get("self_hp_at_least", 0)))
		caption = "HP"
	if number != "":
		_label(number, 0, y + h * 0.5 - 30.0, SIDE_W, 36.0, 30, DARK)
		_label(caption, 0, y + h * 0.5 + 4.0, SIDE_W, 20.0, 12, DARK)
	# damage (right)
	var dmg: int = int(atk.get("damage", 0))
	_label(str(dmg) if dmg > 0 else "-", DW - SIDE_W, y, SIDE_W, h, 30, DARK)
	var on_base: Color = _on_base()
	var name_text: String = str(atk.get("name", "")).to_upper()
	if compact:
		_label(name_text, SIDE_W, y, DW - SIDE_W * 2.0, h, 28, on_base)
	else:
		var desc: String = _attack_description(atk)
		_rich(name_text + (":" if desc != "" else ""), desc, SIDE_W, y, DW - SIDE_W * 2.0, h, on_base)


## "70 + this champion does 20 damage to itself." -> "this champion does 20 damage to itself."
func _attack_description(atk: Dictionary) -> String:
	var text: String = str(atk.get("text", ""))
	var re := RegEx.new()
	re.compile("^\\s*\\d+\\s*\\+?\\s*")
	return re.sub(text, "").strip_edges()


func _draw_description_boxes(texts: Array, with_labels: bool) -> void:
	var on_base: Color = _on_base()
	var y: float = STAT_Y
	var total: float = DH - STAT_Y
	var n: int = maxi(1, texts.size())
	var h: float = total / float(n)
	for i in n:
		_box(0, y, DW, h, _base_color())
		var text: String = str(texts[i]) if i < texts.size() else ""
		var label: String = "Effect %d:" % (i + 1) if with_labels and n > 1 else ("Effect:" if with_labels else "")
		if compact:
			_label(("EFFECT %d" % (i + 1)) if with_labels and n > 1 else ("SPELL" if with_labels else "ENCHANTMENT"), 0, y, DW, h, 30, on_base)
		else:
			var pad_top: float = 16.0 if i > 0 and with_labels else 0.0  # keep clear of the OR badge
			var pad_bottom: float = 16.0 if i < n - 1 and with_labels else 0.0
			_rich(label, text, 0, y + pad_top, DW, h - pad_top - pad_bottom, on_base)
		y += h
	if with_labels and n > 1:  # you choose ONE effect: an OR badge on each dividing line (drawn last, on top)
		y = STAT_Y
		for i in n - 1:
			y += h
			var badge := _box(DW * 0.5 - 28.0, y - 15.0, 56.0, 30.0, Color(0.97, 0.97, 0.97))
			_label("OR", DW * 0.5 - 28.0, y - 15.0, 56.0, 30.0, 20, DARK)


func _draw_live_tags() -> void:
	var tags: Array = []
	if encamped:
		tags.append("ENCAMPED")
	for st in live.statuses:
		match str(st.kind):
			"poison":
				tags.append("POISONED")
			"protected":
				tags.append("PROTECTED")
			"no_attack":
				tags.append("CHAINED")
			"duel":
				tags.append("DUEL")
			"next_attack_bonus":
				tags.append("+%d NEXT" % int(st.get("amount", 0)))
			"stored_bonus":
				tags.append("+%d GNAW" % int(st.get("amount", 0)))
	if live.damage > 0:
		tags.append("DMG %d" % live.damage)
	if tags.is_empty():
		return
	var strip := ColorRect.new()
	strip.color = Color(0, 0, 0, 0.7)
	strip.position = Vector2(0, IMG_Y + IMG_H - 36.0) * k
	strip.size = Vector2(DW, 36.0) * k
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	_label("  ".join(tags), 6, IMG_Y + IMG_H - 36.0, DW - 12.0, 36.0, 22, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_LEFT)
