## damage.gd - Damage maths and its consequences: the damage order (attack, then ability, then spells and
## attack buffs, then enchantment percentages, rounded down to the nearest 10), applying damage to
## champions and Fortresses, encampment immunity, destroying champions (discard pile, Annihilation
## points) and the "would be destroyed" hook.
class_name DamageRules
extends RefCounted


## coin_extra: damage already decided by coin flips (per-Heads damage, a Heads bonus); attack.gd flips
## the coins so they are flipped exactly once per attack. `notes` (optional) collects a line for every part of
## the total, so the screen can explain where an attack's value comes from.
static func calc(g: Game, attacker: Champion, atk: Dictionary, target: Champion, spell_bonus: int,
		enchant_order: Array = [], coin_extra: int = 0, notes: Array = []) -> int:
	var me: PlayerState = g.players[attacker.owner]
	var foe: PlayerState = g.players[1 - attacker.owner]
	var total: float = float(atk.get("damage", 0)) + float(coin_extra)
	notes.append("Base damage: %d" % int(total))
	# Attack effects printed on the attack itself.
	if atk.has("bonus_vs_type") and target != null and target.champion_type() == str(atk.bonus_vs_type.type):
		total += float(atk.bonus_vs_type.amount)
		notes.append("+%d against %s champions" % [int(atk.bonus_vs_type.amount), str(atk.bonus_vs_type.type)])
	if atk.has("bonus_vs_class") and target != null and target.champion_class() == str(atk.bonus_vs_class["class"]):
		total += float(atk.bonus_vs_class.amount)
		notes.append("+%d against %s champions" % [int(atk.bonus_vs_class.amount), str(atk.bonus_vs_class["class"])])
	var own_ench: int = int(atk.get("per_own_enchantment", 0)) * me.enchantments.size()
	if own_ench != 0:
		total += float(own_ench)
		notes.append("+%d (%d per enchantment you have)" % [own_ench, int(atk.per_own_enchantment)])
	if bool(atk.get("damage_equals_own_hp", false)):  # Gob's Vortex: damage equal to the attacker's current HP
		total += float(attacker.current_hp())
		notes.append("+%d (its current HP)" % attacker.current_hp())
	var hand_cards: int = int(atk.get("per_opponent_hand_card", 0)) * foe.hand.size()
	if hand_cards != 0:
		total += float(hand_cards)
		notes.append("+%d (%d per card in the opponent's hand)" % [hand_cards, int(atk.per_opponent_hand_card)])
	if atk.has("per_champion_in_own_discard"):
		var n: int = 0
		for c in me.discard:
			if str(c.get("kind", "")) == "champion":
				n += 1
		total += float(int(atk.per_champion_in_own_discard) * n)
		notes.append("+%d (%d per champion in your discard pile)" % [int(atk.per_champion_in_own_discard) * n, int(atk.per_champion_in_own_discard)])
	# The champion's ability.
	if attacker.has_ability():
		var ab: Dictionary = attacker.card.ability
		var trigger: String = str(ab.get("trigger", "on_attack"))
		if trigger == "on_attack" and ab.has("bonus_damage"):
			var applies: bool = true
			if ab.has("vs_type"):
				applies = target != null and target.champion_type() == str(ab.vs_type)
			if applies:
				total += float(ab.bonus_damage)
				notes.append("+%d from %s's ability" % [int(ab.bonus_damage), attacker.card_name()])
		if trigger == "on_attack" and ab.has("bonus_per"):
			var counted: int = int(ab.bonus_per.amount) * _count_for(g, attacker, str(ab.bonus_per.count))
			total += float(counted)
			notes.append("+%d from %s's ability (%d each)" % [counted, attacker.card_name(), int(ab.bonus_per.amount)])
	for sst in attacker.statuses:
		if str(sst.kind) == "stored_bonus":
			total += float(sst.amount)
			notes.append("+%d saved up by not attacking last turn" % int(sst.amount))
	# Cards that count things (Brickeen, Hydrostretch, Psyville, Psybar)
	if atk.has("per_active_named"):
		var named: int = 0
		for c in me.active_champions():
			if c != attacker and (atk.per_active_named.names as Array).has(c.card_name()):  # the other ones, not itself
				named += 1
		total += float(int(atk.per_active_named.amount) * named)
		notes.append("+%d (%d each for %d other active %s)" % [int(atk.per_active_named.amount) * named, int(atk.per_active_named.amount), named, " / ".join(atk.per_active_named.names)])
	if atk.has("per_active_color_own"):
		var colored: int = 0
		for c in me.active_champions():
			if c.color().to_lower() == str(atk.per_active_color_own.color).to_lower():
				colored += 1
		total += float(int(atk.per_active_color_own.amount) * colored)
		notes.append("+%d (%d each for %d of your active %s champions)" % [int(atk.per_active_color_own.amount) * colored, int(atk.per_active_color_own.amount), colored, str(atk.per_active_color_own.color)])
	var in_play: int = int(atk.get("per_enchantment_in_play", 0)) * (me.enchantments.size() + foe.enchantments.size())
	if in_play != 0:
		total += float(in_play)
		notes.append("+%d (%d per enchantment in play, both players)" % [in_play, int(atk.per_enchantment_in_play)])
	if spell_bonus != 0:
		total += float(spell_bonus)
		notes.append("+%d from a spell played with the attack" % spell_bonus)
	var buffs: int = StatusRules.attack_bonus(g.players[attacker.owner])
	if buffs != 0:
		total += float(buffs)
		notes.append("+%d from attack bonuses (spells)" % buffs)
	if total > 0.0:  # Magic Wave / Rain of Dragons (this turn, by champion type) and Warrior Idol (compounds every turn)
		var by_type: int = StatusRules.type_bonus(me, attacker.champion_type())
		if by_type != 0:
			total += float(by_type)
			notes.append("+%d for %s champions this turn (spell)" % [by_type, attacker.champion_type()])
		for att in attacker.attached:
			if str(att.get("attach_kind", "")) == "warrior_idol":
				total += 10.0 * float(int(att.get("_stacks", 1)))
				notes.append("+%d from Warrior Idol (+10 for every turn it has been attached)" % (10 * int(att.get("_stacks", 1))))
	var lair: int = int(g.players[attacker.owner].fortress_def.get("creature_bonus_damage", 0))  # Beasts Lair
	if lair > 0 and total > 0.0 and attacker.champion_type() == "Creature":
		total += float(lair)
		notes.append("+%d from your Fortress (%s)" % [lair, str(g.players[attacker.owner].fortress_def.get("name", "Fortress"))])
	var before_ench: float = total
	total = apply_enchantments(total, g.players[attacker.owner], enchant_order, attacker.color(), false)
	if absf(total - before_ench) > 0.01:
		notes.append("%+d from your enchantments (percentage)" % int(round(total - before_ench)))
	var shield: int = StatusRules.outgoing_reduction(me)  # Grand Shield
	if shield > 0:
		notes.append("-%d from Grand Shield" % mini(shield, int(total)))
	total = maxf(0.0, total - float(shield))
	var rounded: int = round_down_10(total)
	if rounded != int(total):
		notes.append("Rounded down to the nearest 10")
	return rounded


