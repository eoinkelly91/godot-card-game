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
const IMG_H := 205.0       # about the shape of the art (2.0 to 2.9 wide), so pictures are not cropped
const STAT_Y := 275.0
const STAT_H := 48.0
const BODY_Y := 323.0
const BODY_H := 327.0
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
var select_color: Color = Color(1.0, 0.9, 0.25)  # yellow; red for a champion that has already attacked
var compact: bool = false
var encamped: bool = false
var game: Game = null            # lets a board card show the damage its attacks would really do now
var k: float = 1.0               # design units -> pixels
var _layer: TextLayer            # all single-line text is drawn here, on top of the boxes


static func create(p_card: Dictionary, width: float, p_live: Champion = null, p_compact: bool = false,
		p_selected: bool = false, p_encamped: bool = false, p_game: Game = null,
		p_select_color: Color = Color(1.0, 0.9, 0.25)) -> CardView:
	var v := CardView.new()
	v.game = p_game
	v.card = p_card
	v.live = p_live
	v.compact = p_compact
	v.selected = p_selected
	v.select_color = p_select_color
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
	return CardView.create(card, 340.0, live, false, false, encamped, game)


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
		"spell", "fortress":  # a Fortress card has the same background as a spell
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


## Single-line text. It is drawn by the text layer (not a Label node), centred exactly in its box and
## shrunk to fit the width, so long names and captions never spill over or sit low.
func _label(text: String, x: float, y: float, w: float, h: float, px: float, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, bold: bool = true) -> void:
	_layer.items.append({
		"text": text, "rect": Rect2(Vector2(x, y) * k, Vector2(w, h) * k), "px": maxf(5.0, px * k),
		"color": color, "align": align, "font": bold_font() if bold else ThemeDB.fallback_font,
	})


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
	var content: String = ("[b]%s[/b] %s" % [bold_part.replace("[", "[lb]"), body]) if bold_part != "" else body
	r.text = "[center]%s[/center]" % content
	add_child(r)
	call_deferred("_center_vertically", r)


## Centres a text box's contents vertically once its layout is known.
func _center_vertically(r: RichTextLabel) -> void:
	if not is_instance_valid(r) or not r.is_inside_tree():
		return
	var full: float = r.size.y
	var ch: float = float(r.get_content_height())
	if ch > 0.0 and ch < full:
		r.position.y += (full - ch) * 0.5
		r.size.y = ch + 2.0


# ---------------------------------------------------------------- the card

func _build() -> void:
	_layer = TextLayer.new()
	_layer.size = size
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base: Color = _base_color()
	var on_base: Color = _on_base()
	var is_champion: bool = _kind() == "champion"
	_box(0, 0, DW, DH, base, 2.0)

	# Top bar: cost / B and the name (a Fortress has its name on the left and its HP on the right)
	var name_text: String = str(card.get("name", "?")).to_upper()
	if _kind() == "fortress":
		var hp_w: float = 150.0
		var max_hp: int = int(card.get("hp", 500))
		var hp_text: String = "%d/%d" % [int(card.get("hp_now", max_hp)), max_hp]
		_label(name_text, 6.0, 0, DW - hp_w - 12.0, TOP_H, clampf(46.0 - maxf(0.0, name_text.length() - 12.0) * 2.4, 22.0, 40.0), on_base)
		_label(hp_text, DW - hp_w, 0, hp_w, TOP_H, 34, on_base)
		var hp_line := ColorRect.new()
		hp_line.color = DARK
		hp_line.position = Vector2(DW - hp_w - 1.0, 4.0) * k
		hp_line.size = Vector2(2.0 * k, (TOP_H - 8.0) * k)
		hp_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hp_line)
	else:
		var num_text: String = _top_left_text()
		_label(num_text, 0, 0, NUM_W, TOP_H, 38 if num_text.length() < 3 else 28, on_base)
		var line := ColorRect.new()
		line.color = DARK
		line.position = Vector2(NUM_W - 1.0, 4.0) * k
		line.size = Vector2(2.0 * k, (TOP_H - 8.0) * k)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
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
	add_child(_layer)  # last, so the text sits on top of every box
	if encamped and _kind() == "fortress":  # castled: an orange border around the Fortress
		var cb := Panel.new()
		cb.size = size
		cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cbs := StyleBoxFlat.new()
		cbs.bg_color = Color(0, 0, 0, 0)
		cbs.set_border_width_all(maxi(3, int(6.0 * k * 2.0)))
		cbs.border_color = Color(1.0, 0.5, 0.05)
		cb.add_theme_stylebox_override("panel", cbs)
		add_child(cb)
	if _kind() != "fortress" and _asleep():  # asleep (encamped, just summoned, chained): faded, with Zzz
		modulate = Color(1, 1, 1, 0.5)
		_zzz()
	if selected:
		var sel := Panel.new()
		var inset: float = 7.0 * k * 2.0 if (encamped and _kind() == "fortress") else 0.0
		sel.position = Vector2(inset, inset)
		sel.size = size - Vector2(inset, inset) * 2.0
		sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(maxi(3, int(5.0 * k * 2.0)))
		sb.border_color = select_color
		sel.add_theme_stylebox_override("panel", sb)
		add_child(sel)


