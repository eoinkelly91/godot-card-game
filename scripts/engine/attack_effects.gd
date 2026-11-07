## attack_effects.gd - Effects printed on an attack that happen around the damage: coin flips that decide
## damage, self-damage, hitting several champions, poison, discards and draws. Called from attack.gd.
## Every coin is flipped through Game.flip_coin(), exactly once per effect.
## Effects the engine cannot do yet are marked "unimplemented" in the card data; they are logged and
## the attack does only its printed damage.
class_name AttackEffects
extends RefCounted


## Coin flips that decide damage BEFORE it is calculated. Returns {"extra": int, "fizzle": bool}.
static func coin_damage(g: Game, atk: Dictionary) -> Dictionary:
	var extra: int = 0
	var fizzle: bool = false
	if atk.has("coins"):
		var heads: int = 0
		for i in int(atk.coins.count):
			if g.flip_coin():
				heads += 1
		extra += heads * int(atk.coins.per_heads_damage)
		g._log("%d Heads out of %d coins." % [heads, int(atk.coins.count)])
	if atk.has("coin_bonus"):
		if g.flip_coin():
			extra += int(atk.coin_bonus)
			g._log("Coin: Heads, +%d damage." % int(atk.coin_bonus))
		else:
			g._log("Coin: Tails.")
	if bool(atk.get("coin_fizzle", false)):
		if g.flip_coin():
			g._log("Coin: Heads, the attack goes ahead.")
		else:
			fizzle = true
			g._log("Coin: Tails, the attack does nothing.")
	return {"extra": extra, "fizzle": fizzle}


## Effects that happen when the attack lands (after its damage). target may be null (Fortress or no target).
static func after_damage(g: Game, p: int, attacker: Champion, atk: Dictionary, target: Champion) -> void:
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	if atk.has("unimplemented"):
		g._log("(Not implemented yet: %s)" % str(atk.unimplemented))

	# One coin per enemy champion, 10/20 damage to that champion on Heads.
	if atk.has("coin_each_enemy"):
		for c in foe.champions.duplicate():
			if g.flip_coin():
				_hit(g, p, attacker, c, int(atk.coin_each_enemy))
	if atk.has("damage_each_enemy"):
		for c in foe.champions.duplicate():
			_hit(g, p, attacker, c, int(atk.damage_each_enemy))
	if atk.has("splash_enemies"):  # every OTHER enemy champion; the target already took the attack's damage
		for c in foe.champions.duplicate():
			if c != target:
				_hit(g, p, attacker, c, int(atk.splash_enemies))
	if atk.has("splash_all"):  # every champion in play, your own included, but not the attacker itself
		var everyone: Array = foe.champions.duplicate()
		everyone.append_array(me.champions)
		for c in everyone:
			if c != attacker:
				_hit(g, p, attacker, c, int(atk.splash_all))

	if atk.has("poison") and target != null and foe.champions.has(target):
		if not bool(atk.get("coin_gated", false)) or g.flip_coin():
			StatusRules.apply_poison(g, target, int(atk.poison.amount), int(atk.poison.turns), p)
		else:
			g._log("Coin: Tails, no poison.")

	if atk.has("coin_opponent_discards"):
		if g.flip_coin():
			_discard_random(g, 1 - p, int(atk.coin_opponent_discards))
		else:
			g._log("Coin: Tails.")
	if atk.has("coin_draw"):  # Predict: heads draws cards, tails does nothing
		if g.flip_coin():
			_draw(g, p, int(atk.coin_draw))
		else:
			g._log("Coin: Tails.")
	if atk.has("coin_draw_or_discard"):
		if g.flip_coin():
			_draw(g, p, int(atk.coin_draw_or_discard.draw))
		else:
			_discard_random(g, p, int(atk.coin_draw_or_discard.discard))
	if bool(atk.get("coin_protect_self", false)) and me.champions.has(attacker):
		if g.flip_coin():
			attacker.statuses.append({"kind": "protected"})
			g._log("%s is protected until its owner's next turn." % attacker.card_name())
		else:
			g._log("Coin: Tails.")

	if bool(atk.get("duel", false)) and target != null and foe.champions.has(target):
		target.statuses.append({"kind": "duel", "duelist": attacker.uid, "turns_left": 1})
		g._log("%s must attack %s on its owner's next turn." % [target.describe(), attacker.card_name()])
	if bool(atk.get("coin_extra_attack", false)):
		if g.flip_coin():
			me.extra_attacks.append(attacker.uid)
			g._log("Coin: Heads, another of P%d's champions can attack again this turn." % p)
		else:
			g._log("Coin: Tails.")
	if bool(atk.get("coin_return_target_to_hand", false)) and target != null and foe.champions.has(target):
		if g.flip_coin():
			foe.champions.erase(target)
			foe.hand.append(target.card)
			for att in target.attached:
				foe.hand.append(att)
			g._log("%s and its attached cards return to P%d's hand." % [target.card_name(), 1 - p])
		else:
			g._log("Coin: Tails.")

	# Self damage comes last. A champion destroyed by its own recoil scores a point for the opponent.
	if atk.has("self_damage") and me.champions.has(attacker):
		DamageRules.damage_champion(g, attacker, int(atk.self_damage), 1 - p)


## Damage from an attack's side effect (splash and so on); Gnome ignores champions with too much max HP.
static func _hit(g: Game, p: int, attacker: Champion, c: Champion, amount: int) -> void:
	if c.has_ability() and c.card.ability.has("immune_to_attackers_max_hp_over") \
			and attacker.max_hp() > int(c.card.ability.immune_to_attackers_max_hp_over):
		g._log("%s cannot be damaged by a champion with over %d HP." % [c.card_name(), int(c.card.ability.immune_to_attackers_max_hp_over)])
		return
	DamageRules.damage_champion(g, c, amount, p)


static func _draw(g: Game, p: int, n: int) -> void:
	var ps: PlayerState = g.players[p]
	for i in n:
		if ps.deck.is_empty():
			g._finish(1 - p, "Decking out")
			return
		ps.hand.append(ps.deck.pop_back())
	g._log("P%d draws %d card(s)." % [p, n])


## Discarded cards are chosen at random for now (a player-choice prompt comes with the UI).
static func _discard_random(g: Game, p: int, n: int) -> void:
	var ps: PlayerState = g.players[p]
	for i in n:
		if ps.hand.is_empty():
			return
		var idx: int = g.rng.randi_range(0, ps.hand.size() - 1)
		ps.discard.append(ps.hand[idx])
		ps.hand.remove_at(idx)
		g._log("P%d discards a card." % p)
