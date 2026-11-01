extends SceneTree
## Rules tests. Run from the project folder:
##   godot --headless --import          (first time only, builds the class cache)
##   godot --headless -s tests/test_runner.gd
## Exit code is the number of failed checks.

var cards: Dictionary       # old placeholder cards (tests/fixtures), used by the rules tests
var real: Dictionary        # the real card data in data/cards, used by the champion tests
var passed: int = 0
var failed: int = 0


func _init() -> void:
	cards = CardDB.load_cards("res://tests/fixtures/cards/")
	real = CardDB.load_cards()
	var tests: Array[Callable] = [
		test_damage_rounding,
		test_damage_order_example,
		test_setup_and_first_turns,
		test_first_turn_restrictions,
		test_fortress_triggers_after_first_turn,
		test_one_summon_per_turn,
		test_play_area_limit_and_sacrifice_on_full_board,
		test_sacrifice_color_rule_and_counters,
		test_sacrifice_count_must_match,
		test_sacrifice_carryover_lethal,
		test_class_rules,
		test_card_and_deck_files,
		test_fortress_immunity_and_opening,
		test_color_limit_and_multiple_attacks,
		test_spells_are_free_actions,
		test_attached_spell_overkill_used_up,
		test_enchantment_limit,
		test_standalone_spell_damage_and_enchantments,
		test_lock_counts_affected_players_turns,
		test_summon_lock_one_turn,
		test_self_buff_one_turn,
		test_reaction_negate_fizzles_but_color_used,
		test_reaction_destroys_attacker,
		test_reaction_spell_played_earlier_in_turn,
		test_annihilation_points,
		test_economic_victory,
		test_decking_out,
		test_pass_ends_turn,
		test_fortress_heal,
		test_simultaneous_win_is_draw,
		test_mulligan_limit,
		test_castle_basics,
		test_castle_limits,
		test_encamped_immunity_and_own_effects,
		test_poison_continues_while_encamped,
		test_start_of_turn_ability_triggers_while_encamped,
		test_encampment_limit_and_elite_while_castled,
		test_real_card_data,
		test_real_decks_build_and_play,
		test_three_slots_and_ability_only,
		test_hp_threshold_current_hp_at_least,
		test_carryover_death_scores_point,
		test_no_copy_limit,
		test_spike_sacrifices_as_any_color,
		test_coin_attacks,
		test_self_damage_and_splash,
		test_attack_bonuses,
		test_ability_damage_bonuses,
		test_defensive_abilities,
		test_reactive_abilities,
		test_passive_locks,
		test_start_of_turn_champion_abilities,
		test_protection_and_blackthorn,
		test_poison_discard_and_hand_effects,
	]
	for t in tests:
		var before_failed := failed
		t.call()
		print("%s %s" % ["ok  " if failed == before_failed else "FAIL", t.get_method()])
	print("\n%d checks passed, %d failed" % [passed, failed])
	quit(failed)


# ---------------------------------------------------------------- helpers

func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("      failed: " + label)


func card(id: String) -> Dictionary:
	return cards[id]


## A game with empty hands. By default both players are past their first turn so the first-turn
## restrictions do not get in the way; pass past_first_turns = false to test those.
func new_game(first: int = 0, past_first_turns: bool = true) -> Game:
	var filler: Array = []
	for i in 60:
		filler.append(card("ember_scout"))
	var g := Game.new()
	g.setup([filler.duplicate(), filler.duplicate()], 7, first)
	g.start()
	g.players[0].hand.clear()
	g.players[1].hand.clear()
	if past_first_turns:
		g.players[0].turns_taken = 2
		g.players[1].turns_taken = 2
	return g


## Moves the active player's turn on to the Attack step.
func to_attack(g: Game) -> void:
	g.next_step(g.active)
	g.next_step(g.active)


func custom_champion(color: String, type: String, hp: int, attacks: Array, ability: Variant = null,
		summon: Dictionary = {}) -> Dictionary:
	var c := {"id": "custom", "name": "Custom", "kind": "champion", "class": "basic", "color": color,
		"type": type, "hp": hp, "summon": summon, "attacks": attacks}
	if ability != null:
		c["ability"] = ability
	return c


# ---------------------------------------------------------------- tests

func test_damage_rounding() -> void:
	var g := new_game()
	var u := g.spawn_champion(0, custom_champion("Red", "Human", 50, [{"name": "x", "damage": 29}]))
	check(g.calc_damage(u, u.card.attacks[0], null, 0) == 20, "29 damage rounds down to 20 (2 counters)")


func test_damage_order_example() -> void:
	# 10 attack + 10 ability vs Creature + 10 spell = 30; +50% enchantment = 45 -> 40.
	var g := new_game()
	var attacker := g.spawn_champion(0, custom_champion("Red", "Human", 50, [{"name": "x", "damage": 10}],
		{"trigger": "on_attack", "bonus_damage": 10, "vs_type": "Creature"}))
	var creature := g.spawn_champion(1, custom_champion("Blue", "Creature", 90, []))
	var human := g.spawn_champion(1, custom_champion("Blue", "Human", 90, []))
	g.players[0].enchantments.append(card("war_banner"))
	check(g.calc_damage(attacker, attacker.card.attacks[0], creature, 10) == 40, "worked example from the rules = 40")
	check(g.calc_damage(attacker, attacker.card.attacks[0], human, 10) == 30, "no type bonus vs Human: 10+10=20 -> x1.5 = 30")


func test_setup_and_first_turns() -> void:
	var g := Game.new()
	var filler: Array = []
	for i in 60:
		filler.append(card("ember_scout"))
	g.setup([filler.duplicate(), filler.duplicate()], 3, 0)
	check(g.players[0].hand.size() == 7 and g.players[1].hand.size() == 7, "starting hands are 7")
	check(g.players[0].mana == 5 and g.players[1].mana == 5, "starting mana is 5")
	check(g.players[0].fortress_hp == 500, "Fortress has 500 HP")
	g.start()
	check(g.active == 0 and g.players[0].hand.size() == 8, "first player draws on their first turn")
	g.end_turn(0)
	check(g.players[0].mana == 5, "the Fortress does not trigger on a first turn")
	check(g.active == 1 and g.players[1].hand.size() == 8, "second player draws on their first turn")
	g.end_turn(1)
	check(g.players[1].mana == 5, "no Fortress mana on the second player's first turn either")
	g.next_step(0)
	check(g.players[0].mana == 6, "from their second turn the Fortress adds +1 mana")


func test_first_turn_restrictions() -> void:
	var g := new_game(0, false)
	g.players[0].hand = [card("ember_scout"), card("war_banner"), card("fire_bolt")]
	check(not g.castle(0).ok, "no castling on a first turn")
	check(g.summon(0, 0).ok, "summoning is allowed on a first turn")
	check(not g.play_enchantment(0, 0).ok, "no enchantments on a first turn")
	g.next_step(0)
	check(not g.play_spell(0, 0, 0, {"champion": g.players[0].champions[0].uid}).ok, "no spells on a first turn")
	check(not g.attack(0, g.players[0].champions[0].uid, 0, {"fortress": 1}).ok, "no attacks on a first turn")
	check(not g.fortress_heal(0, g.players[0].champions[0].uid).ok, "no Fortress heal on a first turn")


