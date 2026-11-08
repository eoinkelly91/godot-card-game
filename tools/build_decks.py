#!/usr/bin/env python3
"""Rebuilds data/decks.json so both decks fill the deck composition limits
(keep DECK_LIMITS in sync with scripts/engine/card_db.gd).
Cards of a group are spread as evenly as possible; leftovers go to the cards the old deck used most.
A colour pair with no champion in a group (no Legendary in white/purple yet) simply has fewer cards."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIMITS = {"legendary": 1, "heroic": 6, "elite": 10, "basic": 25, "enchantment": 6, "spell": 12}
FORTRESS = {"red_blue": "beasts_lair", "white_purple": "castle"}  # each deck has exactly one Fortress
DECKS = {"red_blue": ["red", "blue"], "white_purple": ["white", "purple"]}

old = json.loads((ROOT / "data/decks.json").read_text())
cards = {}
for f in ["red", "blue", "white", "purple", "spells", "enchantments", "fortresses"]:
    for c in json.loads((ROOT / f"data/cards/{f}.json").read_text()):
        cards[c["id"]] = c


def group(c):
    return c["class"] if c["kind"] == "champion" else c["kind"]


new = {}
for name, colours in DECKS.items():
    spec = {}
    for g, limit in LIMITS.items():
        pool = [c for c in cards.values() if group(c) == g and (g in ("enchantment", "spell") or c["color"].lower() in colours)]
        if not pool:
            continue
        pool.sort(key=lambda c: (-old[name].get(c["id"], 0), c["id"]))
        n = len(pool)
        for i in range(limit):
            c = pool[i % n]
            spec[c["id"]] = spec.get(c["id"], 0) + 1
    spec[FORTRESS[name]] = 1
    new[name] = spec
    print(name, sum(spec.values()), "cards")
(ROOT / "data/decks.json").write_text(json.dumps(new, indent=1) + "\n")
