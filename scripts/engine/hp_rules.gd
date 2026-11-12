## hp_rules.gd - Champion HP that changes while the champion is in play: Super Shrink (-20 HP for the opponent's
## active champions), Fusion (+20 per OTHER active champion of the same color), Power Source (+10 per card in hand) and
## Gaia (copies the HP of the opponent's active champion with the most HP, 50 if there is none). All of it is
## recalculated after every action (Game._ok) and whenever a champion is destroyed. A champion whose damage is
## then at or above its HP is destroyed and the opponent scores a kill.
class_name HpRules
extends RefCounted

const GAIA_FALLBACK_HP := 50


static func recalc(g: Game) -> void:
	if g.hp_recalc_busy or g.players.size() < 2:
		return
	g.hp_recalc_busy = true
	for round in 6:  # a destruction can change what Gaia copies, so repeat until nothing changes
		_update(g)
		var doomed: Array = []
		for ps in g.players:
			for c in ps.champions:
				if c.damage >= c.max_hp():
					doomed.append(c)
		if doomed.is_empty():
			break
		for c in doomed:
			if g.players[c.owner].champions.has(c):
				g._log("%s's HP is now %d, so it is destroyed." % [c.describe(), c.max_hp()])
				DamageRules.destroy_champion(g, c, 1 - c.owner)
	g.hp_recalc_busy = false


static func _update(g: Game) -> void:
	for ps in g.players:
		for c in ps.champions:
			c.hp_mod = 0
			c.hp_override = -1
	for p in 2:
		var ps: PlayerState = g.players[p]
		for ench in ps.enchantments:  # Super Shrink
			if ench.has("hp_aura_enemy"):
				for c in g.players[1 - p].active_champions():
					c.hp_mod += int(ench.hp_aura_enemy)
		for c in ps.champions:
			if c.has_ability() and c.card.ability.has("hp_per_own_creature"):  # Water Hound: +10 per OTHER active creature
				var creatures: int = 0
				for o in ps.active_champions():
					if o != c and o.champion_type() == "Creature":
						creatures += 1
				c.hp_mod += int(c.card.ability.hp_per_own_creature) * creatures
			for att in c.attached:
				match str(att.get("attach_kind", "")):
					"fusion":  # +20 for each OTHER active champion of yours of the same color
						var same: int = 0
						for o in ps.active_champions():
							if o != c and o.color() == c.color():  # the other champions, not itself
								same += 1
						c.hp_mod += 20 * same
					"power_source":  # +10 for every card in your hand
						c.hp_mod += 10 * ps.hand.size()
	for p in 2:  # Gaia: the most HP among the opponent's active champions (other Gaias are not copied)
		for c in g.players[p].champions:
			if c.has_ability() and bool(c.card.ability.get("gaia_hp", false)):
				var best: int = -1
				for o in g.players[1 - p].active_champions():
					if o.has_ability() and bool(o.card.ability.get("gaia_hp", false)):
						continue
					best = maxi(best, o.max_hp())
				c.hp_override = best if best >= 0 else GAIA_FALLBACK_HP