func test_fortress_triggers_after_first_turn() -> void:
	var g := new_game()
	g.next_step(0)
	check(g.players[0].mana == 6 and g.players[0].heal_pending, "Fortress adds mana and offers a heal")


func test_one_summon_per_turn() -> void:
	var g := new_game()
	g.players[0].hand = [card("ember_scout"), card("ember_scout")]
	check(g.summon(0, 0).ok, "first summon works")
	check(not g.summon(0, 0).ok, "second summon the same turn is refused")
	check(g.players[0].mana == 5, "5 + 1 Fortress - 1 cost = 5")


func test_play_area_limit_and_sacrifice_on_full_board() -> void:
	var g := new_game()
	for i in 6:
		g.spawn_champion(0, card("ember_scout"))
	g.players[0].hand = [card("ember_scout"), card("sunblade_champion")]
	check(not g.summon(0, 0).ok, "7th champion refused")
	var sac_uid := g.players[0].champions[0].uid
	check(g.summon(0, 1, [sac_uid]).ok, "sacrifice summon works on a full board")
	check(g.players[0].champions.size() == 6, "still 6 champions")


func test_sacrifice_color_rule_and_counters() -> void:
	var g := new_game()
	var r1 := g.spawn_champion(0, card("ember_scout"))
	var r2 := g.spawn_champion(0, card("ember_scout"))
	var b1 := g.spawn_champion(0, card("glass_sage"))
	r1.damage = 10
	r2.damage = 20
	g.players[0].hand = [card("cinder_tyrant"), card("sunblade_champion")]
	check(not g.summon(0, 0, [r1.uid, b1.uid]).ok, "a Red elite cannot sacrifice a Blue champion")
	check(g.summon(0, 0, [r1.uid, r2.uid]).ok, "a Red elite sacrifices two Red champions")
	var tyrant: Champion = g.players[0].champions[g.players[0].champions.size() - 1]
	var found: Champion = null
	for c in g.players[0].champions:
		if c.card_name() == "Cinder Tyrant":
			found = c
	check(found != null and found.damage == 30, "all damage counters carry over, added together (10 + 20)")
	check(g.players[0].discard.size() == 2, "both sacrificed champions go to the discard pile")
	check(g.players[1].kills == 0, "sacrificing awards no points")
	# White can sacrifice any color (new turn, so the summon is available again).
	g.end_turn(0)
	g.end_turn(1)
	check(g.summon(0, 0, [b1.uid]).ok, "a White elite can sacrifice a Blue champion")
	check(tyrant != null, "tyrant exists")


func test_sacrifice_count_must_match() -> void:
	var g := new_game()
	var r1 := g.spawn_champion(0, card("ember_scout"))
	g.players[0].hand = [card("cinder_tyrant")]
	check(not g.summon(0, 0, [r1.uid]).ok, "needs exactly 2 sacrifices")
	check(g.players[0].hand.size() == 1 and g.players[0].champions.size() == 1, "nothing was paid or sacrificed")


func test_sacrifice_carryover_lethal() -> void:
	var g := new_game()
	var weak := g.spawn_champion(0, card("ember_scout"))
	weak.damage = 20
	var elite := custom_champion("Red", "Human", 20, [{"name": "x", "damage": 10}], null, {"sacrifice": 1})
	elite["class"] = "elite"
	g.players[0].hand = [elite]
	check(g.summon(0, 0, [weak.uid]).ok, "summon resolves")
	check(g.players[0].champions.is_empty(), "carried damage >= HP destroys the new champion")
	check(g.players[1].kills == 1, "a carry-over death scores an Annihilation point for the opponent")
	check(g.players[0].summoned_this_turn, "the summon was still used up")


func test_class_rules() -> void:
	check(CardDB.expected_class({"summon": {}}) == "basic", "no sacrifice and no mana = basic")
	check(CardDB.expected_class({"summon": {"mana": 1}}) == "elite", "a mana cost = elite")
	check(CardDB.expected_class({"summon": {"sacrifice": 1}}) == "elite", "one sacrifice = elite")
	check(CardDB.expected_class({"summon": {"sacrifice": 2, "mana": 1}}) == "elite", "sacrifices and mana = elite")
	for id in cards:
		var c: Dictionary = cards[id]
		if str(c.kind) != "champion":
			check(not c.has("class"), "%s: only champions have a class" % id)
			continue
		check(str(c.get("class", "")) == CardDB.expected_class(c), "%s: class matches the basic/elite rule" % id)
		check(not c.summon.has("discard_min"), "%s: no discard-pile summon requirement" % id)
		for atk in c.attacks:
			check(not (int(atk.get("mana_cost", 0)) > 0 and atk.has("requires")), "%s: no attack combines mana and HP threshold" % id)


func test_card_and_deck_files() -> void:
	check(cards.size() == 24, "all 24 fixture cards load from the six files (got %d)" % cards.size())
	var colors := {"red": "Red", "blue": "Blue", "white": "White", "purple": "Purple"}
	for file_name in colors:
		var parsed: Variant = CardDB._read_json("res://tests/fixtures/cards/%s.json" % file_name)
		var all_match := true
		for c in parsed:
			if str(c.kind) != "champion" or str(c.color) != colors[file_name]:
				all_match = false
		check(all_match, "%s.json holds only %s champions" % [file_name, colors[file_name]])
	var decks := CardDB.load_decks("res://tests/fixtures/decks.json")
	for deck_name in decks:
		var total := 0
		for id in decks[deck_name]:
			total += int(decks[deck_name][id])
		check(total == 60, "%s has 60 cards (got %d)" % [deck_name, total])


func test_fortress_immunity_and_opening() -> void:
	var g := new_game()
	var mine := g.spawn_champion(0, card("ember_scout"))
	var theirs := g.spawn_champion(1, card("glass_sage"))
	theirs.damage = 20
	to_attack(g)
	check(not g.attack(0, mine.uid, 0, {"fortress": 1}).ok, "Fortress immune while the owner has a champion in the active play area")
	var r := g.attack(0, mine.uid, 0, {"champion": theirs.uid})
	check(r.ok and g.players[1].champions.is_empty(), "attack destroys the last champion")
	var blue := g.spawn_champion(0, card("rune_adept"))
	var r2 := g.attack(0, blue.uid, 0, {"fortress": 1})
	check(r2.ok and g.players[1].fortress_hp == 480, "Fortress takes 20 right after the last champion dies")


func test_color_limit_and_multiple_attacks() -> void:
	var g := new_game()
	var a := g.spawn_champion(0, card("ember_scout"))
	var b := g.spawn_champion(0, card("ash_duelist"))
	var c := g.spawn_champion(0, card("rune_adept"))
	var enemy := g.spawn_champion(1, card("cinder_tyrant"))
	to_attack(g)
	check(g.attack(0, a.uid, 0, {"champion": enemy.uid}).ok, "first Red attack works")
	check(not g.attack(0, b.uid, 0, {"champion": enemy.uid}).ok, "second Red attack the same turn is refused")
	check(g.attack(0, c.uid, 0, {"champion": enemy.uid}).ok, "a different color can still attack the same turn")


