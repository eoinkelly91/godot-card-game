#!/usr/bin/env python3
"""Converts data/source/champions.xlsx into data/cards/{red,blue,white,purple}.json.

Run from the project folder:  python3 tools/import_champions.py
Needs openpyxl (pip install openpyxl).

The spreadsheet is the editing copy. Plain attacks come straight from the sheet; anything with an
effect is tagged below (ATTACK_EFFECTS / ABILITIES) with machine-readable keys the engine understands.
An effect without a tag keeps its sheet text and just does the printed damage.
Attacks the engine cannot fully resolve yet are marked "unimplemented": true (see README).
"""
import json
import re
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent
SHEET = ROOT / "data" / "source" / "champions.xlsx"
OUT = ROOT / "data" / "cards"

# ---- attack effects, keyed by (champion name, attack index 0/1) ---------------------------------
ATTACK_EFFECTS = {
    ("Joseph the Knight", 1): {"self_damage": 20},
    ("War Bear", 1): {"damage": 0, "coins": {"count": 3, "per_heads_damage": 20}},
    ("Mersoilder", 1): {"coin_bonus": 20},
    ("Tigrodon", 1): {"self_damage": 30},
    ("Poglass", 1): {"damage": 0, "coin_draw_or_discard": {"draw": 2, "discard": 1}},
    ("Gronk", 0): {"bonus_vs_class": {"class": "basic", "amount": 20}},
    ("Gronk", 1): {"splash_enemies": 20},
    ("Green Goblin", 0): {"bonus_vs_class": {"class": "basic", "amount": 10}},
    ("Pumpkin Knight", 0): {"bonus_vs_type": {"type": "Creature", "amount": 30}},
    ("Tree Dragon", 1): {"splash_all": 10},
    ("Capeasant", 0): {"damage": 0, "no_target": True, "coin_each_enemy": 10},
    ("Capatsar", 0): {"damage": 0, "no_target": True, "coin_each_enemy": 20},
    ("Capatsar", 1): {"duel": True},
    ("Elite-O", 0): {"damage": 10, "multi_target": 2},
    ("Maragret", 1): {"damage": 0, "coin_opponent_discards": 1},
    ("Psyville", 0): {"damage": 0, "no_target": True, "damage_each_enemy": 10},
    ("Psybar", 0): {"per_own_enchantment": 10},
    ("Molten Harry", 1): {"damage": 0, "no_target": True, "coin_extra_attack": True},
    ("Cwelen", 1): {"coin_fizzle": True},
    ("Saisen", 0): {"damage": 0, "coins": {"count": 3, "per_heads_damage": 10}},
    ("Stanter", 0): {"optional_discard_bonus": 30},
    ("Suburn", 0): {"coin_bonus": 20},
    ("The Magician Gcairo", 0): {"damage": 0, "per_opponent_hand_card": 10},
    ("The Magician Gcairo", 1): {"damage": 0, "coin_return_target_to_hand": True},
    ("Griffog", 0): {"poison": {"amount": 10, "turns": -1}},
    ("Taibait", 0): {"self_damage": 10},
    ("Gorth", 0): {"self_damage": 10},
    ("Lava Titan", 0): {"self_damage": 10},
    ("Spike", 0): {"poison": {"amount": 10, "turns": -1}, "coin_gated": True},
    ("Skullmort", 0): {"damage": 0, "per_champion_in_own_discard": 10},
    ("Misley", 0): {"coin_protect_self": True},
    ("Pupever", 0): {"coin_protect_self": True},
}

