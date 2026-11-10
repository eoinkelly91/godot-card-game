## attack.gd - The Attack step: spells (free, any number, before or after attacking), attacks (one per
## color per turn, Fortress targeting rules, castling and encampment rules, attached spells, reactions,
## fizzling). Champions in the encampment area cannot attack and cannot be targeted by the opponent's
## attacks or spells. Nothing here is allowed on a first turn.
class_name AttackRules
extends RefCounted


## Plays a spell on its own (not attached to an attack). Any number, at any time after the castle step
## (Summon or Attack step), paying the card's mana cost. One effect of the card is chosen.
## target: {"champion": uid} or {"fortress": player_index}, depending on the effect.
static func play_spell(g: Game, p: int, hand_index: int, effect_index: int, target: Dictionary = {}) -> Dictionary:
	var chk: Dictionary = TurnRules.require_turn(g, p)
	if not chk.ok:
		return chk
	var ps: PlayerState = g.players[p]
	if ps.is_first_turn():
		return g._fail("You cannot play spells on your first turn.")
	if LockRules.is_locked(g, p, "spell"):
		return g._fail("Your spells are locked.")
	if hand_index < 0 or hand_index >= ps.hand.size():
		return g._fail("Bad hand index.")
	var card: Dictionary = ps.hand[hand_index]
	if str(card.get("kind", "")) != "spell":
		return g._fail("That is not a spell.")
	var effects: Array = card.get("effects", [])
	if effect_index < 0 or effect_index >= effects.size():
		return g._fail("Bad effect index.")
	var effect: Dictionary = effects[effect_index]
	var spell_cost: int = int(card.get("cost", 0))
	if ps.mana < spell_cost:
		return g._fail("Not enough banked mana (%d needed)." % spell_cost)

	# Validate the target BEFORE the card is consumed.
	var op: String = str(effect.get("op", ""))
	var target_champion: Champion = null
	match op:
		"heal":
			target_champion = g._champion_of(ps, int(target.get("champion", -1)))
			if target_champion == null:
				return g._fail("Heal needs one of your own champions as target.")
		"damage", "poison":
			if target.has("champion"):
				target_champion = g._find_champion(int(target.champion))
				if target_champion == null:
					return g._fail("Target champion not found.")
				if target_champion.owner != p and g.players[target_champion.owner].castled:
					return g._fail("Encamped champions cannot be targeted.")
			elif target.has("fortress") and op == "damage":
				var fi: int = int(target.fortress)
				if fi < 0 or fi > 1:
					return g._fail("Bad fortress index.")
			else:
				return g._fail("This effect needs a champion target.")
			if op == "poison" and target_champion.owner == p:
				return g._fail("Poison needs an enemy champion.")
		"bonus_damage":  # played on its own it names the champion whose next attack this turn gets the bonus
			target_champion = g._champion_of(ps, int(target.get("champion", -1)))
			if target_champion == null:
				return g._fail("Pick one of your champions to give the bonus to, or attach the spell to an attack.")
			var cant: String = Preflight.attack_problem(g, p, target_champion)
			if cant != "":
				return g._fail("The bonus would be wasted: " + cant)
		"lock", "draw", "gain_mana", "buff_attack":
			pass
		"attach":  # Warrior Idol, Fusion, Power Source: the card stays on one of your champions
			target_champion = g._champion_of(ps, int(target.get("champion", -1)))
			if target_champion == null:
				return g._fail("Pick one of your own champions to attach this card to.")
			if target_champion.attached.size() >= int(g.rules.max_attached_cards):
				return g._fail("%s already has %d cards attached." % [target_champion.card_name(), int(g.rules.max_attached_cards)])
		_:
			var verr: String = SpellEffects.validate(g, p, hand_index, effect, target)
			if verr != "":
				return g._fail(verr)

	ps.mana -= spell_cost
	ps.hand.remove_at(hand_index)
	if op != "attach":  # an attached card stays on its champion instead of going to the discard pile
		ps.discard.append(card)
	g.spells_this_turn += 1
	g._log("P%d casts %s (effect %d)." % [p, card.get("name", "?"), effect_index + 1])

	match op:
		"heal":
			target_champion.damage = maxi(0, target_champion.damage - int(effect.get("amount", 0)))
		"damage":
			var total: float = DamageRules.apply_enchantments(float(effect.get("amount", 0)), ps, [], "", true)
			var dmg: int = DamageRules.round_down_10(total)
			if target_champion != null:
				DamageRules.damage_champion(g, target_champion, dmg, p)
			else:
				DamageRules.damage_fortress(g, int(target.fortress), dmg)
		"poison":
			StatusRules.apply_poison(g, target_champion, int(effect.get("amount", 10)), int(effect.get("turns", 1)), p)
		"buff_attack":
			StatusRules.add_attack_buff(g, p, int(effect.get("amount", 0)), int(effect.get("turns", 1)))
		"lock":
			LockRules.add(g, 1 - p, str(effect.get("what", "")), int(effect.get("turns", 1)))
		"draw":
			for i in int(effect.get("amount", 1)):
				if ps.deck.is_empty():
					g._finish(1 - p, "Decking out")
					break
				ps.hand.append(ps.deck.pop_back())
		"gain_mana":
			ps.mana += int(effect.get("amount", 0))
		"attach":
			var att: Dictionary = card.duplicate()
			att["attach_kind"] = str(effect.get("kind", ""))
			att["_stacks"] = 1  # Warrior Idol: +10 now, one more +10 at the start of each of your turns
			target_champion.attached.append(att)
			g._log("%s is attached to %s." % [card.get("name", "?"), target_champion.describe()])
		"bonus_damage":
			target_champion.statuses.append({"kind": "next_attack_bonus", "amount": int(effect.get("amount", 0))})
			g._log("%s's next attack this turn does +%d damage." % [target_champion.describe(), int(effect.get("amount", 0))])
		_:
			SpellEffects.apply(g, p, hand_index, effect, target)
	g._check_win()
	return g._ok()