func test_spells_are_free_actions() -> void:
	var g := new_game()
	var mine := g.spawn_champion(0, card("ember_scout"))
	mine.damage = 20
	var foe := g.spawn_champion(1, card("tide_guard"))
	g.players[0].hand = [card("mend"), card("mend"), card("mend")]
	g.players[1].hand = [card("mend")]
	to_attack(g)
	check(g.play_spell(0, 0, 0, {"champion": mine.uid}).ok, "spell before acting")
	check(mine.damage == 0, "Mend healed 20")
	check(g.play_spell(0, 0, 0, {"champion": mine.uid}).ok, "a second spell")
	check(g.attack(0, mine.uid, 0, {"champion": foe.uid}).ok, "attack after spells")
	check(g.play_spell(0, 0, 0, {"champion": mine.uid}).ok, "spell after the attack")
	check(not g.play_spell(1, 0, 0, {"champion": foe.uid}).ok, "cannot cast on the opponent's turn")
	var g2 := new_game()
	var m2 := g2.spawn_champion(0, card("ember_scout"))
	g2.players[0].hand = [card("mend")]
	to_attack(g2)
	check(g2.play_spell(0, 0, 0, {"champion": m2.uid}).ok and g2.pass_action(0).ok, "spells then pass is allowed")
	check(g2.active == 1, "passing ends the turn")


func test_attached_spell_overkill_used_up() -> void:
	var g := new_game()
	var attacker := g.spawn_champion(0, card("ember_scout"))
	var target := g.spawn_champion(1, card("glass_sage"))
	target.damage = 20  # 10 HP left
	g.players[0].hand = [card("fire_bolt")]
	to_attack(g)
	var r := g.attack(0, attacker.uid, 0, {"champion": target.uid}, [{"hand_index": 0, "effect_index": 1}])
	check(r.ok and r.damage == 20, "10 attack + 10 spell = 20 against 10 HP")
	check(g.players[0].hand.is_empty() and g.players[0].discard.size() == 1, "spell is used up despite overkill")
	check(g.players[1].champions.is_empty(), "target destroyed")


func test_enchantment_limit() -> void:
	var g := new_game()
	g.players[0].mana = 99
	for i in 6:
		g.players[0].hand.append(card("war_banner"))
	var oks := 0
	for i in 6:
		if g.play_enchantment(0, 0).ok:
			oks += 1
	check(oks == 5, "only 5 enchantments allowed")


func test_standalone_spell_damage_and_enchantments() -> void:
	var g := new_game()
	g.spawn_champion(1, custom_champion("Blue", "Human", 90, []))
	g.players[0].enchantments.append(card("war_banner"))
	g.players[0].hand = [card("fire_bolt"), card("fire_bolt")]
	to_attack(g)
	var target := g.players[1].champions[0]
	g.play_spell(0, 0, 0, {"champion": target.uid})
	check(target.damage == 20, "War Banner does not boost standalone spell damage")
	g.players[0].enchantments.append(card("spellfire_sigil"))
	g.play_spell(0, 0, 0, {"champion": target.uid})
	check(target.damage == 50, "Spellfire Sigil does: 20 x1.5 = 30")


func test_lock_counts_affected_players_turns() -> void:
	# A 5-turn enchantment lock stops the opponent for 5 of THEIR turns, starting with their next turn.
	var g := new_game()
	g.players[0].hand = [card("binding_seal")]
	g.players[1].hand = []
	for i in 8:
		g.players[1].hand.append(card("war_banner"))
	g.players[1].mana = 15  # stays well below the Economic Victory threshold of 30
	to_attack(g)
	check(g.play_spell(0, 0, 0).ok, "Binding Seal (lock enchantments for 5 turns)")
	for k in 5:
		g.end_turn(0)
		check(not g.play_enchantment(1, 0).ok, "opponent is locked on their turn %d" % (k + 1))
		g.end_turn(1)
	g.end_turn(0)
	check(g.play_enchantment(1, 0).ok, "opponent is free again on their 6th turn")
	check(not g._is_locked(0, "enchantment"), "the caster was never locked")


func test_summon_lock_one_turn() -> void:
	var g := new_game()
	g.players[0].hand = [card("stillness")]
	g.players[1].hand = [card("ember_scout"), card("ember_scout")]
	to_attack(g)
	check(g.play_spell(0, 0, 0).ok, "Stillness (opponent cannot summon for 1 turn)")
	g.end_turn(0)
	check(not g.summon(1, 0).ok, "they cannot summon on their next turn")
	g.end_turn(1)
	g.end_turn(0)
	check(g.summon(1, 0).ok, "the effect wore off when their turn ended")


func test_self_buff_one_turn() -> void:
	var g := new_game()
	var mine := g.spawn_champion(0, card("ember_scout"))
	var foe := g.spawn_champion(1, card("tide_guard"))
	g.players[0].hand = [card("battle_cry")]
	to_attack(g)
	g.play_spell(0, 0, 0)
	var r := g.attack(0, mine.uid, 0, {"champion": foe.uid})
	check(r.ok and r.damage == 20, "+10 buff applies on the turn it is played (10 + 10)")
	g.end_turn(0)
	g.end_turn(1)
	to_attack(g)
	var r2 := g.attack(0, mine.uid, 0, {"champion": foe.uid})
	check(r2.ok and r2.damage == 10, "the one-turn buff is gone on their next turn")


func test_reaction_negate_fizzles_but_color_used() -> void:
	var g := new_game()
	var red := g.spawn_champion(0, card("ember_scout"))
	var foe := g.spawn_champion(1, card("tide_guard"))
	g.players[1].enchantments.append(card("ward_of_reprisal"))
	to_attack(g)
	var r := g.attack(0, red.uid, 0, {"champion": foe.uid})
	check(r.ok and r.fizzled and foe.damage == 0, "Ward negates the Red attack")
	check("Red" in g.players[0].colors_used, "Red still counts as used")
	check(g.players[1].enchantments.is_empty(), "one-shot Ward went to the discard pile")


func test_reaction_destroys_attacker() -> void:
	var g := new_game()
	var scout := g.spawn_champion(0, card("ember_scout"))
	scout.damage = 20  # 10 HP left
	var foe := g.spawn_champion(1, card("tide_guard"))
	g.players[1].enchantments.append(card("thorn_aura"))
	to_attack(g)
	var r := g.attack(0, scout.uid, 0, {"champion": foe.uid})
	check(r.fizzled and foe.damage == 0, "attacker destroyed by the reaction -> attack fizzles")
	check(g.players[1].kills == 1, "Annihilation point for the reaction kill")


func test_reaction_spell_played_earlier_in_turn() -> void:
	var g := new_game()
	var attacker := g.spawn_champion(0, card("ember_scout"))
	var foe := g.spawn_champion(1, card("tide_guard"))
	g.players[0].hand = [card("mend")]
	var punish := {"id": "t", "name": "Spell Punisher", "kind": "enchantment", "cost": 0,
		"reaction": {"when": {"spell_with_attack": true}, "effect": {"op": "negate_attack"}}}
	g.players[1].enchantments.append(punish)
	to_attack(g)
	g.play_spell(0, 0, 0, {"champion": attacker.uid})
	var r := g.attack(0, attacker.uid, 0, {"champion": foe.uid})
	check(r.fizzled, "a spell cast earlier in the turn counts as 'spell with the attack'")


