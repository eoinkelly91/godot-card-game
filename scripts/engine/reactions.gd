## reactions.gd - Reactions: enchantments that trigger on an opponent's attack and resolve completely
## before the attack lands. Triggers can test the attacker's color, type, whether it has an ability,
## whether the attack deals damage, and whether a spell was played with the attack.
## Effects so far: negate_attack, damage_attacker. Add new reaction effects in run().
class_name ReactionRules
extends RefCounted


## Returns true if the attack was negated.
static func run(g: Game, attacker_player: int, attacker: Champion, atk: Dictionary, spell_flag: bool) -> bool:
	var defender: PlayerState = g.players[1 - attacker_player]
	var negated: bool = false
	for ench in defender.enchantments.duplicate():
		if typeof(ench.get("reaction")) != TYPE_DICTIONARY:
			continue
		var rx: Dictionary = ench.reaction
		if not matches(rx.get("when", {}), attacker, atk, spell_flag):
			continue
		g._log("Reaction: %s triggers." % ench.get("name", "?"))
		var eff: Dictionary = rx.get("effect", {})
		match str(eff.get("op", "")):
			"negate_attack":
				negated = true
			"damage_attacker":
				DamageRules.damage_champion(g, attacker, int(eff.get("amount", 0)), 1 - attacker_player)
		if bool(rx.get("one_shot", false)):
			defender.enchantments.erase(ench)
			defender.discard.append(g.enchantment_as_card(ench))
		if g.finished or not g.players[attacker_player].champions.has(attacker):
			break
	return negated


## Supported conditions: attacker_color, attacker_type, attacker_has_ability, deals_damage, spell_with_attack.
static func matches(when: Dictionary, attacker: Champion, atk: Dictionary, spell_flag: bool) -> bool:
	for key in when:
		match str(key):
			"attacker_color":
				if attacker.color() != str(when[key]):
					return false
			"attacker_type":
				if attacker.champion_type() != str(when[key]):
					return false
			"attacker_has_ability":
				if attacker.has_ability() != bool(when[key]):
					return false
			"deals_damage":
				if (int(atk.get("damage", 0)) > 0) != bool(when[key]):
					return false
			"spell_with_attack":
				if spell_flag != bool(when[key]):
					return false
			_:
				push_warning("Unknown reaction condition: " + str(key))
				return false
	return true
