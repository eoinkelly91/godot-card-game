## champion.gd - A champion on the board.
## Holds the card data plus live state (owner, damage taken). Damage is stored in HP points and is always
## a multiple of 10, so 1 damage counter = 10. Pure data and small helpers; no rules logic lives here.
class_name Champion
extends RefCounted

var uid: int
var card: Dictionary
var owner: int
var damage: int = 0
var attached: Array = []  # cards attached to this champion (future decision; nothing uses it yet)
var summoned_turn: int = -1  # the game turn this champion was summoned on (it cannot attack that turn)
var attacked_this_turn: bool = false  # Grimn: did this champion attack during its owner's turn
var statuses: Array = []  # ongoing effects, e.g. {"kind": "poison", "amount": 10, "turns_left": 3, "source": 0}


func _init(p_uid: int, p_card: Dictionary, p_owner: int) -> void:
	uid = p_uid
	card = p_card
	owner = p_owner


func card_name() -> String:
	return str(card.get("name", "?"))


func color() -> String:
	return str(card.get("color", ""))


func champion_type() -> String:
	return str(card.get("type", ""))


## "basic" or "elite" (see CardDB.expected_class for the rule).
func champion_class() -> String:
	return str(card.get("class", ""))


func max_hp() -> int:
	return int(card.get("hp", 0))


func current_hp() -> int:
	return max_hp() - damage


func counters() -> int:
	return int(damage / 10.0)


func has_ability() -> bool:
	return typeof(card.get("ability")) == TYPE_DICTIONARY


func is_destroyed() -> bool:
	return damage >= max_hp()


func describe() -> String:
	return "%s#%d [%s %s %s] %d/%d HP" % [card_name(), uid, color(), champion_class(), champion_type(), current_hp(), max_hp()]