func test_annihilation_points() -> void:
	var g := new_game()
	var a := g.spawn_champion(0, card("ember_scout"))
	var weak := g.spawn_champion(1, card("glass_sage"))
	weak.damage = 20
	to_attack(g)
	g.attack(0, a.uid, 0, {"champion": weak.uid})
	check(g.players[0].kills == 1, "enemy attack kill = 1 point")
	var g2 := new_game()
	g2.players[0].kills = 9
	var x := g2.spawn_champion(0, card("ember_scout"))
	var y := g2.spawn_champion(1, card("glass_sage"))
	y.damage = 20
	to_attack(g2)
	g2.attack(0, x.uid, 0, {"champion": y.uid})
	check(g2.finished and g2.winner == 0, "10th point wins by Annihilation")


func test_economic_victory() -> void:
	var g := Game.new()
	var filler: Array = []
	for i in 60:
		filler.append(card("ember_scout"))
	g.setup([filler.duplicate(), filler.duplicate()], 5, 0)
	g.players[0].mana = 30
	g.start()
	check(g.finished and g.winner == 0 and g.win_reason == "Economic Victory", "30 mana at the start of your turn wins")


func test_decking_out() -> void:
	var g := new_game()
	g.players[1].deck.clear()
	g.end_turn(0)
	check(g.finished and g.winner == 0 and g.win_reason == "Decking out", "empty deck on draw loses")


func test_pass_ends_turn() -> void:
	var g := new_game(0)
	var turn_before := g.turn
	g.pass_action(0)
	check(g.active == 1 and g.turn == turn_before + 1, "passing ends the turn and the other player goes")
	check(g.players[0].mana == 6, "the Fortress still triggered on a turn that was passed straight away")


func test_fortress_heal() -> void:
	var g := new_game()
	var u := g.spawn_champion(0, card("tide_guard"))
	u.damage = 30
	check(g.fortress_heal(0, u.uid).ok and u.damage == 10, "Fortress heals 20")
	check(not g.fortress_heal(0, u.uid).ok, "only once per turn")


func test_simultaneous_win_is_draw() -> void:
	var g := new_game()
	g.players[0].fortress_hp = 0
	g.players[1].fortress_hp = 0
	g._check_win()
	check(g.finished and g.winner == 2, "both Fortresses at 0 -> draw")


func test_mulligan_limit() -> void:
	var f := Game.new()
	var filler: Array = []
	for i in 60:
		filler.append(card("ember_scout"))
	f.setup([filler.duplicate(), filler.duplicate()], 9, 0)
	check(f.mulligan(0).ok and f.mulligan(0).ok, "two mulligans allowed")
	check(not f.mulligan(0).ok, "third hand must be kept")
	check(f.players[0].hand.size() == 7, "hand size stays 7")


# ---------------------------------------------------------------- castling

func test_castle_basics() -> void:
	var g := new_game()
	var mine := g.spawn_champion(0, card("ember_scout"))
	g.spawn_champion(1, card("tide_guard"))
	g.players[0].hand = [card("ember_scout")]
	check(g.castle(0).ok, "castle at the start of the turn")
	check(g.players[0].active_champions().is_empty() and g.players[0].encamped_champions().size() == 1, "champions are encamped")
	g.next_step(0)
	check(g.players[0].mana == 6, "the Fortress still triggers while castled")
	check(g.summon(0, 0).ok and g.players[0].encamped_champions().size() == 2, "a champion summoned while castled is encamped")
	g.next_step(0)
	check(not g.attack(0, mine.uid, 0, {"fortress": 1}).ok, "encamped champions cannot attack")
	g.end_turn(0)
	# The opponent's turn: only the Fortress can be attacked, even though champions are encamped.
	var enemy := g.players[1].champions[0]
	to_attack(g)
	var mine_enc: Champion = g.players[0].champions[0]
	check(not g.attack(1, enemy.uid, 0, {"champion": mine_enc.uid}).ok, "encamped champions cannot be attacked")
	var r := g.attack(1, enemy.uid, 0, {"fortress": 0})
	check(r.ok and g.players[0].fortress_hp < 500, "the castled Fortress can be attacked despite encamped champions")


func test_castle_limits() -> void:
	var g := new_game()
	g.spawn_champion(0, card("ember_scout"))
	check(g.castle(0).ok, "castle on turn A")
	g.end_turn(0)
	g.end_turn(1)
	check(g.players[0].castled, "still castled on A+1")
	g.end_turn(0)
	g.end_turn(1)
	check(g.players[0].castled, "still castled on A+2 (3 own turns castled)")
	g.end_turn(0)
	var log_start := g.log_lines.size()
	g.end_turn(1)
	# Now P0's turn A+3 has begun: forced uncastle before the draw.
	var lines: Array = g.log_lines.slice(log_start)
	var idx_switch := -1
	var idx_draw := -1
	for i in lines.size():
		if "castle has run out" in lines[i] and idx_switch < 0:
			idx_switch = i
		if "P0 draws a card" in lines[i] and idx_draw < 0:
			idx_draw = i
	check(not g.players[0].castled, "the castle ran out and the Fortress switched back")
	check(idx_switch >= 0 and idx_draw > idx_switch, "the switch happens before the draw")
	check(not g.castle(0).ok, "castling is only allowed once per game")
	# Uncastling early also uses up the one castle.
	var g2 := new_game()
	g2.spawn_champion(0, card("ember_scout"))
	g2.castle(0)
	g2.end_turn(0)
	g2.end_turn(1)
	check(g2.uncastle(0).ok and not g2.players[0].castled, "uncastle early")
	check(not g2.castle(0).ok, "the one castle is gone")


func test_encamped_immunity_and_own_effects() -> void:
	var g := new_game()
	var mine := g.spawn_champion(0, card("ember_scout"))
	var safe := g.spawn_champion(1, card("tide_guard"))
	safe.damage = 30
	g.players[1].castled = true
	g.players[1].castles_used = 1
	g.players[1].castled_turns = 1
	g.players[0].hand = [card("fire_bolt"), card("venom_dart")]
	g.players[1].hand = [card("mend")]
	to_attack(g)
	check(not g.attack(0, mine.uid, 0, {"champion": safe.uid}).ok, "attacks cannot target encamped champions")
	check(not g.play_spell(0, 0, 0, {"champion": safe.uid}).ok, "damage spells cannot target encamped champions")
	check(not g.play_spell(0, 1, 0, {"champion": safe.uid}).ok, "poison cannot target encamped champions")
	g.end_turn(0)
	# Their own effects still work on encamped champions: the Fortress heal and their own spells.
	g.next_step(1)
	check(g.fortress_heal(1, safe.uid).ok and safe.damage == 10, "own Fortress heal works on an encamped champion")
	g.next_step(1)
	check(g.play_spell(1, 0, 0, {"champion": safe.uid}).ok and safe.damage == 0, "own heal spell works on an encamped champion")
	check(g.players[1].enchantments.is_empty(), "(no enchantments involved)")


