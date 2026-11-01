## locks.gd - Locks (suppressions): effects that stop a player using attacks, spells, enchantments,
## summoning or their Fortress for a number of turns. Durations count the AFFECTED player's own turns:
## a lock on your opponent starts with their next turn and wears off when the last of those turns ends,
## so a one-turn summoning lock stops them summoning on their next turn only. Locks tick down in
## end_of_turn(), called when the locked player's turn ends.
class_name LockRules
extends RefCounted


static func add(g: Game, affected_player: int, what: String, turns: int) -> void:
	g.locks.append({"player": affected_player, "what": what, "turns_left": turns})
	g._log("P%d is locked from %s for %d of their turns." % [affected_player, what, turns])


static func is_locked(g: Game, p: int, what: String) -> bool:
	# Passive ability locks: while an enemy champion with "lock_enemy" is in play (active or encamped).
	if what == "spell" or what == "fortress":
		for c in g.players[1 - p].champions:
			if c.has_ability() and str(c.card.ability.get("lock_enemy", "")) == what:
				return true
	for l in g.locks:
		if int(l.player) == p and str(l.what) == what and int(l.turns_left) > 0:
			return true
	return false


## Called at the end of player p's turn.
static func end_of_turn(g: Game, p: int) -> void:
	for l in g.locks.duplicate():
		if int(l.player) == p:
			l.turns_left = int(l.turns_left) - 1
			if int(l.turns_left) <= 0:
				g.locks.erase(l)
