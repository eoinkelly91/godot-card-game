## spell_effects.gd - The spell effects added with the real spell list: cleanse, moving damage counters,
## mana drain, removing enchantments, Fortress repair, "cannot attack", card draw/discard tricks, mana from
## discards and the sacrifice discount. attack.gd's play_spell() calls validate() BEFORE the card is
## consumed and apply() afterwards. Targets are plain dictionaries (see each op).
## Discards that a player will choose in the UI are random when no choice is given ("random for now").
class_name SpellEffects
extends RefCounted


static func validate(g: Game, p: int, hand_index: int, effect: Dictionary, target: Dictionary) -> String:
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	match str(effect.get("op", "")):
		"cleanse":
			if g._champion_of(me, int(target.get("champion", -1))) == null:
				return "Pick one of your own champions."
		"move_counters":  # target {"moves": [{"from": own uid, "to": enemy uid, "counters": n}]}
			var moves: Array = target.get("moves", [])
			if moves.is_empty():
				return "Choose where the damage counters go."
			if foe.castled:
				return "Encamped champions cannot be targeted."
			var total: int = 0
			var taken: Dictionary = {}
			for m in moves:
				var from_c: Champion = g._champion_of(me, int(m.get("from", -1)))
				var to_c: Champion = g._champion_of(foe, int(m.get("to", -1)))
				var n: int = int(m.get("counters", 0))
				if from_c == null or to_c == null or n < 1:
					return "Bad counter move."
				taken[from_c.uid] = int(taken.get(from_c.uid, 0)) + n
				if int(taken[from_c.uid]) * 10 > from_c.damage:
					return "%s does not have that many damage counters." % from_c.card_name()
				total += n
			if total > int(effect.get("count", 3)):
				return "You can move at most %d counters." % int(effect.get("count", 3))
		"type_attack_bonus", "reduce_enemy_attacks", "damage_all_enemies", "shuffle_weak_champions":
			pass
		"retreat_basic":  # Retreat Signal: target {"champions": [uids]} of your own active basic champions
			var picked: Array = target.get("champions", [])
			if picked.is_empty():
				return "Pick at least one of your active basic champions."
			for u in picked:
				var rc: Champion = g._champion_of(me, int(u))
				if rc == null or not me.active_champions().has(rc) or rc.champion_class() != "basic":
					return "Only your active basic champions can retreat."
		"mystery_remove":  # Mystery: target {"champion": uid} of an opponent's champion that has attached cards
			var mc: Champion = g._champion_of(foe, int(target.get("champion", -1)))
			if mc == null or foe.castled:
				return "Pick an enemy champion in the active play area."
			if mc.attached.is_empty():
				return "%s has no cards attached." % mc.card_name()
		"return_card":  # Galachs Will: target {"discard_index": i}, a spell or an enchantment depending on the effect
			var ri: int = int(target.get("discard_index", -1))
			if ri < 0 or ri >= me.discard.size() or str(me.discard[ri].get("kind", "")) != str(effect.get("kind", "spell")):
				return "Pick a %s card in your discard pile." % str(effect.get("kind", "spell"))
		"drain_mana", "drain_mana_per_card", "gain_mana_per_enchantment", "opponent_discards", "summon_discount", "wizardry_draw", "rearrange_top":
			pass
		"remove_enchantment":  # target {"enchantment": index into the opponent's enchantments}
			var ei: int = int(target.get("enchantment", -1))
			if ei < 0 or ei >= foe.enchantments.size():
				return "Pick one of the opponent's enchantments."
		"move_all_damage":  # target {"from": uid, "to": uid}, both yours
			var a: Champion = g._champion_of(me, int(target.get("from", -1)))
			var b: Champion = g._champion_of(me, int(target.get("to", -1)))
			if a == null or b == null or a == b:
				return "Pick two different champions of yours."
			if a.damage <= 0:
				return "%s has no damage to move." % a.card_name()
		"damage_many":  # target {"champions": [uid, ...]}: min(count, enemy champions) different enemy champions
			var uids: Array = target.get("champions", [])
			if foe.castled:
				return "Encamped champions cannot be targeted."
			var need: int = mini(int(effect.get("targets", 3)), foe.champions.size())
			if uids.size() != need or need == 0:
				return "Pick %d different enemy champions." % need
			var seen: Array = []
			for uid in uids:
				var c: Champion = g._champion_of(foe, int(uid))
				if c == null or seen.has(c):
					return "Bad target."
				seen.append(c)
		"repair_fortress":  # target {"discard_indices": [hand indices]} or {"discard_random": n}
			var err: String = _discard_choice_error(me, hand_index, target)
			if err != "":
				return err
		"no_attack":
			if foe.castled or g._champion_of(foe, int(target.get("champion", -1))) == null:
				return "Pick an enemy champion in the active play area."
		"return_champion":  # target {"discard_index": i}
			var di: int = int(target.get("discard_index", -1))
			if di < 0 or di >= me.discard.size() or str(me.discard[di].get("kind", "")) != "champion":
				return "Pick a champion card in your discard pile."
		"discard_spells_for_mana":  # target {"discard_indices": [hand indices of spell cards]}
			var idxs: Array = target.get("discard_indices", [])
			var used: Array = []
			for i in idxs:
				var hi: int = int(i)
				if hi == hand_index or hi < 0 or hi >= me.hand.size() or used.has(hi):
					return "Bad discard choice."
				if str(me.hand[hi].get("kind", "")) != "spell":
					return "Only spell cards can be discarded."
				used.append(hi)
		"discard_enchantment_for_mana":  # target {"enchantment": index in play} or {"hand_index": i}
			if target.has("enchantment"):
				var ei2: int = int(target.enchantment)
				if ei2 < 0 or ei2 >= me.enchantments.size():
					return "Pick one of your enchantments in play."
			elif target.has("hand_index"):
				var hi2: int = int(target.hand_index)
				if hi2 == hand_index or hi2 < 0 or hi2 >= me.hand.size() or str(me.hand[hi2].get("kind", "")) != "enchantment":
					return "Pick an enchantment card in your hand."
			else:
				return "Pick an enchantment to discard."
		_:
			return "Unknown spell effect: " + str(effect.get("op", ""))
	return ""