func test_poison_continues_while_encamped() -> void:
	var g := new_game()
	g.spawn_champion(0, card("ember_scout"))
	var victim := g.spawn_champion(1, custom_champion("Blue", "Human", 20, [{"name": "x", "damage": 10}]))
	g.players[0].hand = [card("venom_dart")]
	to_attack(g)
	check(g.play_spell(0, 0, 0, {"champion": victim.uid}).ok, "poison an enemy champion that is in the active play area")
	g.end_turn(0)
	check(g.castle(1).ok, "the victim's owner castles")
	g.next_step(1)
	check(victim.damage == 10, "poison keeps ticking while the champion is encamped")
	g.end_turn(1)
	g.end_turn(0)
	g.next_step(1)
	check(g.players[1].champions.is_empty(), "poison destroys the encamped champion")
	check(g.players[0].kills == 1, "the opponent scores an Annihilation point for the poison kill")


func test_start_of_turn_ability_triggers_while_encamped() -> void:
	var g := new_game()
	var ability := {"trigger": "start_of_turn", "op": "gain_mana", "amount": 1}
	g.spawn_champion(0, custom_champion("Red", "Human", 30, [{"name": "x", "damage": 10}], ability))
	g.castle(0)
	g.next_step(0)
	check(g.players[0].mana == 7, "5 + 1 Fortress + 1 ability, even though the champion is encamped")
	# A champion summoned this turn does not trigger until the owner's next turn.
	var g2 := new_game()
	g2.players[0].hand = [custom_champion("Red", "Human", 30, [{"name": "x", "damage": 10}], ability)]
	g2.summon(0, 0)
	check(g2.players[0].mana == 6, "no ability trigger on the turn it was summoned")
	g2.end_turn(0)
	g2.end_turn(1)
	g2.next_step(0)
	check(g2.players[0].mana == 8, "it triggers on the owner's next turn (6 + 1 Fortress + 1 ability)")


func test_encampment_limit_and_elite_while_castled() -> void:
	var g := new_game()
	for i in 6:
		g.spawn_champion(0, card("ember_scout"))
	g.castle(0)
	g.players[0].hand = [card("ember_scout"), card("sunblade_champion")]
	check(not g.summon(0, 0).ok, "the encampment area holds 6 champions, like the active play area")
	var sac := g.players[0].champions[0].uid
	check(g.summon(0, 1, [sac]).ok, "a castled player can sacrifice encamped champions to summon an elite")
	check(g.players[0].encamped_champions().size() == 6, "the elite is placed in the encampment area")


# ---------------------------------------------------------------- real card data and champion abilities

func rc(id: String) -> Dictionary:
	return real[id]


## A game between two players with 60 real champions each; hands emptied, past first turns.
func real_game(first: int = 0) -> Game:
	var filler: Array = []
	for i in 60:
		filler.append(rc("syranite"))
	var g := Game.new()
	g.setup([filler.duplicate(), filler.duplicate()], 7, first)
	g.start()
	g.players[0].hand.clear()
	g.players[1].hand.clear()
	g.players[0].turns_taken = 2
	g.players[1].turns_taken = 2
	return g


func spawn(g: Game, p: int, id: String) -> Champion:
	return g.spawn_champion(p, rc(id))


func test_real_card_data() -> void:
	var champions := 0
	var by_color := {"Red": 0, "Blue": 0, "White": 0, "Purple": 0}
	for id in real:
		var c: Dictionary = real[id]
		if str(c.kind) != "champion":
			continue
		champions += 1
		by_color[c.color] += 1
		check(str(c.class) == CardDB.expected_class(c), "%s: class matches the basic/elite rule" % id)
		check(c.attacks.size() <= 2, "%s: at most 2 attacks" % id)
		check(c.attacks.size() + (1 if c.has("ability") else 0) >= 1, "%s: has an attack or an ability" % id)
		check(int(c.hp) % 10 == 0, "%s: HP is a multiple of 10" % id)
		for atk in c.attacks:
			check(not (atk.has("mana_cost") and atk.has("requires")), "%s: %s does not mix mana and an HP threshold" % [id, atk.name])
	check(champions == 55, "55 champions load (got %d)" % champions)
	check(by_color == {"Red": 15, "Blue": 14, "White": 13, "Purple": 13}, "champions per color: %s" % str(by_color))
	check(rc("mersoilder").attacks[1].mana_cost == 2 and rc("mersoilder").attacks[1].coin_bonus == 20, "Mersoilder's Engage costs 2 mana and has a 20 coin bonus")
	check(rc("harmlobeast").attacks.is_empty() and rc("harmlobeast").has("ability"), "Harmlobeast has an ability and no attack")
	check(rc("stanter").attacks[1].requires.self_hp_at_least == 70, "Stanter's Divine Wind needs 70 HP")
	check(rc("amustas").summon.sacrifice == 3, "Amustas needs 3 sacrifices")
	var decks := CardDB.load_decks()
	for deck_name in decks:
		var total := 0
		for id in decks[deck_name]:
			total += int(decks[deck_name][id])
			check(real.has(id), "%s: card %s exists" % [deck_name, id])
		check(total == 60, "%s has 60 cards (got %d)" % [deck_name, total])


func test_real_decks_build_and_play() -> void:
	var decks := CardDB.load_decks()
	var names: Array = decks.keys()
	var g := Game.new()
	g.setup([CardDB.build_deck(real, decks[names[0]]), CardDB.build_deck(real, decks[names[1]])], 11, 0)
	g.start()
	for i in 60:
		if g.finished:
			break
		SimpleBot.take_turn(g, g.active)
	check(g.finished or g.turn > 20, "a bot game on the real decks runs without stalling")


func test_three_slots_and_ability_only() -> void:
	var g := real_game()
	var w := spawn(g, 0, "warlord")
	check(w.card.attacks.size() == 2 and w.has_ability(), "Warlord holds an ability and two attacks")
	var h := spawn(g, 0, "harmlobeast")
	var enemy := spawn(g, 1, "gob")
	to_attack(g)
	check(not g.attack(0, h.uid, 0, {"champion": enemy.uid}).ok, "an ability-only champion has no attack to use")
	g.players[0].mana = 2
	check(g.attack(0, w.uid, 1, {"champion": enemy.uid}).ok, "Warlord can use its second attack (Molten Fury, 2 mana)")
	check(enemy.card_name() == "Gob" and g.players[1].champions.is_empty(), "80 damage destroys Gob")


func test_hp_threshold_current_hp_at_least() -> void:
	var g := real_game()
	var raider := spawn(g, 0, "dark_raider")  # Mace needs 40 current HP, 60 max
	var enemy := spawn(g, 1, "amustas")
	to_attack(g)
	check(g.attack(0, raider.uid, 0, {"champion": enemy.uid}).ok, "Dark Raider can attack while at full HP")
	var g2 := real_game()
	var raider2 := spawn(g2, 0, "dark_raider")
	raider2.damage = 30  # 30 HP left, below the 40 needed
	var enemy2 := spawn(g2, 1, "amustas")
	to_attack(g2)
	check(not g2.attack(0, raider2.uid, 0, {"champion": enemy2.uid}).ok, "Dark Raider loses its attack below 40 HP")
	raider2.damage = 20  # exactly 40 HP
	check(g2.attack(0, raider2.uid, 0, {"champion": enemy2.uid}).ok, "Dark Raider can attack at exactly 40 HP")
	var g3 := real_game()
	var st := spawn(g3, 0, "stanter")
	var foe3 := spawn(g3, 1, "amustas")
	st.damage = 10
	to_attack(g3)
	check(not g3.attack(0, st.uid, 1, {"champion": foe3.uid}).ok, "Stanter's Divine Wind needs full HP (70 of 70)")


