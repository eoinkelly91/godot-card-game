## card_item_list.gd - An ItemList whose rows can show a card as their hover tip (the discard pile viewer):
## give a row the tooltip "card:N" and put the card in cards[N].
class_name CardItemList
extends ItemList

var cards: Dictionary = {}


func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.begins_with("card:"):
		var idx: int = int(for_text.substr(5))
		if cards.has(idx):
			return CardView.create(cards[idx], 300.0, null, false)
	return null
