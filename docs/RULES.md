# Tactical Card Game: rules reference

Keep this file up to date when rules change. The numbers live in `scripts/engine/game.gd` (the `rules` dictionary).

## Winning
- **Siege:** reduce the enemy Fortress to 0 HP (Castle 400, Pirate Cove 350, Wizards Enclave 300, Beasts Lair 400).
- **Annihilation:** destroy **15** enemy champions.
- **Economic Victory:** bank **50** mana at the start of your turn.

## Setup and the turn
- Deck: 70 cards to draw + exactly one Fortress (played automatically). Limits: 1 Legendary, 6 Heroic, 10 Elite, 35 Basic, 12 spells, 6 enchantments.
- Starting hand **7** cards (free mulligans: 2). **Nobody starts with mana.** A coin flip picks who goes first (player X; the other is player Y).
- Start of turn: draw **2** cards (**0** on your first turn), gain **2** mana, then statuses (poison...) and the Fortress, enchantment and champion abilities trigger.
- Hand limit **13** (discard down at end of turn).
- On your first turn only draw and summon (no attacks, spells or enchantments).
- Attack once per colour. Early turns: player X's 2nd turn may attack with only **1 colour**; after that no limit.

## Summoning
- Each turn: **one Basic** summon and **one sacrifice** summon (a non-Basic champion: by sacrifices or by mana).
- On your **first turn** you may summon **two Basic** champions (and nothing else).
- Castling gives **one extra summon** of either kind.
- Every summoned champion (Basic or through sacrifice) cannot attack on the turn it is summoned (status **Summoned this turn**), and it **can** be attacked on the opponent's next turn.

## Castling
- From your **3rd turn**, once per game, with **1 or 2** active champions, before your first attack of the turn.
- While castled: your champions are Encamped and the Fortress is the only target. Castling gives +1 summon, +1 mana (3 a turn) and +1 card drawn (3 a turn). It lasts at most 3 of your turns.
- Encamping removes any status effects the champions had.

## Champion statuses
| Status | Meaning |
|---|---|
| **Active** | Can attack and can receive damage. Abilities are active. |
| **Summoned this turn** (Active) | The champion was summoned this turn: it cannot attack yet. It is dimmed with "Zzz" on its owner's turn. It can be attacked on the opponent's next turn. |
| **Encamped** | Cannot attack and cannot be attacked. Its abilities are inactive, and cards attached to it have no effect until it is active again. Encamping removes status effects. If you have only Encamped champions in play, your Fortress can be targeted. Happens when you castle (all your champions are encamped while castled). |
| **Chained** (Active) | Cannot attack but can be targeted by attacks. |
| **Poisoned** (Active) | Takes 10 damage at the start of its player's turn. A poisoned champion cannot be poisoned again. |
| **Armed** (Active or Encamped) | Has cards attached to it (at most 2). |
| *Protected / Shielded* | Takes no damage (for example Blackthorn Dragon's coin). Shown as "(shielded)" next to its name in target menus. |

More statuses may be added: add a row here and in `CardView._status_tags()`.

## Enchantments and spells
- Enchantments last the number of turns in the sheet's TURNS column (counted down at the start of their owner's turn; the turn they are played does not count). At most 3 in play; a 4th replaces one you choose.
- Spells and enchantments cannot be played on your first turn.