func test_carryover_death_scores_point() -> void:
	var g := real_game()
	var a := spawn(g, 0, "syranite")
	a.damage = 50
	g.players[0].hand = [rc("war_bear")]  # elite needing 1 sacrifice, 80 HP; damage 50 does not kill it
	check(g.summon(0, 0, [a.uid]).ok, "sacrifice summon resolves")
	var g2 := real_game()
	var b := spawn(g2, 0, "syranite")
	b.damage = 50
	var small := rc("war_bear").duplicate(true)
	small["hp"] = 50
	g2.players[0].hand = [small]
	check(g2.summon(0, 0, [b.uid]).ok and g2.players[0].champions.is_empty(), "carried damage destroys the new champion")
	check(g2.players[1].kills == 1, "the opponent scores an Annihilation point for the carry-over death")


func test_no_copy_limit() -> void:
	var spec := {"syranite": 20, "gob": 40}
	var deck := CardDB.build_deck(real, spec)
	check(deck.size() == 60, "a deck may hold more than 4 copies of a card (got %d cards)" % deck.size())


func test_spike_sacrifices_as_any_color() -> void:
	var g := real_game()
	var spike := spawn(g, 0, "spike")  # White
	g.players[0].hand = [rc("tigrodon").duplicate(true)]  # White: any color anyway
	var red_elite := rc("battlement_guard")  # Red, needs 1 sacrifice of Red
	g.players[0].hand = [red_elite]
	check(g.summon(0, 0, [spike.uid]).ok, "Spike can be sacrificed for a Red champion")
	var g2 := real_game()
	var pog := spawn(g2, 0, "pog")  # White, no special ability
	g2.players[0].hand = [rc("battlement_guard")]
	check(not g2.summon(0, 0, [pog.uid]).ok, "a normal White champion cannot be sacrificed for Red")


func test_coin_attacks() -> void:
	var g := real_game()
	var bear := spawn(g, 0, "war_bear")
	var target := spawn(g, 1, "amustas")
	g.forced_coins = [true, false, true]
	to_attack(g)
	g.players[0].mana = 1  # set after the Fortress has given its mana
	var r := g.attack(0, bear.uid, 1, {"champion": target.uid})
	check(r.ok and r.damage == 40 and target.damage == 40, "Double Claw: 2 Heads of 3 coins = 40 damage")
	check(g.players[0].mana == 0, "Double Claw cost 1 mana")
	var g2 := real_game()
	var mer := spawn(g2, 0, "mersoilder")
	var t2 := spawn(g2, 1, "amustas")
	g2.players[0].mana = 2
	g2.forced_coins = [true]
	to_attack(g2)
	check(g2.attack(0, mer.uid, 1, {"champion": t2.uid}).damage == 40, "Engage: 20 + 20 on Heads")
	var g3 := real_game()
	var mer3 := spawn(g3, 0, "mersoilder")
	var t3 := spawn(g3, 1, "amustas")
	g3.players[0].mana = 2
	g3.forced_coins = [false]
	to_attack(g3)
	check(g3.attack(0, mer3.uid, 1, {"champion": t3.uid}).damage == 20, "Engage: 20 on Tails")
	var g4 := real_game()
	var cw := spawn(g4, 0, "cwelen")
	var t4 := spawn(g4, 1, "amustas")
	g4.forced_coins = [true]
	to_attack(g4)
	var r4 := g4.attack(0, cw.uid, 1, {"champion": t4.uid})
	check(r4.fizzled and t4.damage == 0, "Risky Move on Heads does nothing")
	check(g4.players[0].colors_used.has("Red"), "Risky Move still uses the color")
	var g5 := real_game()
	var sa := spawn(g5, 0, "saisen")
	var t5 := spawn(g5, 1, "amustas")
	g5.forced_coins = [true, true, true]
	to_attack(g5)
	check(g5.attack(0, sa.uid, 0, {"champion": t5.uid}).damage == 30, "Death Stars: 3 Heads = 30")
	var g6 := real_game()
	var sub := spawn(g6, 0, "suburn")
	var t6 := spawn(g6, 1, "amustas")
	g6.forced_coins = [true]
	to_attack(g6)
	check(g6.attack(0, sub.uid, 0, {"champion": t6.uid}).damage == 30, "Air Claw: 10 + 20 on Heads")
	var g7 := real_game()
	var cape := spawn(g7, 0, "capeasant")
	var e1 := spawn(g7, 1, "amustas")
	var e2 := spawn(g7, 1, "gob")
	var e3 := spawn(g7, 1, "fu")
	g7.players[0].mana = 1
	g7.forced_coins = [true, false, true]
	to_attack(g7)
	check(g7.attack(0, cape.uid, 0, {}).ok, "Revolt needs no target")
	check(e1.damage == 10 and e2.damage == 0 and e3.damage == 10, "Revolt: 10 damage to each champion whose coin is Heads")


func test_self_damage_and_splash() -> void:
	var g := real_game()
	var joseph := spawn(g, 0, "joseph_the_knight")
	var t := spawn(g, 1, "amustas")
	g.players[0].mana = 1
	to_attack(g)
	g.attack(0, joseph.uid, 1, {"champion": t.uid})
	check(t.damage == 70 and joseph.damage == 20, "Honourable Task: 70 damage and 20 to itself")
	var g2 := real_game()
	var lava := spawn(g2, 0, "lava_titan")
	var t2 := spawn(g2, 1, "amustas")
	to_attack(g2)
	g2.attack(0, lava.uid, 0, {"champion": t2.uid})
	check(t2.damage == 30 and lava.damage == 10, "Eruption: 30 damage, 10 to itself")
	var g3 := real_game()
	var gronk := spawn(g3, 0, "gronk")
	var e1 := spawn(g3, 1, "amustas")
	var e2 := spawn(g3, 1, "amustas")
	g3.players[0].mana = 2
	to_attack(g3)
	g3.attack(0, gronk.uid, 1, {"champion": e1.uid})
	check(e1.damage == 50 and e2.damage == 20, "Path of Destruction: 50 to the target and 20 to every other enemy champion")
	var g4 := real_game()
	var td := spawn(g4, 0, "tree_dragon")
	var own := spawn(g4, 0, "pog")
	var f1 := spawn(g4, 1, "amustas")
	var f2 := spawn(g4, 1, "amustas")
	to_attack(g4)
	g4.attack(0, td.uid, 1, {"champion": f1.uid})
	check(f1.damage == 80 and f2.damage == 10 and own.damage == 10 and td.damage == 0, "Burnout: 70 to the target and 10 to every champion including your own, but not Tree Dragon itself")
	var g5 := real_game()
	var tig := spawn(g5, 0, "tigrodon")
	tig.damage = 100
	var t5 := spawn(g5, 1, "amustas")
	g5.players[0].mana = 2
	to_attack(g5)
	g5.attack(0, tig.uid, 1, {"champion": t5.uid})
	check(g5.players[0].champions.is_empty() and g5.players[1].kills == 1, "a champion destroyed by its own recoil scores a point for the opponent")
	var g6 := real_game()
	var psy := spawn(g6, 0, "psyville")
	var h1 := spawn(g6, 1, "amustas")
	var h2 := spawn(g6, 1, "amustas")
	to_attack(g6)
	check(g6.attack(0, psy.uid, 0, {}).ok and h1.damage == 10 and h2.damage == 10, "Trident: 10 damage to each enemy champion")