## target: {"champion": uid} or {"fortress": enemy_index}. The Fortress can be attacked when it is
## castled (in the active play area) or when its owner has no champions; otherwise it is immune.
## spell_picks: [{"hand_index": i, "effect_index": j}, ...] in the order they execute.
## enchant_order: indices into your enchantment list (defaults to the order they were played).
static func attack(g: Game, p: int, attacker_uid: int, attack_index: int, target: Dictionary,
		spell_picks: Array = [], enchant_order: Array = []) -> Dictionary:
	var chk: Dictionary = TurnRules.require_step(g, p, Game.Step.ATTACKED)
	if not chk.ok:
		return chk
	var me: PlayerState = g.players[p]
	var foe: PlayerState = g.players[1 - p]
	if me.is_first_turn():
		return g._fail("You cannot attack on your first turn.")
	if LockRules.is_locked(g, p, "attack"):
		return g._fail("Your attacks are locked.")
	if me.castled:
		return g._fail("Your champions are encamped and cannot attack.")

	var attacker: Champion = g._champion_of(me, attacker_uid)
	if attacker == null:
		return g._fail("Pick one of your own champions to attack with.")
	if attacker.summoned_turn == g.turn:
		return g._fail("%s was summoned this turn and cannot attack until your next turn." % attacker.card_name())
	var attacks: Array = attacker.card.get("attacks", [])
	if attack_index < 0 or attack_index >= attacks.size():
		return g._fail("Bad attack index.")
	var atk: Dictionary = attacks[attack_index]
	for st in attacker.statuses:
		if str(st.kind) == "no_attack":
			return g._fail("%s cannot attack this turn." % attacker.card_name())
	var token: int = -1
	if attacker.color() in me.colors_used:
		# Volcanic Horn: a token lets a champion other than the one that granted it attack again.
		for ti in me.extra_attacks.size():
			if int(me.extra_attacks[ti]) != attacker.uid:
				token = ti
				break
		if token < 0:
			return g._fail("You already attacked with %s this turn." % attacker.color())
	var req_err: String = _requirement_error(attacker, atk)
	if req_err != "":
		return g._fail(req_err)
	var mana_cost: int = int(atk.get("mana_cost", 0))
	if me.mana < mana_cost:
		return g._fail("Not enough banked mana (%d needed)." % mana_cost)

	var target_champion: Champion = null
	var extra_targets: Array = []
	if bool(atk.get("no_target", false)):
		target = {}  # attacks that hit every enemy champion need no target
	elif int(atk.get("multi_target", 0)) > 1 and target.has("champions"):
		if foe.castled:
			return g._fail("Encamped champions cannot be targeted.")
		var uids: Array = target.champions
		if uids.size() != mini(int(atk.multi_target), foe.champions.size()):
			return g._fail("Pick %d different enemy champions." % mini(int(atk.multi_target), foe.champions.size()))
		for uid in uids:
			var mc: Champion = g._champion_of(foe, int(uid))
			if mc == null or mc == target_champion or extra_targets.has(mc):
				return g._fail("Bad target.")
			if target_champion == null:
				target_champion = mc
			else:
				extra_targets.append(mc)
	elif target.has("champion"):
		if int(atk.get("multi_target", 0)) > 1 and foe.champions.size() >= 2 and not foe.castled:
			return g._fail("%s needs %d different targets." % [atk.get("name", "This attack"), int(atk.multi_target)])
		target_champion = g._champion_of(foe, int(target.champion))
		if target_champion == null:
			return g._fail("Target must be an enemy champion.")
		if foe.castled:
			return g._fail("Encamped champions cannot be targeted; only the Fortress can be attacked.")
	elif target.has("fortress"):
		if not foe.castled and foe.champions.size() > 0:
			return g._fail("The Fortress is immune while its owner controls a champion in the active play area.")
	elif not bool(atk.get("no_target", false)):
		return g._fail("No target given.")

	# Validate attached spells.
	var picked: Array = []   # [{card, hand_index}]
	var seen: Array = []
	# Gnome cannot be attacked by a champion with more max HP than its limit: such an attack is not allowed.
	for tc in [target_champion] + extra_targets:
		if tc != null and tc.has_ability() and tc.card.ability.has("immune_to_attackers_max_hp_over") \
				and attacker.max_hp() > int(tc.card.ability.immune_to_attackers_max_hp_over):
			return g._fail("%s cannot attack %s (it has more than %d HP)." % [attacker.card_name(), tc.card_name(), int(tc.card.ability.immune_to_attackers_max_hp_over)])
	# Duel: the champion that was dueled must attack its duelist while that champion can be targeted.
	if not bool(atk.get("no_target", false)):
		for dst in attacker.statuses:
			if str(dst.kind) == "duel":
				var duelist: Champion = g._champion_of(foe, int(dst.duelist))
				if duelist != null and not foe.castled and target_champion != duelist:
					return g._fail("%s must attack %s (Duel)." % [attacker.card_name(), duelist.card_name()])
	var spell_bonus: int = 0
	var spell_costs: int = 0
	if LockRules.is_locked(g, p, "spell") and not spell_picks.is_empty():
		return g._fail("Your spells are locked.")
	for pick in spell_picks:
		var hi: int = int(pick.get("hand_index", -1))
		var ei: int = int(pick.get("effect_index", 0))
		if hi < 0 or hi >= me.hand.size() or hi in seen:
			return g._fail("Bad spell pick.")
		var scard: Dictionary = me.hand[hi]
		if str(scard.get("kind", "")) != "spell":
			return g._fail("Only spells can be attached.")
		var seffects: Array = scard.get("effects", [])
		if ei < 0 or ei >= seffects.size():
			return g._fail("Bad spell effect index.")
		var seffect: Dictionary = seffects[ei]
		var sop: String = str(seffect.get("op", ""))
		if sop != "bonus_damage" and sop != "damage":
			return g._fail("%s cannot be attached to an attack." % scard.get("name", "That spell"))
		spell_bonus += int(seffect.get("amount", 0))
		spell_costs += int(scard.get("cost", 0))
		seen.append(hi)
		picked.append({"card": scard, "hand_index": hi})

	if me.mana < mana_cost + spell_costs:
		return g._fail("Not enough banked mana for the attack and its spells (%d needed)." % (mana_cost + spell_costs))
	# Staff Attack: an optional discard from hand for extra damage.
	var discard_card: Dictionary = {}
	var discard_bonus: int = 0
	if atk.has("optional_discard_bonus") and target.has("discard"):
		var di: int = int(target.discard)
		if di < 0 or di >= me.hand.size() or seen.has(di):
			return g._fail("Bad discard choice.")
		discard_card = me.hand[di]
		discard_bonus = int(atk.optional_discard_bonus)

	# Commit: pay, mark the color used (even if the attack fizzles), use up the spells.
	me.mana -= mana_cost + spell_costs
	me.colors_used.append(attacker.color())
	attacker.attacked_this_turn = true
	if token >= 0:
		me.extra_attacks.remove_at(token)
	var drop: Array = seen.duplicate()
	drop.sort()
	drop.reverse()
	for hi in drop:
		me.hand.remove_at(hi)
	for entry in picked:
		me.discard.append(entry.card)
	if not discard_card.is_empty():
		me.hand.erase(discard_card)
		me.discard.append(discard_card)
		g._log("P%d discards %s for +%d damage." % [p, discard_card.get("name", "a card"), discard_bonus])
	var tname: String = target_champion.describe() if target_champion != null else \
			("every enemy champion" if bool(atk.get("no_target", false)) else "P%d's Fortress" % (1 - p))
	g._log("P%d attacks %s with %s (%s)." % [p, tname, attacker.describe(), atk.get("name", "attack")])

	# Reactions resolve completely before the attack lands.
	var spell_flag: bool = (not picked.is_empty()) or g.spells_this_turn > 0
	var negated: bool = ReactionRules.run(g, p, attacker, atk, spell_flag)
	# Champion abilities that react to being attacked (damage back to the attacker) resolve before the attack lands.
	if target_champion != null and target_champion.has_ability() and not g.finished:
		var tab: Dictionary = target_champion.card.ability
		if tab.has("when_attacked_damage_attacker") and me.champions.has(attacker):
			DamageRules.damage_champion(g, attacker, int(tab.when_attacked_damage_attacker), 1 - p)
	# Enchantments that defend the Fortress (Battlements): prevent damage and hit the attacker.
	var fortress_prevent: int = 0
	if target_champion == null and not bool(atk.get("no_target", false)) and not g.finished:
		for ench in foe.enchantments:
			if typeof(ench.get("fortress_defense")) == TYPE_DICTIONARY:
				fortress_prevent += int(ench.fortress_defense.get("prevent", 0))
				if me.champions.has(attacker) and int(ench.fortress_defense.get("damage_attacker", 0)) > 0:
					g._log("%s hits the attacker." % ench.get("name", "An enchantment"))
					DamageRules.damage_champion(g, attacker, int(ench.fortress_defense.damage_attacker), 1 - p)
	# One-turn bonuses given to this champion by spells such as Battle Axe.
	for st2 in attacker.statuses.duplicate():
		if str(st2.kind) == "next_attack_bonus":
			spell_bonus += int(st2.amount)
			attacker.statuses.erase(st2)
	var target_gone: bool = target_champion != null and not foe.champions.has(target_champion)
	var attacker_gone: bool = not me.champions.has(attacker)
	if g.finished:
		return g._ok({"damage": 0, "fizzled": true})
	if negated or target_gone or attacker_gone:
		g._log("The attack fizzles. %s is still used this turn." % attacker.color())
		return g._ok({"damage": 0, "fizzled": true})

	var coins: Dictionary = AttackEffects.coin_damage(g, atk)
	if bool(coins.fizzle):
		g._log("The attack does nothing. %s is still used this turn." % attacker.color())
		return g._ok({"damage": 0, "fizzled": true})
	var extra_dmg: int = int(coins.extra) + discard_bonus
	var coin_recoil: int = int(coins.self_damage)
	var dmg: int = DamageRules.calc(g, attacker, atk, target_champion, spell_bonus, enchant_order, extra_dmg)
	for sst in attacker.statuses.duplicate():
		if str(sst.kind) == "stored_bonus":  # Grimn's saved-up Gnaw bonus is used up by the attack
			attacker.statuses.erase(sst)
	# Defensive abilities of the target champion.
	if target_champion != null and target_champion.has_ability():
		var tab2: Dictionary = target_champion.card.ability
		if tab2.has("negate_if_damage_over") and dmg > int(tab2.negate_if_damage_over):
			g._log("%s prevents the attack (it would do %d)." % [target_champion.card_name(), dmg])
			return g._ok({"damage": 0, "fizzled": true})
		if tab2.has("immune_to_attackers_max_hp_over") and attacker.max_hp() > int(tab2.immune_to_attackers_max_hp_over):
			g._log("%s cannot be damaged by a champion with over %d HP." % [target_champion.card_name(), int(tab2.immune_to_attackers_max_hp_over)])
			dmg = 0
	if target_champion != null:
		var shield: int = StatusRules.incoming_reduction(target_champion)  # Dive / Formation
		if shield > 0 and dmg > 0:
			dmg = maxi(0, dmg - shield)
			g._log("%s's defence reduces the attack by %d (%d gets through)." % [target_champion.card_name(), shield, dmg])
		DamageRules.damage_champion(g, target_champion, dmg, p)
		_when_destroyed_reaction(g, attacker, target_champion, p)
	elif not bool(atk.get("no_target", false)):
		if fortress_prevent > 0 and dmg > 0:
			dmg = maxi(0, dmg - fortress_prevent)
			g._log("Enchantments prevent %d damage to the Fortress (%d gets through)." % [fortress_prevent, dmg])
		DamageRules.damage_fortress(g, 1 - p, dmg)
	for ex in extra_targets:  # second target of Dual Spear: same attack, its own damage calculation
		if foe.champions.has(ex) and not g.finished and me.champions.has(attacker):
			var xab: Dictionary = ex.card.ability if ex.has_ability() else {}
			if xab.has("when_attacked_damage_attacker"):  # Gluto reacts to being targeted
				DamageRules.damage_champion(g, attacker, int(xab.when_attacked_damage_attacker), 1 - p)
			var d2: int = DamageRules.calc(g, attacker, atk, ex, spell_bonus, enchant_order, extra_dmg)
			d2 = _after_defences(g, attacker, ex, d2)
			if d2 >= 0:
				DamageRules.damage_champion(g, ex, d2, p)
				_when_destroyed_reaction(g, attacker, ex, p)
				if xab.has("when_hit_over_damage_attacker") and d2 > int(xab.when_hit_over_damage_attacker.over) and me.champions.has(attacker):
					DamageRules.damage_champion(g, attacker, int(xab.when_hit_over_damage_attacker.amount), 1 - p)  # Gyptjeous
	if target_champion != null and target_champion.has_ability() and me.champions.has(attacker):
		var tab3: Dictionary = target_champion.card.ability
		if tab3.has("when_hit_over_damage_attacker") and dmg > int(tab3.when_hit_over_damage_attacker.over):
			DamageRules.damage_champion(g, attacker, int(tab3.when_hit_over_damage_attacker.amount), 1 - p)
	if coin_recoil > 0 and me.champions.has(attacker) and not g.finished:  # Suproar: 10 for each tails
		DamageRules.damage_champion(g, attacker, coin_recoil, 1 - p)
	if not g.finished:
		AttackEffects.after_damage(g, p, attacker, atk, target_champion)
	g._check_win()
	return g._ok({"damage": dmg, "fizzled": false})