## "Zzz" over the art of an encamped (sleeping) champion.
func _zzz() -> void:
	var z := Label.new()
	z.text = "Zzz"
	z.position = Vector2(DW * 0.52, IMG_Y + 6.0) * k
	z.size = Vector2(DW * 0.46, 120.0) * k
	z.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	z.add_theme_font_size_override("font_size", maxi(10, int(80.0 * k)))
	z.add_theme_color_override("font_color", Color(1, 1, 1))
	z.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.3))
	z.add_theme_constant_override("outline_size", maxi(2, int(8.0 * k)))
	z.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(z)


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
		var back := ColorRect.new()  # shows only if a picture is narrower than the box
		back.color = Color(0.1, 0.1, 0.12)
		back.size = holder.size
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(back)
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # must be set first, or the rect grows to the picture's pixel size
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED  # the whole picture is visible
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.texture = load(path)
		holder.add_child(tr)
		tr.size = holder.size  # (expand_mode was set first, so this is not raised to the picture's pixel size)
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


## True when this champion cannot pay for the attack right now (not enough mana, or HP below the threshold).
func _attack_unmet(atk: Dictionary) -> bool:
	if live == null or game == null or live.owner >= game.players.size():
		return false
	return Preflight._attack_cost_problem(game, game.players[live.owner], live, atk) != ""


## A champion that cannot act right now sleeps: encamped, summoned this turn, or chained.
func _asleep() -> bool:
	if live == null:
		return false
	if encamped:
		return true
	if game != null and live.summoned_turn == game.turn:
		return true
	for st in live.statuses:
		if str(st.kind) == "no_attack":
			return true
	return false


func _draw_stats_row() -> void:
	var color_name: String = str(card.get("color", ""))
	var white := Color(1, 1, 1)
	_box(0, STAT_Y, 365, STAT_H, white)
	_box(365, STAT_Y, 125, STAT_H, white)
	var big: float = 1.2 if compact else 1.0  # board cards are small, so their stats are drawn larger
	# Class and type together ("Legendary Creature"), in the champion's colour instead of a colour word
	var class_type: String = ("%s %s" % [str(card.get("class", "")).capitalize(), str(card.get("type", ""))]).strip_edges()
	_label(class_type, 0, STAT_Y, 365, STAT_H, (26 if class_type.length() < 18 else 20) * big, COLOR_WORD.get(color_name, DARK))
	var hp_text: String = "%dHP" % int(card.get("hp", 0))
	if live != null:
		hp_text = "%d/%dHP" % [live.current_hp(), live.max_hp()]
	# shrink the HP text so "100/100HP" always fits its cell
	var hp_px: float = minf(24.0 * big, (125.0 - 12.0) / (float(hp_text.length()) * 0.74))
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
		_label("ABILITY", 0, y + h * 0.06, DW, h * 0.55, 30, DARK)
		_label("(hover for info)", 0, y + h * 0.58, DW, h * 0.36, 20, DARK, HORIZONTAL_ALIGNMENT_CENTER, false)
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
	var unmet: bool = _attack_unmet(atk)  # red until the condition (mana or HP) is met again
	var req_color: Color = Color(0.85, 0.1, 0.1) if unmet else DARK
	if number != "":
		_label(number, 0, y + h * 0.5 - 34.0, SIDE_W, 38.0, 32, req_color)
		_label(caption, 0, y + h * 0.5 + 4.0, SIDE_W, 24.0, 12, req_color)
	# damage (right): a fixed number, "3X10" for coin attacks, or a dash
	var dmg: int = int(atk.get("damage", 0))
	var dmg_color: Color = req_color
	if live != null and game != null and not atk.has("coins") and live.owner < game.players.size():
		var now: int = DamageRules.preview(game, live, atk)  # what the attack would do right now
		if now != dmg and now > 0:
			dmg = now
			dmg_color = Color(0.0, 0.45, 0.1)
	var dmg_text: String = str(dmg) if dmg > 0 else "-"
	if atk.has("coins"):
		dmg_text = "%dX%d" % [int(atk.coins.count), int(atk.coins.per_heads_damage)]
	_label(dmg_text, DW - SIDE_W, y, SIDE_W, h, 30 if dmg_text.length() < 4 else 21, dmg_color)
	var on_base: Color = _on_base()
	var name_text: String = str(atk.get("name", "")).to_upper()
	if compact:
		if _attack_description(atk) != "":  # an extra effect: say so, the details are in the hover card
			_label(name_text, SIDE_W, y + h * 0.06, DW - SIDE_W * 2.0, h * 0.55, 28, on_base)
			_label("(hover for info)", SIDE_W, y + h * 0.58, DW - SIDE_W * 2.0, h * 0.36, 20, on_base, HORIZONTAL_ALIGNMENT_CENTER, false)
		else:
			_label(name_text, SIDE_W, y, DW - SIDE_W * 2.0, h, 28, on_base)
	else:
		var desc: String = _attack_description(atk)
		if desc == "":  # just a name: centred in the box
			_label(name_text, SIDE_W, y, DW - SIDE_W * 2.0, h, 30, on_base)
		else:
			_rich(name_text + ":", desc, SIDE_W, y, DW - SIDE_W * 2.0, h, on_base)


