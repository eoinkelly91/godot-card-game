## player_state.gd - Everything that belongs to one player: Fortress HP, banked mana, deck, hand, discard
## pile, champions, enchantments, castling state, duration effects on them, and per-turn flags.
## Champions all live in `champions`; `castled` says whether they are in the encampment area (castled) or
## the active play area (not castled), because castling always moves every champion at once.
## Pure data; the rules that change it live in turn.gd, summon.gd, attack.gd, damage.gd and statuses.gd.
class_name PlayerState
extends RefCounted

var index: int
var fortress_def: Dictionary = {}
var fortress_hp: int = 0
var mana: int = 0
var deck: Array = []          # card dictionaries; the top of the deck is the END of the array
var hand: Array = []
var discard: Array = []
var champions: Array[Champion] = []
var enchantments: Array = []  # card dictionaries
var kills: int = 0            # Annihilation points earned by this player
var mulligans: int = 0
var turns_taken: int = 0      # this player's own turns so far (1 = their first turn)
var castled: bool = false     # true: Fortress is in the active play area, champions are encamped
var castles_used: int = 0     # castling is limited per game
var castled_turns: int = 0    # own turns spent castled so far, counting the turn they castled on
var buffs: Array = []         # duration effects on this player, e.g. {"kind": "attack", "amount": 10, "turns_left": 1}
var summoned_this_turn: bool = false
var colors_used: Array = []   # colors that have attacked this turn
var extra_attacks: Array = []  # Volcanic Horn tokens: uid of the champion that granted each extra attack
var summon_discount: int = 0   # Mumified: sacrifices or mana taken off this turn's summon


func _init(p_index: int) -> void:
	index = p_index


func reset_for_turn() -> void:
	summoned_this_turn = false
	colors_used.clear()
	summon_discount = 0
	extra_attacks.clear()
	for c in champions:
		c.attacked_this_turn = false


func is_first_turn() -> bool:
	return turns_taken == 1


## Champions in the active play area (they can attack and be targeted).
func active_champions() -> Array[Champion]:
	var none: Array[Champion] = []
	return none if castled else champions


## Champions in the encampment area (they cannot attack and cannot be targeted by the opponent).
func encamped_champions() -> Array[Champion]:
	return champions if castled else ([] as Array[Champion])