## Where an attack's value comes from right now (one line per part), for the hover text. Coin flips and
## bonuses that depend on the target cannot be known in advance, so they are only mentioned.
static func explain(g: Game, attacker: Champion, atk: Dictionary) -> Array:
	var notes: Array = []
	calc(g, attacker, atk, null, 0, [], 0, notes)
	if atk.has("coins") or atk.has("coin_damage") or atk.has("bonus_vs_type") or atk.has("bonus_vs_class"):
		notes.append("(Coin flips and bonuses against a type of target are added when it attacks.)")
	return notes


## The damage an attack would do right now against an unknown target (fixed bonuses, abilities, saved bonuses and
## enchantments included, coin flips and target-dependent bonuses not). The screen shows this on cards and menus.
static func preview(g: Game, attacker: Champion, atk: Dictionary) -> int:
	return calc(g, attacker, atk, null, 0, [], 0)


## Counts used by "+N damage for each ..." abilities.
static func _count_for(g: Game, attacker: Champion, what: String) -> int:
	var n: int = 0
	match what:
		"own_champions":  # your other champions; the attacker itself is not counted
			n = g.players[attacker.owner].champions.size() - 1
		"own_spirits":  # your other Spirits
			for c in g.players[attacker.owner].active_champions():
				if c.champion_type() == "Spirit" and c != attacker:
					n += 1
		"spirits_in_play":  # both players' active Spirits, not counting the attacker
			for ps in g.players:
				for c in ps.active_champions():
					if c.champion_type() == "Spirit" and c != attacker:
						n += 1
		"own_damage_per_5_counters":
			n = int(attacker.counters() / 5)
		_:
			push_warning("Unknown ability count: " + what)
	return n