func test_attack_bonuses() -> void:
	var g := real_game()
	var gronk := spawn(g, 0, "gronk")
	var basic := spawn(g, 1, "gob")
	var elite := spawn(g, 1, "amustas")
	to_attack(g)
	check(g.attack(0, gronk.uid, 0, {"champion": basic.uid}).damage == 40, "Devour: +20 against basic champions")
	var g2 := real_game()
	var gronk2 := spawn(g2, 0, "gronk")
	var elite2 := spawn(g2, 1, "amustas")
	to_attack(g2)
	check(g2.attack(0, gronk2.uid, 0, {"champion": elite2.uid}).damage == 20, "Devour: no bonus against elite champions")
	var g3 := real_game()
	var pk := spawn(g3, 0, "pumpkin_knight")
	var creature := spawn(g3, 1, "amustas")
	to_attack(g3)
	check(g3.attack(0, pk.uid, 0, {"champion": creature.uid}).damage == 40, "Slay: +30 against creatures")
	var g4 := real_game()
	var psybar := spawn(g4, 0, "psybar")
	g4.players[0].enchantments = [{"name": "a"}, {"name": "b"}]
	var t4 := spawn(g4, 1, "amustas")
	g4.players[0].mana = 1
	to_attack(g4)
	check(g4.attack(0, psybar.uid, 1 - 1, {"champion": t4.uid}).ok, "Psybar attacks")
	check(t4.damage == 30, "Demonic: 10 + 10 per enchantment in play (got %d)" % t4.damage)
	var g5 := real_game()
	var gc := spawn(g5, 0, "the_magician_gcairo")
	var t5 := spawn(g5, 1, "amustas")
	g5.players[1].hand = [rc("syranite"), rc("syranite"), rc("syranite")]
	to_attack(g5)
	check(g5.attack(0, gc.uid, 0, {"champion": t5.uid}).damage == 30, "Surprise Attack: 10 per card in the opponent's hand")
	var g6 := real_game()
	var sk := spawn(g6, 0, "skullmort")
	var t6 := spawn(g6, 1, "amustas")
	g6.players[0].discard = [rc("syranite"), rc("syranite"), rc("fire_bolt")]
	to_attack(g6)
	check(g6.attack(0, sk.uid, 0, {"champion": t6.uid}).damage == 20, "Army of the Dead: 10 per champion card in your discard pile")


func test_ability_damage_bonuses() -> void:
	var g := real_game()
	var marcos := spawn(g, 0, "marcos_the_gladiator")
	spawn(g, 0, "pog")
	spawn(g, 0, "gob")
	var t := spawn(g, 1, "amustas")
	to_attack(g)
	check(g.attack(0, marcos.uid, 0, {"champion": t.uid}).damage == 40, "Marcos: 20 + 10 per other active champion (2), himself not counted")
	var g2 := real_game()
	var pt := spawn(g2, 0, "psytwist")
	spawn(g2, 0, "hypnotwist")
	spawn(g2, 1, "maragret")
	var t2 := spawn(g2, 1, "amustas")
	to_attack(g2)
	check(g2.attack(0, pt.uid, 0, {"champion": t2.uid}).damage == 40, "Psytwist: 20 + 10 per other Spirit in play, both sides (2), itself not counted")
	var g3 := real_game()
	var ht := spawn(g3, 0, "hypnotwist")
	spawn(g3, 0, "amustas")  # a Creature, not a Spirit
	spawn(g3, 0, "misley")
	spawn(g3, 1, "maragret")
	var t3 := spawn(g3, 1, "amustas")
	to_attack(g3)
	check(g3.attack(0, ht.uid, 0, {"champion": t3.uid}).damage == 20, "Hypnotwist: 10 + 10 per other own Spirit (1), itself and enemy Spirits not counted")
	var g4 := real_game()
	var lt := spawn(g4, 0, "lava_titan")
	lt.damage = 100
	var t4 := spawn(g4, 1, "amustas")
	to_attack(g4)
	g4.attack(0, lt.uid, 0, {"champion": t4.uid})
	check(t4.damage == 50, "Lava Titan: 30 + 10 per 5 damage counters (10 counters = +20)")


func test_defensive_abilities() -> void:
	var g := real_game()
	var gnome := spawn(g, 1, "gnome")
	var big := spawn(g, 0, "amustas")
	var small := spawn(g, 0, "syranite")  # Red, 60 HP: not over 60
	to_attack(g)
	g.attack(0, big.uid, 0, {"champion": gnome.uid})
	check(gnome.damage == 0, "a champion with over 60 HP cannot damage Gnome")
	g.attack(0, spawn(g, 0, "gob").uid, 0, {"champion": gnome.uid})
	check(gnome.damage == 10, "a champion with 60 HP or less can damage Gnome")
	var g2 := real_game()
	var troll := spawn(g2, 1, "small_troll")
	var hitter := spawn(g2, 0, "joseph_the_knight")
	g2.players[0].mana = 1
	to_attack(g2)
	var r := g2.attack(0, hitter.uid, 1, {"champion": troll.uid})
	check(r.fizzled and troll.damage == 0 and hitter.damage == 0, "Small Troll prevents an attack over 30, with all its effects")
	var g3 := real_game()
	var troll3 := spawn(g3, 1, "small_troll")
	var h3 := spawn(g3, 0, "joseph_the_knight")
	to_attack(g3)
	check(g3.attack(0, h3.uid, 0, {"champion": troll3.uid}).damage == 30 and troll3.damage == 30, "Small Troll takes an attack of exactly 30")
	var g4 := real_game()
	var big_troll := spawn(g4, 1, "big_troll")
	var a4 := spawn(g4, 0, "amustas")
	to_attack(g4)
	check(g4.attack(0, a4.uid, 1, {"champion": big_troll.uid}).fizzled, "Big Troll prevents an attack over 60 (Armageddon 100)")


