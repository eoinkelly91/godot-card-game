#!/usr/bin/env python3
"""Converts data/source/spells_enchantments.xlsx into data/cards/spells.json and enchantments.json.

Run from the project folder:  python3 tools/import_spells.py      (needs openpyxl)
The sheet gives each card's name, class, cost and the effect text. The machine-readable effects live in
SPELLS / ENCHANTMENTS below, keyed by card name. A card with two effects lets the player CHOOSE ONE
(play_spell takes an effect_index). The script checks that the sheet and these tables agree on names and costs.
"""
import json
import re
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "data" / "source" / "spells_enchantments.xlsx"
OUT = ROOT / "data" / "cards"

SPELLS = {
    "Heal": [{"op": "heal", "amount": 50}, {"op": "cleanse"}],
    "Mist of Despair": [{"op": "move_counters", "count": 3}],
    "Crimson Wave": [{"op": "drain_mana", "amount": 2}, {"op": "gain_mana_per_enchantment", "per_card": 1}],
    "Ancient Script": [{"op": "remove_enchantment"}],
    "Treason": [{"op": "move_all_damage"}],
    "Battle Axe": [{"op": "bonus_damage", "amount": 30}, {"op": "damage_many", "amount": 10, "targets": 3}],
    "Reconstruction": [{"op": "repair_fortress", "per_card": 30}],
    "Spirit Chain": [{"op": "no_attack", "turns": 1}],
    "Wizardry": [{"op": "wizardry_draw", "draw": 3, "discard": 1}, {"op": "rearrange_top", "count": 5}],
    "Archaeology": [{"op": "return_champion"}],
    "Parasite": [{"op": "drain_mana_per_card", "per_card": 1}, {"op": "opponent_discards", "amount": 2}],
    "Decoder": [{"op": "discard_spells_for_mana", "per_card": 2}, {"op": "discard_enchantment_for_mana", "amount": 5}],
    "Mumified": [{"op": "summon_discount", "amount": 1}],
    "Magic Wave": [{"op": "type_attack_bonus", "type": "Spirit", "amount": 20}],
    "Thunderstorm": [{"op": "damage_all_enemies", "amount": 10}],
    "Vortex of the Damned": [{"op": "shuffle_weak_champions", "hp_below": 60}],
    "Warrior Idol": [{"op": "attach", "kind": "warrior_idol"}],
    "Fusion": [{"op": "attach", "kind": "fusion"}],
    "Galachs Will": [{"op": "return_card", "kind": "spell"}, {"op": "return_card", "kind": "enchantment"}],
    "Mystery": [{"op": "mystery_remove"}],
    "Grand Shield": [{"op": "reduce_enemy_attacks", "amount": 20}],
    "Rain of Dragons": [{"op": "type_attack_bonus", "type": "Creature", "amount": 20}],
    "Power Source": [{"op": "attach", "kind": "power_source"}],
    "Monster Trap": [{"op": "attach", "kind": "monster_trap"}],
    "Retreat Signal": [{"op": "retreat_basic"}],
}

ENCHANTMENTS = {
    "Field Medics": {"start_of_turn": {"op": "heal_all", "amount": 10}},
    "Enchanted Forest": {"start_of_turn": {"op": "gain_mana_per_champion", "amount": 1}},
    "Battlements": {"fortress_defense": {"prevent": 20, "damage_attacker": 20}},
    "Siege Works": {"start_of_turn": {"op": "fortress_damage_per_active_champion", "amount": 10}},
    "Mist of Grief": {"on_champion_lost_to_attack": {"gain_mana": 1}},
    "Super Shrink": {"hp_aura_enemy": -20},
}


# Fortress cards (class "fortress" in the sheet; the HP comes from the sheet's HP column). A Fortress ability
# either triggers at the start of its owner's turn together with the enchantments ("start_of_turn"), or is a
# passive the engine checks while attacking. Every player always draws a card and gains 1 mana at the start of
# their turn, so that is not part of a Fortress.
FORTRESSES = {
    "Castle": {"start_of_turn": {"op": "heal_all_active", "amount": 10}},
    "Pirate Cove": {"start_of_turn": {"op": "coin_draw", "count": 1}},
    "Wizards Enclave": {"start_of_turn": {"op": "gain_mana", "amount": 1}},
    "Beasts Lair": {"creature_bonus_damage": 10},
}


def snake(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def main():
    ws = openpyxl.load_workbook(SHEET).active
    header = [c.value for c in ws[1]]
    spells, enchants, fortresses, seen = [], [], [], set()
    for row in ws.iter_rows(min_row=2, values_only=True):
        d = dict(zip(header, row))
        if not d["name"]:
            continue
        cost = 0
        if d["cost"]:
            kind, value = str(d["cost"]).split(":")
            assert kind == "mana", d
            cost = int(value)
        text = [t.strip() for t in (d["effect_1"], d["effect_2"]) if t]
        card = {"id": snake(d["name"]), "name": d["name"], "kind": d["class"], "cost": cost, "text": text}
        seen.add(d["name"])
        if d["class"] == "spell":
            card["effects"] = SPELLS[d["name"]]
            spells.append(card)
        elif d["class"] == "fortress":
            card.update(FORTRESSES[d["name"]])
            card["hp"] = int(d["HP"] if "HP" in d else d["hp"])
            card.pop("cost", None)
            fortresses.append(card)
        else:
            card.update(ENCHANTMENTS[d["name"]])
            enchants.append(card)
    missing = (set(SPELLS) | set(ENCHANTMENTS) | set(FORTRESSES)) - seen
    if missing:
        raise SystemExit(f"Tagged cards not in the sheet: {missing}")
    (OUT / "spells.json").write_text(json.dumps(spells, indent=1) + "\n")
    (OUT / "enchantments.json").write_text(json.dumps(enchants, indent=1) + "\n")
    (OUT / "fortresses.json").write_text(json.dumps(fortresses, indent=1) + "\n")
    print(f"{len(spells)} spells, {len(enchants)} enchantments, {len(fortresses)} fortresses")


if __name__ == "__main__":
    sys.exit(main())