# ---- abilities, keyed by champion name -----------------------------------------------------------
ABILITIES = {
    "Blackthorn Dragon": {"trigger": "start_of_turn", "op": "coin_protect"},
    "Ramaire": {"trigger": "passive", "lock_enemy": "spell"},
    "Warlord": {"trigger": "passive", "lock_enemy": "spell"},
    "Harmlobeast": {"trigger": "passive", "lock_enemy": "fortress"},
    "Gluto": {"trigger": "passive", "when_attacked_damage_attacker": 20},
    "Poglasaur": {"trigger": "start_of_turn", "op": "draw", "amount": 1},
    "Gyptjeous": {"trigger": "passive", "when_hit_over_damage_attacker": {"over": 50, "amount": 20}},
    "Grimn": {"trigger": "passive", "stored_bonus_if_idle": 20},
    "Gnome": {"trigger": "passive", "immune_to_attackers_max_hp_over": 60},
    "Dynamo": {"trigger": "passive", "clear_damage_at": 50},
    "Psybar": {"trigger": "start_of_turn", "op": "coin_lock", "what": "draw", "turns": 1},
    "Marcos the Gladiator": {"trigger": "on_attack", "bonus_per": {"count": "own_champions", "amount": 10}},
    "Psytwist": {"trigger": "on_attack", "bonus_per": {"count": "spirits_in_play", "amount": 10}},
    "Hypnotwist": {"trigger": "on_attack", "bonus_per": {"count": "own_spirits", "amount": 10}},
    "Small Troll": {"trigger": "passive", "negate_if_damage_over": 30},
    "Big Troll": {"trigger": "passive", "negate_if_damage_over": 60},
    "Lava Titan": {"trigger": "on_attack", "bonus_per": {"count": "own_damage_per_5_counters", "amount": 10}},
    "Spike": {"trigger": "passive", "sacrifice_as_any_color": True},
}


def snake(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def parse_req(text):
    if not text:
        return None
    kind, value = str(text).split(":")
    return kind.strip(), int(value)


def parse_attack(text: str):
    name, _, rest = str(text).partition(":")
    rest = rest.strip()
    m = re.match(r"(\d+)", rest)
    return name.strip(), (int(m.group(1)) if m else 0), rest


def main() -> int:
    ws = openpyxl.load_workbook(SHEET).active
    header = [c.value for c in ws[1]]
    by_color = {"red": [], "blue": [], "white": [], "purple": []}
    used_effects, used_abilities = set(), set()
    for row in ws.iter_rows(min_row=2, values_only=True):
        d = dict(zip(header, row))
        sac, man = (int(x) for x in re.fullmatch(r"sac:(\d+)-man:(\d+)", d["summon"]).groups())
        summon = {}
        if sac:
            summon["sacrifice"] = sac
        if man:
            summon["mana"] = man
        card = {"id": snake(d["name"]), "name": d["name"], "kind": "champion",
                "class": d["class"], "color": d["color"].capitalize(), "type": d["type"].capitalize(),
                "hp": int(d["hp"]), "summon": summon, "attacks": []}
        for i in (0, 1):
            text = d[f"attack_{i + 1}"]
            if not text:
                continue
            name, dmg, rest = parse_attack(text)
            atk = {"name": name, "damage": dmg}
            req = parse_req(d[f"attack_{i + 1}_req"])
            if req:
                kind, value = req
                if kind == "manareq":
                    atk["mana_cost"] = value
                elif kind == "hpreq":
                    atk["requires"] = {"self_hp_at_least": value}  # current HP at or above N
                else:
                    raise SystemExit(f"{d['name']}: unknown requirement {kind}")
            eff = ATTACK_EFFECTS.get((d["name"], i))
            if eff:
                used_effects.add((d["name"], i))
                atk.update(eff)
            if rest and not rest.isdigit():
                atk["text"] = rest
            card["attacks"].append(atk)
        if d["ability"]:
            ab = {"text": d["ability"].strip()}
            tags = ABILITIES.get(d["name"])
            if tags:
                used_abilities.add(d["name"])
                ab.update(tags)
            else:
                ab["unimplemented"] = "no engine tag"
            card["ability"] = ab
        by_color[d["color"]].append(card)
    unused = set(ATTACK_EFFECTS) - used_effects
    unused_ab = set(ABILITIES) - used_abilities
    if unused or unused_ab:
        raise SystemExit(f"Tags that matched no card: {unused} {unused_ab}")
    for color, cards in by_color.items():
        (OUT / f"{color}.json").write_text(json.dumps(cards, indent=1) + "\n")
        print(f"{color}.json: {len(cards)} champions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