func test_reactive_abilities() -> void:
	var g := real_game()
	var gluto := spawn(g, 1, "gluto")
	var a := spawn(g, 0, "syranite")
	to_attack(g)
	g.attack(0, a.uid, 0, {"champion": gluto.uid})
	check(a.damage == 20 and gluto.damage == 20, "Gluto deals 20 to an attacker (and takes the 20 attack)")
	var g2 := real_game()
	var gyp := spawn(g2, 1, "gyptjeous")
	var big := spawn(g2, 0, "amustas")
	to_attack(g2)
	g2.attack(0, big.uid, 0, {"champion": gyp.uid})
	check(big.damage == 0, "Gyptjeous does not react to an attack of 40")
	var g3 := real_game()
	var gyp3 := spawn(g3, 1, "gyptjeous")
	var big3 := spawn(g3, 0, "amustas")
	to_attack(g3)
	g3.attack(0, big3.uid, 1, {"champion": gyp3.uid})
	check(big3.damage == 20 and gyp3.damage == 100, "Gyptjeous deals 20 to an attacker that deals over 50 (Armageddon 100)")


func test_passive_locks() -> void:
	var g := real_game()
	spawn(g, 1, "ramaire")
	g.players[0].hand = [rc("fire_bolt")]
	spawn(g, 0, "pog")
	to_attack(g)
	check(not g.play_spell(0, 0, 0, {"champion": g.players[1].champions[0].uid}).ok, "Ramaire locks the opponent's spells")
	var g2 := real_game()
	var w := spawn(g2, 1, "warlord")
	g2.players[0].hand = [rc("fire_bolt")]
	spawn(g2, 0, "pog")
	g2.players[1].castled = true
	to_attack(g2)
	check(not g2.play_spell(0, 0, 0, {"fortress": 1}).ok, "Warlord locks spells even while encamped")
	var g3 := real_game()
	spawn(g3, 1, "harmlobeast")
	check(LockRules.is_locked(g3, 0, "fortress") and not LockRules.is_locked(g3, 1, "fortress"), "Harmlobeast stops only the opponent's Fortress effects")
	g3.players[0].turns_taken = 2
	var mana_before: int = g3.players[0].mana
	g3.next_step(0)
	check(g3.players[0].mana == mana_before, "the Fortress gives no mana under Harmlobeast")


func test_start_of_turn_champion_abilities() -> void:
	var g := real_game()
	spawn(g, 0, "poglasaur")
	var hand_before: int = g.players[0].hand.size()
	g.next_step(0)
	check(g.players[0].hand.size() == hand_before + 1, "Poglasaur draws a card at the start of your turn")
	var g2 := real_game()
	spawn(g2, 0, "psybar")
	g2.forced_coins = [true]
	g2.next_step(0)
	check(LockRules.is_locked(g2, 1, "draw"), "Psybar on Heads stops the opponent drawing next turn")
	g2.end_turn(0)
	check(g2.players[1].hand.size() == 0, "the locked opponent did not draw")
	var g3 := real_game()
	spawn(g3, 0, "psybar")
	g3.forced_coins = [false]
	g3.next_step(0)
	check(not LockRules.is_locked(g3, 1, "draw"), "Psybar on Tails does nothing")


func test_protection_and_blackthorn() -> void:
	var g := real_game()
	var misley := spawn(g, 0, "misley")
	var foe := spawn(g, 1, "amustas")
	g.forced_coins = [true]
	to_attack(g)
	g.attack(0, misley.uid, 0, {"champion": foe.uid})
	check(DamageRules.is_protected(misley), "Mist on Heads protects Misley")
	DamageRules.damage_champion(g, misley, 30, 1)
	check(misley.damage == 0, "protected Misley takes no damage")
	StatusRules.run_start_of_turn(g, 0)
	check(not DamageRules.is_protected(misley), "protection ends at the start of its owner's next turn")
	DamageRules.damage_champion(g, misley, 10, 1)
	check(misley.damage == 10, "Misley takes damage again after that")
	var g2 := real_game()
	var bd := spawn(g2, 0, "blackthorn_dragon")
	g2.forced_coins = [true]
	StatusRules.run_start_of_turn(g2, 0)
	check(DamageRules.is_protected(bd), "Blackthorn Dragon on Heads is protected until its owner's next turn")
	DamageRules.damage_champion(g2, bd, 30, 1)
	check(bd.damage == 0, "protected Blackthorn Dragon takes no damage from any source")
	g2.forced_coins = [false]
	StatusRules.run_start_of_turn(g2, 0)
	check(not DamageRules.is_protected(bd), "the protection ended and the new coin was Tails")
	DamageRules.damage_champion(g2, bd, 30, 1)
	check(bd.damage == 30, "Blackthorn Dragon takes damage after a Tails")
	var g3 := real_game()
	var dyn := spawn(g3, 0, "dynamo")
	DamageRules.damage_champion(g3, dyn, 40, 1)
	check(dyn.damage == 40, "Dynamo keeps 40 damage")
	DamageRules.damage_champion(g3, dyn, 10, 1)
	check(dyn.damage == 0, "Dynamo removes all its damage at 50")


func test_poison_discard_and_hand_effects() -> void:
	var g := real_game()
	var gf := spawn(g, 0, "griffog")
	var t := spawn(g, 1, "amustas")
	to_attack(g)
	g.attack(0, gf.uid, 0, {"champion": t.uid})
	check(t.damage == 20 and t.statuses.size() == 1 and t.statuses[0].kind == "poison", "Poisonous Bite: 20 damage and poison")
	for i in 4:
		StatusRules.run_start_of_turn(g, 1)
	check(t.damage == 60 and t.statuses.size() == 1, "poison keeps ticking 10 a turn with no end (60 after 4 ticks)")
	t.statuses.clear()
	StatusRules.run_start_of_turn(g, 1)
	check(t.damage == 60, "removing the poison status stops the damage")
	var g2 := real_game()
	var spike := spawn(g2, 0, "spike")
	var t2 := spawn(g2, 1, "amustas")
	g2.forced_coins = [false]
	to_attack(g2)
	g2.attack(0, spike.uid, 0, {"champion": t2.uid})
	check(t2.statuses.is_empty(), "Spike's poison needs Heads")
	var g3 := real_game()
	var mar := spawn(g3, 0, "maragret")
	var t3 := spawn(g3, 1, "amustas")
	g3.players[1].hand = [rc("syranite"), rc("syranite")]
	g3.players[0].mana = 1
	g3.forced_coins = [true]
	to_attack(g3)
	g3.attack(0, mar.uid, 1, {"champion": t3.uid})
	check(g3.players[1].hand.size() == 1 and g3.players[1].discard.size() == 1, "Infest on Heads: the opponent discards a card")
	var g4 := real_game()
	var pg := spawn(g4, 0, "poglass")
	var t4 := spawn(g4, 1, "amustas")
	g4.players[0].mana = 1
	g4.forced_coins = [true]
	var hand_before: int = g4.players[0].hand.size()
	to_attack(g4)
	g4.attack(0, pg.uid, 1, {"champion": t4.uid})
	check(g4.players[0].hand.size() == hand_before + 2, "Ring of Greed on Heads: draw 2")
	var g5 := real_game()
	var pg5 := spawn(g5, 0, "poglass")
	var t5 := spawn(g5, 1, "amustas")
	g5.players[0].mana = 1
	g5.players[0].hand = [rc("syranite"), rc("gob")]
	g5.forced_coins = [false]
	to_attack(g5)
	g5.attack(0, pg5.uid, 1, {"champion": t5.uid})
	check(g5.players[0].hand.size() == 1, "Ring of Greed on Tails: discard a card")
