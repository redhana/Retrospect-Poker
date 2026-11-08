class_name HandEvaluator
extends RefCounted
## Works out the best 5-card poker hand from up to 7 cards.
##
## A card is a Vector2i(rank, suit): rank 2..14 (14 = ace), suit 0..3.
## The result "score" is an Array like [category, tiebreak1, tiebreak2, ...].
## Higher category wins; if equal, compare tiebreakers left to right.
##   e.g. pair of kings, A-9-4 kickers  ->  [1, 13, 14, 9, 4]

enum { HIGH_CARD, PAIR, TWO_PAIR, TRIPS, STRAIGHT, FLUSH, FULL_HOUSE, QUADS, STRAIGHT_FLUSH }

const CATEGORY_NAMES := ["High card", "Pair", "Two pair", "Three of a kind", "Straight",
	"Flush", "Full house", "Four of a kind", "Straight flush"]
const RANK_NAMES := {2: "2", 3: "3", 4: "4", 5: "5", 6: "6", 7: "7", 8: "8", 9: "9",
	10: "10", 11: "Jack", 12: "Queen", 13: "King", 14: "Ace"}


## Best hand from the given cards. Returns {"score": Array, "name": String}.
static func evaluate(cards: Array) -> Dictionary:
	var score := _score(cards)
	return {"score": score, "name": describe(score)}


## +1 if a beats b, -1 if b beats a, 0 if tie.
static func compare(a: Array, b: Array) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] > b[i]:
			return 1
		if a[i] < b[i]:
			return -1
	return 0


## Turn a score into words, e.g. "Full house, Kings over 3s".
static func describe(s: Array) -> String:
	match s[0]:
		STRAIGHT_FLUSH:
			return "Royal flush" if s[1] == 14 else "Straight flush, %s high" % RANK_NAMES[s[1]]
		QUADS:
			return "Four of a kind, %s" % _plural(s[1])
		FULL_HOUSE:
			return "Full house, %s over %s" % [_plural(s[1]), _plural(s[2])]
		FLUSH:
			return "Flush, %s high" % RANK_NAMES[s[1]]
		STRAIGHT:
			return "Straight, %s high" % RANK_NAMES[s[1]]
		TRIPS:
			return "Three of a kind, %s" % _plural(s[1])
		TWO_PAIR:
			return "Two pair, %s and %s" % [_plural(s[1]), _plural(s[2])]
		PAIR:
			return "Pair of %s" % _plural(s[1])
		_:
			return "%s high" % RANK_NAMES[s[1]]


# ---------------------------------------------------------------- internals

static func _score(cards: Array) -> Array:
	# count how many of each rank, and group ranks by suit
	var count := {}                    # rank -> how many
	var by_suit := [[], [], [], []]    # suit -> list of ranks
	for c in cards:
		count[c.x] = count.get(c.x, 0) + 1
		by_suit[c.y].append(c.x)

	# ranks sorted high -> low (each rank once)
	var ranks: Array = count.keys()
	ranks.sort()
	ranks.reverse()

	# 1) straight flush / flush
	for suited in by_suit:
		if suited.size() >= 5:
			var sf := _straight_top(suited)
			if sf > 0:
				return [STRAIGHT_FLUSH, sf]
			suited.sort()
			suited.reverse()
			var flush := [FLUSH]
			flush.append_array(suited.slice(0, 5))
			var quads_or_full := _groups_score(count, ranks)   # quads/full house still beat a flush
			if quads_or_full[0] > FLUSH:
				return quads_or_full
			return flush

	# 2) quads / full house (checked before straight because they beat it)
	var g := _groups_score(count, ranks)
	if g[0] >= FULL_HOUSE:
		return g

	# 3) straight
	var top := _straight_top(ranks)
	if top > 0:
		return [STRAIGHT, top]

	# 4) trips, two pair, pair, high card
	return g


## Scores based on matching ranks only (quads, full house, trips, pairs, high card).
static func _groups_score(count: Dictionary, ranks: Array) -> Array:
	var quads := []
	var trips := []
	var pairs := []
	var singles := []
	for r in ranks:                 # ranks are already high -> low
		match count[r]:
			4: quads.append(r)
			3: trips.append(r)
			2: pairs.append(r)
			_: singles.append(r)

	if quads.size() > 0:
		var rest := _without(ranks, quads[0])
		return [QUADS, quads[0], _at(rest, 0)]
	if trips.size() >= 2:          # e.g. KKK 333 -> full house K over 3
		return [FULL_HOUSE, trips[0], trips[1]]
	if trips.size() == 1 and pairs.size() > 0:
		return [FULL_HOUSE, trips[0], pairs[0]]
	if trips.size() == 1:
		var rest := _without(ranks, trips[0])
		return [TRIPS, trips[0], _at(rest, 0), _at(rest, 1)]
	if pairs.size() >= 2:
		var rest := _without(_without(ranks, pairs[0]), pairs[1])
		return [TWO_PAIR, pairs[0], pairs[1], _at(rest, 0)]
	if pairs.size() == 1:
		var rest := _without(ranks, pairs[0])
		return [PAIR, pairs[0], _at(rest, 0), _at(rest, 1), _at(rest, 2)]
	var high := [HIGH_CARD]
	high.append_array(ranks.slice(0, 5))
	return high


## Highest card of a 5-in-a-row run, or 0 if none. Ace can also be low (A-2-3-4-5).
static func _straight_top(rank_list: Array) -> int:
	var has := {}
	for r in rank_list:
		has[r] = true
	if has.has(14):
		has[1] = true                 # ace-low
	for top in range(14, 4, -1):      # 14 down to 5
		var ok := true
		for k in 5:
			if not has.has(top - k):
				ok = false
				break
		if ok:
			return top
	return 0


static func _at(arr: Array, i: int) -> int:
	return arr[i] if i < arr.size() else 0   # 0 = "no card" when fewer than 5 cards


static func _without(arr: Array, value) -> Array:
	var out := []
	for v in arr:
		if v != value:
			out.append(v)
	return out


static func _plural(r: int) -> String:
	return RANK_NAMES[r] + "s"