## "70 + this champion does 20 damage to itself." -> "this champion does 20 damage to itself."
func _attack_description(atk: Dictionary) -> String:
	var text: String = str(atk.get("text", ""))
	var re := RegEx.new()
	re.compile("^\\s*\\d+\\s*\\+?\\s*")
	return re.sub(text, "").strip_edges()


func _draw_description_boxes(texts: Array, with_labels: bool) -> void:
	var on_base: Color = _on_base()
	var top: float = IMG_Y + IMG_H
	var n: int = maxi(1, texts.size())
	var strip: float = 30.0 if with_labels and n > 1 and _kind() != "fortress" else 0.0   # the OR divider between two effects (a Fortress has a single ability)
	var h: float = (DH - top - strip * float(n - 1)) / float(n)
	var y: float = top
	for i in n:
		_box(0, y, DW, h, _base_color())
		var text: String = str(texts[i]) if i < texts.size() else ""
		var label: String = "Effect %d:" % (i + 1) if with_labels and n > 1 else ("Effect:" if with_labels else "")
		if _kind() == "fortress":
			label = "Ability:"
		if compact and _kind() == "fortress":  # the ability text is in the hover card
			_label("ABILITY", 0, y + h * 0.1, DW, h * 0.5, 30, on_base)
			_label("(hover for info)", 0, y + h * 0.58, DW, h * 0.3, 20, on_base, HORIZONTAL_ALIGNMENT_CENTER, false)
		elif compact:
			_label(("EFFECT %d" % (i + 1)) if with_labels and n > 1 else ("SPELL" if with_labels else "ENCHANTMENT"), 0, y, DW, h, 30, on_base)
		else:
			_rich(label, text, 0, y, DW, h, on_base)
		y += h
		if i < n - 1 and strip > 0.0:  # you choose ONE effect
			_box(0, y, DW, strip, Color(0.96, 0.96, 0.96))
			_label("OR", 0, y, DW, strip, 20, DARK)
			y += strip


func _draw_live_tags() -> void:
	var tags: Array = []
	if encamped:
		tags.append("ENCAMPED")
	elif game != null and live.summoned_turn == game.turn:
		tags.append("SUMMONED: CANNOT ATTACK THIS TURN")
	for st in live.statuses:
		match str(st.kind):
			"poison":
				var ptag: String = "POISONED: %d DMG PER TURN" % int(st.get("amount", 10))
				if not tags.has(ptag):
					tags.append(ptag)
			"protected":
				tags.append("PROTECTED FROM ALL DAMAGE")
			"no_attack":
				tags.append("CHAINED: CANNOT ATTACK")
			"duel":
				tags.append("DUEL: MUST ATTACK THE DUELIST")
			"next_attack_bonus":
				tags.append("NEXT ATTACK +%d DMG" % int(st.get("amount", 0)))
			"stored_bonus":
				tags.append("GNAW +%d DMG" % int(st.get("amount", 0)))
	if tags.is_empty():
		return
	var strip := ColorRect.new()
	strip.color = Color(0, 0, 0, 0.7)
	strip.position = Vector2(0, IMG_Y + IMG_H - 36.0) * k
	strip.size = Vector2(DW, 36.0) * k
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	_label("  ·  ".join(tags), 6, IMG_Y + IMG_H - 36.0, DW - 12.0, 36.0, 22, Color(1, 0.9, 0.4), HORIZONTAL_ALIGNMENT_LEFT)


## Draws the card's single-line texts. Each item: text, rect (pixels), px (font size), color, align, font.
class TextLayer extends Control:
	var items: Array = []

	func _draw() -> void:
		for it in items:
			var font: Font = it.font
			var rect: Rect2 = it.rect
			var fs: int = int(it.px)
			var text: String = it.text
			while fs > 5 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > rect.size.x - 3.0:
				fs -= 1  # shrink long text until it fits the box
			var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var asc: float = font.get_ascent(fs)
			var desc: float = font.get_descent(fs)
			var baseline: float = rect.position.y + (rect.size.y - (asc + desc)) * 0.5 + asc
			var x: float = rect.position.x + (rect.size.x - width) * 0.5
			if int(it.align) == HORIZONTAL_ALIGNMENT_LEFT:
				x = rect.position.x + 3.0
			draw_string(font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, it.color)
