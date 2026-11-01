## card_db.gd - Loads card data from data/cards/*.json (one file per color, plus spells and enchantments)
## and decks from data/decks.json. Also checks cards and decks for mistakes: duplicate ids, a champion's
## "class" not matching the basic/elite rule, an attack that combines a mana cost with an HP threshold,
## and a champion with more than 2 attacks or more than one ability (three slots: up to two attacks and
## one ability). There is no limit on copies of a card in a deck for now. JSON numbers arrive as floats, so engine code casts with int().
class_name CardDB
extends RefCounted

const CARD_DIR := "res://data/cards/"
const CARD_FILES := ["red", "blue", "white", "purple", "spells", "enchantments"]


static func load_cards(dir: String = CARD_DIR) -> Dictionary:
	var cards: Dictionary = {}
	for file_name in CARD_FILES:
		var path: String = "%s%s.json" % [dir, file_name]
		var parsed: Variant = _read_json(path)
		if typeof(parsed) != TYPE_ARRAY:
			push_error("Card file must be a JSON array: " + path)
			continue
		for entry in parsed:
			var card: Dictionary = entry
			var id: String = str(card.get("id", ""))
			if id == "":
				push_error("Card without an id in " + path)
				continue
			if cards.has(id):
				push_error("Duplicate card id '%s' in %s" % [id, path])
				continue
			if str(card.get("kind", "")) == "champion" and str(card.get("class", "")) != expected_class(card):
				push_warning("%s: class is '%s' but the rules say '%s'" % [id, card.get("class", ""), expected_class(card)])
			if str(card.get("kind", "")) == "champion":
				if card.get("attacks", []).size() > 2:
					push_error("%s: more than 2 attacks (three slots: up to 2 attacks and 1 ability)" % id)
				for atk in card.get("attacks", []):
					if int(atk.get("mana_cost", 0)) > 0 and atk.has("requires"):
						push_error("%s: attack '%s' combines a mana cost with an HP threshold" % [id, atk.get("name", "?")])
			cards[id] = card
	return cards


## Basic = no sacrifice and no mana cost to play. Elite = one or more sacrifices, a mana cost, or both.
static func expected_class(card: Dictionary) -> String:
	var req: Dictionary = card.get("summon", {})
	if int(req.get("sacrifice", 0)) > 0 or int(req.get("mana", 0)) > 0:
		return "elite"
	return "basic"


static func load_decks(path: String = "res://data/decks.json") -> Dictionary:
	var parsed: Variant = _read_json(path)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("decks file must be a JSON object: " + path)
		return {}
	return parsed


## Expands {"card_id": count, ...} into a flat Array of card dictionaries.
static func build_deck(cards: Dictionary, spec: Dictionary) -> Array:
	var deck: Array = []
	for id in spec:
		if not cards.has(id):
			push_error("Unknown card id in deck: " + str(id))
			continue
		for i in int(spec[id]):
			deck.append(cards[id])
	return deck


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open " + path)
		return null
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	if err != OK:
		push_error("JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
