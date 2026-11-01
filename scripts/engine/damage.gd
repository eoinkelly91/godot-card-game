## damage.gd - Damage maths and its consequences: the damage order (attack, then ability, then spells and
## attack buffs, then enchantment percentages, rounded down to the nearest 10), applying damage to
## champions and Fortresses, encampment immunity, destroying champions (discard pile, Annihilation
## points) and the "would be destroyed" hook.
class_name DamageRules
extends RefCounted


## coin_extra: damage already decided by coin flips (per-Heads damage, a Heads bonus); attack.gd flips
## the coins so they are flipped exactly once per attack.
static func calc(g: Game, attacker: Champion, atk: Dictionary, target: Champion, spell_bonus: int,
		enchant_order: Array = [], coin_extra: int = 0) -> int:
	var me: PlayerState = g.players[attacker.owner]
	var foe: PlayerState = g.players[1 - attacker.owner]
	var total: float = float(atk.get("damage", 0)) + float(coin_extra)
	# Attack effects printed on the attack itself.
	if atk.has("bonus_vs_type") and target != null and target.champion_type() == str(atk.bonus_vs_type.type):
		total += float(atk.bonus_vs_type.amount)
	if atk.has("bonus_vs_class") and target != null and target.champion_class() == str(atk.bonus_vs_class["class"]):
		total += float(atk.bonus_vs_class.amount)
	total += float(int(atk.get("per_own_enchantment", 0)) * me.enchantments.size())
	total += float(int(atk.get("per_opponent_hand_card", 0)) * foe.hand.size())
	if atk.has("per_champion_in_own_discard"):
		var n: int = 0
		for c in me.discard:
			if str(c.get("kind", "")) == "champion":
				n += 1
		total += float(int(atk.per_champion_in_own_discard) * n)
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
		if trigger == "on_attack" and ab.has("bonus_per"):
			total += float(int(ab.bonus_per.amount) * _count_for(g, attacker, str(ab.bonus_per.count)))
	total += float(spell_bonus) + float(StatusRules.attack_bonus(g.players[attacker.owner]))
	total = apply_enchantments(total, g.players[attacker.owner], enchant_order, attacker.color(), false)
	return round_down_10(total)


## Counts used by "+N damage for each ..." abilities.
static func _count_for(g: Game, attacker: Champion, what: String) -> int:
	var n: int = 0
	match what:
		"own_champions":  # your other champions; the attacker itself is not counted
			n = g.players[attacker.owner].champions.size() - 1
		"own_spirits":  # your other Spirits
			for c in g.players[attacker.owner].champions:
				if c.champion_type() == "Spirit" and c != attacker:
					n += 1
		"spirits_in_play":  # both players, active or encamped, not counting the attacker
			for ps in g.players:
				for c in ps.champions:
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
static func destroy_champion(g: Game, champion: Champion, credit_player: int) -> void:
	var ps: PlayerState = g.players[champion.owner]
	ps.champions.erase(champion)
	ps.discard.append(champion.card)
	for a in champion.attached:
		ps.discard.append(a)
	if credit_player >= 0 and credit_player != champion.owner:
		g.players[credit_player].kills += 1
	g._log("%s is destroyed." % champion.describe())
	g._check_win()