## Enchantment percentage bonuses compound. For standalone spell damage only enchantments that say
## "affects_spell_damage" apply.
static func apply_enchantments(total: float, ps: PlayerState, order: Array, attacker_color: String,
		spell_damage: bool) -> float:
	var list: Array = []
	for i in order:
		if int(i) >= 0 and int(i) < ps.enchantments.size():
			list.append(ps.enchantments[int(i)])
	for ench in ps.enchantments:
		if not list.has(ench):
			list.append(ench)
	for ench in list:
		if not ench.has("damage_percent"):
			continue
		if spell_damage and not bool(ench.get("affects_spell_damage", false)):
			continue
		if ench.has("only_color") and not spell_damage and attacker_color != str(ench.only_color):
			continue
		total *= 1.0 + float(ench.damage_percent) / 100.0
	return total


static func round_down_10(value: float) -> int:
	return int(floor((value + 0.0001) / 10.0)) * 10


## credit_player is the player whose effect this is (-1 for none). Champions in the encampment area are
## immune to NEW effects from the opponent; pass from_existing_effect = true for ongoing effects like poison.
static func damage_champion(g: Game, champion: Champion, amount: int, credit_player: int,
		from_existing_effect: bool = false) -> void:
	if amount <= 0:
		return
	if not from_existing_effect and credit_player >= 0 and credit_player != champion.owner \
			and g.players[champion.owner].castled:
		g._log("%s is encamped and immune." % champion.describe())
		return
	if is_protected(champion):
		g._log("%s is protected: the damage is prevented." % champion.describe())
		return
	champion.damage = mini(champion.max_hp(), champion.damage + amount)  # excess damage is lost
	g._log("%s takes %d damage." % [champion.describe(), amount])
	if champion.is_destroyed():
		if destruction_prevented(g, champion):
			champion.damage = champion.max_hp() - 10
			return
		destroy_champion(g, champion, credit_player)
	elif champion.has_ability() and champion.card.ability.has("clear_damage_at") \
			and champion.damage >= int(champion.card.ability.clear_damage_at):
		g._log("%s removes all its damage." % champion.card_name())
		champion.damage = 0


## A champion with a "protected" status takes no damage (set by a successful Mist or Glide coin flip).
static func is_protected(champion: Champion) -> bool:
	for st in champion.statuses:
		if str(st.kind) == "protected":
			return true
	return false


static func damage_fortress(g: Game, player_index: int, amount: int) -> void:
	if amount <= 0:
		return
	var ps: PlayerState = g.players[player_index]
	ps.fortress_hp = maxi(0, ps.fortress_hp - amount)
	g._log("P%d's Fortress takes %d damage (%d left)." % [player_index, amount, ps.fortress_hp])
	g._check_win()


## Hook: "whenever something would destroy a champion, check whether any spell or enchantment prevents it".
## Nothing prevents destruction yet; add card effects here when you design them.
static func destruction_prevented(_g: Game, _champion: Champion) -> bool:
	return false


## credit_player gets an Annihilation point; pass -1 when no enemy caused it (sacrifice, carried-over damage).
## counts_as_loss is false for carried-over sacrifice damage (Mist of Grief ignores those deaths).
static func destroy_champion(g: Game, champion: Champion, credit_player: int, counts_as_loss: bool = true) -> void:
	var ps: PlayerState = g.players[champion.owner]
	ps.champions.erase(champion)
	ps.discard.append(champion.card)
	release_attached(g, champion)
	if credit_player >= 0 and credit_player != champion.owner:
		g.players[credit_player].kills += 1
	g._log("%s is destroyed." % champion.describe())
	# Mist of Grief: any champion you lose (attacks, poison, spells, recoil) except sacrifices and carried-over damage.
	if counts_as_loss:
		for ench in ps.enchantments:
			if typeof(ench.get("on_champion_lost_to_attack")) == TYPE_DICTIONARY:
				var gain: int = int(ench.on_champion_lost_to_attack.get("gain_mana", 0))
				ps.mana += gain
				g._log("%s gives P%d %d mana." % [ench.get("name", "An enchantment"), champion.owner, gain])
	g._check_win()
	HpRules.recalc(g)  # what Gaia copies may have just changed


## Cards attached to a champion that leaves play (destroyed, sacrificed, shuffled away) go to its owner's discard pile.
static func release_attached(g: Game, champion: Champion) -> void:
	var ps: PlayerState = g.players[champion.owner]
	for a in champion.attached:
		var card: Dictionary = (a as Dictionary).duplicate()
		card.erase("_stacks")
		card.erase("attach_kind")
		ps.discard.append(card)
	champion.attached.clear()
