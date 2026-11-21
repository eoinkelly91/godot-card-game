## champion.gd - A champion on the board.
## Holds the card data plus live state (owner, damage taken). Damage is stored in HP points and is always
## a multiple of 10, so 1 damage counter = 10. Pure data and small helpers; no rules logic lives here.
class_name Champion
extends RefCounted

var uid: int
var card: Dictionary
var owner: int
var damage: int = 0
var attached: Array = []  # spell cards attached to this champion (Warrior Idol, Fusion, Power Source): card dictionaries
var hp_effects: Array = []   # what changed hp_mod, as {"text", "delta"} (set by HpRules; for the hover panel and the HP colour)
var hp_mod: int = 0        # HP changes from Super Shrink, Fusion, Power Source (set by HpRules.recalc)
var hp_override: int = -1  # Gaia: the HP it is currently copying (-1 = the printed HP)
var slot: int = -1          # fixed position on the board (0-5); a destroyed champion leaves its slot empty
## A champion summoned through sacrifice (or mana) is Encamped from the moment it arrives until the start of its
## owner's next turn: it cannot attack and cannot be attacked (the turn counter goes up by one for every player's
## turn, so that is through turn summoned_turn + 1). A castle encamps all of its owner's champions (see PlayerState).
var encamp_until: int = -1
var encamped_flag: bool = false  # kept up to date by Game.refresh_encamp(): true while this champion is Encamped for any reason


func is_encamped(current_turn: int) -> bool:
	return encamp_until >= current_turn


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


func base_hp() -> int:
	return hp_override if hp_override >= 0 else int(card.get("hp", 0))


func max_hp() -> int:
	return maxi(0, base_hp() + hp_mod)


func current_hp() -> int:
	return max_hp() - damage


func counters() -> int:
	return int(damage / 10.0)


## True when the card has an ability AND it is working: the abilities of Encamped champions are inactive.
func has_ability() -> bool:
	return not encamped_flag and typeof(card.get("ability")) == TYPE_DICTIONARY


## The card has an ability printed on it (whether or not it is currently active).
func has_printed_ability() -> bool:
	return typeof(card.get("ability")) == TYPE_DICTIONARY


func is_destroyed() -> bool:
	return damage >= max_hp()


func describe() -> String:
	return "%s#%d [%s %s %s] %d/%d HP" % [card_name(), uid, color(), champion_class(), champion_type(), current_hp(), max_hp()]