## Fu: "Do 30 damage to any champion that destroys Fu." Only an attacking champion that is still in play is hit.
static func _when_destroyed_reaction(g: Game, attacker: Champion, victim: Champion, p: int) -> void:
	if victim.has_ability() and victim.card.ability.has("when_destroyed_damage_attacker") \
			and not g.players[1 - p].champions.has(victim) and g.players[p].champions.has(attacker):
		g._log("%s hits back at the champion that destroyed it." % victim.card_name())
		DamageRules.damage_champion(g, attacker, int(victim.card.ability.when_destroyed_damage_attacker), 1 - p)


## Defensive abilities (Gnome, Trolls) applied to one target. Returns the damage, or -1 if the attack is prevented.
static func _after_defences(g: Game, attacker: Champion, target: Champion, dmg: int) -> int:
	dmg = maxi(0, dmg - StatusRules.incoming_reduction(target)) if dmg > 0 else dmg
	if target.has_ability():
		var ab: Dictionary = target.card.ability
		if ab.has("negate_if_damage_over") and dmg > int(ab.negate_if_damage_over):
			g._log("%s prevents the attack (it would do %d)." % [target.card_name(), dmg])
			return -1
		if ab.has("immune_to_attackers_max_hp_over") and attacker.max_hp() > int(ab.immune_to_attackers_max_hp_over):
			g._log("%s cannot be damaged by a champion with over %d HP." % [target.card_name(), int(ab.immune_to_attackers_max_hp_over)])
			return 0
	return dmg


## Attacks are standard (no cost), mana (mana_cost) or HP threshold (requires); a card never combines
## a mana cost with an HP threshold.
static func _requirement_error(attacker: Champion, atk: Dictionary) -> String:
	var req: Dictionary = atk.get("requires", {})
	if req.has("self_hp_at_most") and attacker.current_hp() > int(req.self_hp_at_most):
		return "Needs the attacker at %d HP or less." % int(req.self_hp_at_most)
	if req.has("self_hp_at_least") and attacker.current_hp() < int(req.self_hp_at_least):
		return "Needs the attacker at %d HP or more." % int(req.self_hp_at_least)
	return ""