static func _discard_choice_error(me: PlayerState, hand_index: int, target: Dictionary) -> String:
	if target.has("discard_indices"):
		var used: Array = []
		for i in target.discard_indices:
			var hi: int = int(i)
			if hi == hand_index or hi < 0 or hi >= me.hand.size() or used.has(hi):
				return "Bad discard choice."
			used.append(hi)
	elif target.has("discard_random"):
		if int(target.discard_random) < 0 or int(target.discard_random) > me.hand.size() - 1:
			return "You do not have that many other cards."
	else:
		return "Choose the cards to discard (discard_indices or discard_random)."
	return ""


## Called after the spell card has left the hand (hand_index is where it used to be).
static func apply(g: Game, p: int, hand_index: int, effect: Dictionary, target: Dictionary) -> void:
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	match str(effect.get("op", "")):
		"type_attack_bonus":  # Magic Wave, Rain of Dragons
			me.buffs.append({"kind": "type_attack", "type": str(effect.get("type", "")), "amount": int(effect.get("amount", 0)), "turns_left": 1})
			g._log("P%d's %s champions attack for +%d this turn." % [p, str(effect.get("type", "")), int(effect.get("amount", 0))])
		"reduce_enemy_attacks":  # Grand Shield: until the end of the opponent's next turn
			foe.buffs.append({"kind": "outgoing_reduction", "amount": int(effect.get("amount", 0)), "turns_left": 1})
			g._log("P%d's attacks are reduced by %d during their next turn." % [1 - p, int(effect.get("amount", 0))])
		"damage_all_enemies":  # Thunderstorm: every opposing champion, encamped ones too
			var dmg: int = DamageRules.round_down_10(DamageRules.apply_enchantments(float(effect.get("amount", 0)), me, [], "", true))
			for c in foe.champions.duplicate():
				DamageRules.damage_champion(g, c, dmg, p, true)
		"shuffle_weak_champions":  # Vortex of the Damned: back into their deck, attached cards to the discard pile
			var below: int = int(effect.get("hp_below", 60))
			for c in foe.champions.duplicate():
				if c.max_hp() < below:
					foe.champions.erase(c)
					DamageRules.release_attached(g, c)
					foe.deck.append(c.card)
					g._log("%s is shuffled back into P%d's deck." % [c.describe(), 1 - p])
			for i in range(foe.deck.size() - 1, 0, -1):  # shuffle with the game's own random numbers
				var j: int = g.rng.randi_range(0, i)
				var tmp: Variant = foe.deck[i]
				foe.deck[i] = foe.deck[j]
				foe.deck[j] = tmp
		"retreat_basic":  # Retreat Signal
			for u in target.get("champions", []):
				var rc: Champion = g._champion_of(me, int(u))
				if rc != null:
					g.shuffle_champion_into_deck(rc)
		"mystery_remove":  # Mystery
			var mc: Champion = g._champion_of(foe, int(target.get("champion", -1)))
			var removed: int = mc.attached.size()
			DamageRules.release_attached(g, mc)
			g._log("Mystery removes %d attached card(s) from %s." % [removed, mc.card_name()])
		"return_card":  # Galachs Will
			var back: Dictionary = me.discard[int(target.discard_index)]
			me.discard.remove_at(int(target.discard_index))
			me.hand.append(back)
			g._log("P%d returns %s from the discard pile to their hand." % [p, str(back.get("name", "a card"))])
		"cleanse":  # removes the NEGATIVE statuses (poison) from one of your champions
			var c: Champion = g._champion_of(me, int(target.champion))
			for st in c.statuses.duplicate():
				if str(st.kind) == "poison":
					c.statuses.erase(st)
			g._log("%s is cleansed of negative statuses." % c.describe())
		"move_counters":
			for m in target.moves:
				var from_c: Champion = g._champion_of(me, int(m.from))
				var to_c: Champion = g._champion_of(foe, int(m.to))
				var n: int = mini(int(m.counters), int(from_c.damage / 10))
				from_c.damage -= n * 10
				g._log("%d damage counter(s) move from %s to %s." % [n, from_c.describe(), to_c.describe()])
				if foe.champions.has(to_c):
					DamageRules.damage_champion(g, to_c, n * 10, p)
		"drain_mana":
			foe.mana = maxi(0, foe.mana - int(effect.amount))
			g._log("P%d loses %d mana (%d left)." % [1 - p, int(effect.amount), foe.mana])
		"gain_mana_per_enchantment":  # Crimson Wave, effect 2
			var gain: int = int(effect.get("per_card", 1)) * me.enchantments.size()
			me.mana += gain
			g._log("P%d gains %d mana for the enchantments in play (%d now)." % [p, gain, me.mana])
		"drain_mana_per_card":
			var loss: int = int(effect.get("per_card", 1)) * foe.hand.size()
			foe.mana = maxi(0, foe.mana - loss)
			g._log("P%d loses %d mana for the cards in hand (%d left)." % [1 - p, loss, foe.mana])
		"opponent_discards":
			AttackEffects._discard_random(g, 1 - p, int(effect.get("amount", 1)))
		"remove_enchantment":
			var ench: Dictionary = foe.enchantments[int(target.enchantment)]
			foe.enchantments.remove_at(int(target.enchantment))
			foe.discard.append(g.enchantment_as_card(ench))
			g._log("%s is removed from P%d's enchantments." % [ench.get("name", "?"), 1 - p])
		"move_all_damage":
			var a: Champion = g._champion_of(me, int(target.from))
			var b: Champion = g._champion_of(me, int(target.to))
			var amount: int = a.damage
			a.damage = 0
			g._log("All %d damage moves from %s to %s." % [amount, a.describe(), b.describe()])
			# Forced move: it ignores protection. A death still scores a point for the opponent.
			b.damage = mini(b.max_hp(), b.damage + amount)
			if b.is_destroyed():
				DamageRules.destroy_champion(g, b, 1 - p)
		"damage_many":
			var total: float = DamageRules.apply_enchantments(float(effect.amount), me, [], "", true)
			for uid in target.champions:
				var c2: Champion = g._champion_of(foe, int(uid))
				if c2 != null:
					DamageRules.damage_champion(g, c2, DamageRules.round_down_10(total), p)
		"repair_fortress":
			var k: int = _discard_and_count(g, p, hand_index, target)
			var cap: int = int(me.fortress_def.get("hp", 500))
			var before: int = me.fortress_hp
			me.fortress_hp = mini(cap, me.fortress_hp + k * int(effect.get("per_card", 50)))
			g._log("P%d discards %d card(s) and repairs the Fortress by %d." % [p, k, me.fortress_hp - before])
		"no_attack":
			var t: Champion = g._champion_of(foe, int(target.champion))
			t.statuses.append({"kind": "no_attack", "turns_left": int(effect.get("turns", 1))})
			g._log("%s cannot attack on its owner's next turn." % t.describe())
		"wizardry_draw":
			var drawn: Array = []
			for i in int(effect.get("draw", 3)):
				if me.deck.is_empty():
					g._finish(1 - p, "Decking out")
					return
				var card: Dictionary = me.deck.pop_back()
				me.hand.append(card)
				drawn.append(card)
			var choice: int = int(target.get("discard_choice", g.rng.randi_range(0, drawn.size() - 1)))
			choice = clampi(choice, 0, drawn.size() - 1)
			me.hand.erase(drawn[choice])
			me.discard.append(drawn[choice])
			g._log("P%d draws %d and discards %s." % [p, drawn.size(), drawn[choice].get("name", "a card")])
		"rearrange_top":
			var n2: int = mini(int(effect.get("count", 5)), me.deck.size())
			var top: Array = []  # top of the deck first
			for i in n2:
				top.append(me.deck[me.deck.size() - 1 - i])
			var order: Array = target.get("order", range(n2))
			if order.size() == n2:
				for i in n2:
					me.deck.pop_back()
				for i in range(n2 - 1, -1, -1):
					me.deck.append(top[int(order[i])])
			g._log("P%d rearranges the top %d cards of their deck." % [p, n2])
		"return_champion":
			var card2: Dictionary = me.discard[int(target.discard_index)]
			me.discard.remove_at(int(target.discard_index))
			me.hand.append(card2)
			g._log("P%d returns %s to their hand." % [p, card2.get("name", "a champion")])
		"discard_spells_for_mana":
			var cards: Array = []
			for i in target.get("discard_indices", []):
				cards.append(me.hand[int(i) - (1 if int(i) > hand_index else 0)])
			for card3 in cards:
				me.hand.erase(card3)
				me.discard.append(card3)
			me.mana += cards.size() * int(effect.get("per_card", 2))
			g._log("P%d discards %d spell(s) and gains %d mana." % [p, cards.size(), cards.size() * int(effect.get("per_card", 2))])
		"discard_enchantment_for_mana":
			var ench2: Dictionary
			if target.has("enchantment"):
				ench2 = me.enchantments[int(target.enchantment)]
				me.enchantments.erase(ench2)
			else:
				var hi: int = int(target.hand_index) - (1 if int(target.hand_index) > hand_index else 0)
				ench2 = me.hand[hi]
				me.hand.remove_at(hi)
			me.discard.append(g.enchantment_as_card(ench2))
			me.mana += int(effect.get("amount", 5))
			g._log("P%d discards %s and gains %d mana." % [p, ench2.get("name", "an enchantment"), int(effect.get("amount", 5))])
		"summon_discount":
			me.summon_discount += int(effect.get("amount", 1))
			g._log("P%d's next summon this turn costs %d less (a sacrifice or mana)." % [p, int(effect.get("amount", 1))])


static func _discard_and_count(g: Game, p: int, hand_index: int, target: Dictionary) -> int:
	var me: PlayerState = g.players[p]
	var cards: Array = []
	if target.has("discard_indices"):
		for i in target.discard_indices:
			cards.append(me.hand[int(i) - (1 if int(i) > hand_index else 0)])
	else:
		var pool: Array = me.hand.duplicate()
		for i in int(target.discard_random):
			var idx: int = g.rng.randi_range(0, pool.size() - 1)
			cards.append(pool[idx])
			pool.remove_at(idx)
	for card in cards:
		me.hand.erase(card)
		me.discard.append(card)
	return cards.size()
