extends Node3D
## Visual-only poker dealer: deck, dealing, flop/turn/river, showdown, fold, reshuffle.
## No rules yet — game logic will call these functions later.
##
## Setup: add a Node3D to main.tscn at position (0,0,0), attach this script,
## drag your Camera3D into the "Camera" slot in the Inspector. Press F5.
##
## Test keys:  SPACE next stage | P you place cards | F random opponent folds | R collect + shuffle

@export var camera: Camera3D
@export var test_keys := true                      ## SPACE/P/F/R testing. poker_game.gd turns this off
@export var num_players := 3                        ## including you (seat 0)
@export var seat_angles: Array[float] = [90.0, 180.0, 0.0]  ## degrees round the table: 90 = you (front), 180 = left, 0 = right, 270 = far side
@export var table_top_y := 0.85                     ## height of the felt surface
@export var seat_radius := Vector2(0.85, 0.48)      ## oval where players' cards sit (x, z)
@export var deck_pos := Vector3(-0.1, -0.1, -0.6)        ## dealer side, opposite you
@export var muck_pos := Vector3(0.1, 0, -0.6)
@export var community_pos := Vector3(0, 0, 0.25)   ## centre of the flop/turn/river row
@export var community_gap := 1.2                 ## spacing between them (1 = touching)
@export var opp_hand_height := 0.2                ## how high bots hold their cards above the table
@export var opp_hand_out := -0.15                  ## how far back toward the bot (away from centre)
@export var deal_time := 0.35                       ## seconds per card flight
@export var hand_offset := Vector3(0, -0.2, -0.36) ## floating hand, relative to camera
@export var hand_spread := 0.55                  ## gap between your 2 cards (1 = side by side, smaller = more overlap)
@export var hand_fan := 9.0                       ## degrees each held card leans outwards
@export var hand_raise := 0.018                   ## how much higher the right card sits
@export var hand_tilt := 75.0                     ## 90 = cards face you straight on

var all_cards: Array[Card] = []
var deck: Array[Card] = []
var hands: Array = []             # hands[seat] = [Card, Card]
var community: Array[Card] = []
var folded: Array[int] = []
var mucked := 0

var deck_slot: Marker3D
var muck_slot: Marker3D
var community_slots: Array[Marker3D] = []
var seat_slots: Array = []        # seat_slots[seat] = [Marker3D, Marker3D]
var hand_holder: Node3D
var hand_slots: Array[Marker3D] = []
var opp_holders: Array[Node3D] = []
var opp_hand_slots: Array = []   # opp_hand_slots[seat] = [Marker3D, Marker3D] (seat 0 unused)

var busy := false
var stage := 0
var hint: Label
const STAGES := ["Deal hands", "Flop", "Turn", "River", "Showdown", "Collect + shuffle"]


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
	_make_slots()
	_make_hint()
	for s in 4:
		for r in range(2, 15):
			var c := Card.new()
			add_child(c)
			c.setup(s, r)
			all_cards.append(c)
	deck = all_cards.duplicate()
	deck.shuffle()
	for i in deck.size():
		_snap_to_deck(deck[i], i)


func _process(_delta: float) -> void:
	# gentle float on the cards in your hand
	if hand_holder:
		var t := Time.get_ticks_msec() / 1000.0
		hand_holder.position = hand_offset + Vector3(0, sin(t * 1.6) * 0.003, 0)
		hand_holder.rotation.z = sin(t * 1.1) * 0.015
	# bots' floating hands bob too (each slightly out of sync)
	var tt := Time.get_ticks_msec() / 1000.0
	for i in opp_holders.size():
		var h := opp_holders[i]
		h.position.y = h.get_meta("base_y") + sin(tt * 1.4 + i * 2.0) * 0.006


# ANIMATIONS
# Each one is a coroutine: `await deal_hands()` waits until it has finished.

## 2 cards each, dealt round the table like a real dealer.
## Yours float in front of the camera; opponents' land face down at their seat.
func deal_hands() -> void:
	hands.clear()
	folded.clear()
	for s in num_players:
		hands.append([])
	for n in 2:
		for s in num_players:
			var c: Card = deck.pop_back()
			hands[s].append(c)
			Sound.play("draw")
			if s == 0:
				c.fly_to(hand_slots[n], true, 0.55, 0.15, true)
			else:
				c.fly_to(opp_hand_slots[s][n], true, deal_time, 0.08, true)   # face toward the bot = we see the back
			await _wait(0.12)
	await _wait(0.6)


## 3 cards face down in the middle, then flipped one by one.
func deal_flop() -> void:
	for i in 3:
		var c: Card = deck.pop_back()
		community.append(c)
		Sound.play("draw")
		c.fly_to(community_slots[i], false, deal_time, 0.06)
		await _wait(0.15)
	await _wait(deal_time)
	for i in 3:
		community[i].flip()
		await _wait(0.2)
	await _wait(0.4)


## One more community card (use for both turn and river)
func deal_one() -> void:
	if community.size() >= 5:
		return
	var c: Card = deck.pop_back()
	var i := community.size()
	community.append(c)
	Sound.play("draw")
	await c.fly_to(community_slots[i], false, deal_time, 0.06)
	await c.flip()


## Just you: your floating cards go down on the table in front of you.
func place_my_cards(face_up := true) -> void:
	if hands.is_empty():
		return
	for i in hands[0].size():
		var c: Card = hands[0][i]
		c.reparent(self)
		if face_up:
			Sound.play("flip")
		c.fly_to(seat_slots[0][i], face_up, 0.45, 0.1)
		await _wait(0.12)
	await _wait(0.5)


## Everyone still in reveals: you place yours, opponents flip theirs.
func showdown() -> void:
	if not (0 in folded):
		await place_my_cards(true)
	for s in range(1, num_players):
		if s in folded:
			continue
		for n in hands[s].size():
			var c: Card = hands[s][n]
			c.reparent(self)
			Sound.play("flip")
			c.fly_to(seat_slots[s][n], true, 0.45, 0.1)
			await _wait(0.1)
		await _wait(0.3)


## Player throws their cards face down onto the muck pile.
func fold(seat: int) -> void:
	if hands.is_empty() or seat in folded:
		return
	folded.append(seat)
	for c in hands[seat]:
		if c.get_parent() != self:
			c.reparent(self)
		c.fly_to(muck_slot, false, 0.4, 0.05, false, Vector3(randf_range(-0.01, 0.01), mucked * Card.THICK, 0))
		mucked += 1
		await _wait(0.08)
	await _wait(0.4)


## Every card flies back to the deck, then a split-and-riffle shuffle.
func collect_and_shuffle() -> void:
	var i := deck.size()
	for c in all_cards:
		if c in deck:
			continue
		if c.get_parent() != self:
			c.reparent(self)
		c.fly_to(deck_slot, false, 0.4, 0.12, false, Vector3(0, i * Card.THICK, 0))
		if i % 3 == 0:
			Sound.play("draw", -8.0, 0.15)            # soft riffle as cards go back in the deck
		i += 1
		await _wait(0.02)
	await _wait(0.5)
	deck = all_cards.duplicate()
	hands.clear()
	community.clear()
	folded.clear()
	mucked = 0
	await shuffle_anim()


func shuffle_anim() -> void:
	# split into two piles
	var t := create_tween().set_parallel()
	for i in deck.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		t.tween_property(deck[i], "position", _deck_local(floori(i / 2.0)) + Vector3(side * 0.05, 0, 0), 0.25) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t.finished
	deck.shuffle()
	Sound.play("shuffle")
	# riffle back together
	var t2 := create_tween().set_parallel()
	for i in deck.size():
		t2.tween_property(deck[i], "position", _deck_local(i), 0.3) \
			.set_delay(i * 0.004).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await t2.finished


# TEST KEYS

func _unhandled_input(e: InputEvent) -> void:
	if not test_keys or not (e is InputEventKey and e.pressed and not e.echo) or busy:
		return
	match e.keycode:
		KEY_SPACE:
			_run(_next_stage)
		KEY_P:
			_run(place_my_cards)
		KEY_F:
			_run(func(): await fold(randi_range(1, num_players - 1)))
		KEY_R:
			_run(_reset)


func _next_stage() -> void:
	match stage:
		0: await deal_hands()
		1: await deal_flop()
		2: await deal_one()   # turn
		3: await deal_one()   # river
		4: await showdown()
		5: await collect_and_shuffle()
	stage = (stage + 1) % STAGES.size()


func _reset() -> void:
	await collect_and_shuffle()
	stage = 0


func _run(fn: Callable) -> void:
	busy = true
	await fn.call()
	busy = false
	_update_hint()


#  SETUP HELPERS

func _make_slots() -> void:
	var y := table_top_y + Card.THICK / 2
	deck_slot = _slot(self, Vector3(deck_pos.x, y, deck_pos.z))
	muck_slot = _slot(self, Vector3(muck_pos.x, y, muck_pos.z))
	for i in 5:
		community_slots.append(_slot(self, Vector3(community_pos.x + (i - 2) * Card.SIZE.x * community_gap, y, community_pos.z)))

	# seats round an oval; seat 0 (you) is nearest the camera (+Z side)
	for s in num_players:
		var a := deg_to_rad(seat_angles[s]) if s < seat_angles.size() else PI / 2 + TAU * s / num_players
		var p := Vector3(cos(a) * seat_radius.x, y, sin(a) * seat_radius.y)
		var seat := _slot(self, p, atan2(p.x, p.z))   # card tops point at table centre
		seat_slots.append([_slot(seat, Vector3(-Card.SIZE.x * 0.57, 0, 0)), _slot(seat, Vector3(Card.SIZE.x * 0.57, 0, 0))])

		# bots: floating hand above their seat, held up facing the bot (so we see the backs)
		if s == 0:
			opp_hand_slots.append([])
			continue
		var holder := _slot(seat, Vector3(0, opp_hand_height, opp_hand_out))
		holder.set_meta("base_y", opp_hand_height)
		opp_holders.append(holder)
		var pair := []
		for i in 2:
			var h := _slot(holder, Vector3((i - 0.5) * Card.SIZE.x * 0.97, 0, -i * 0.004))
			h.rotation = Vector3(deg_to_rad(75), 0, deg_to_rad(-6 + 12 * i))
			pair.append(h)
		opp_hand_slots.append(pair)

	# floating hand, parented to the camera so it follows your mouse-look
	hand_holder = Node3D.new()
	hand_holder.name = "FloatingHand"
	camera.add_child(hand_holder)
	hand_holder.position = hand_offset
	for i in 2:
		var side := -1.0 if i == 0 else 1.0                       # left card, right card
		var pos := Vector3(side * Card.SIZE.x * hand_spread * 0.5, hand_raise * i, i * 0.004)   # right card higher + in front
		var h := _slot(hand_holder, pos)
		# tilt to face the camera, then lean each card outwards (a fan)
		h.basis = Basis(Vector3.RIGHT, deg_to_rad(hand_tilt)) * Basis(Vector3.UP, deg_to_rad(-side * hand_fan))
		hand_slots.append(h)
	# small light so your hand isn't lost in the dark room
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1, 0.85, 0.65)
	lamp.light_energy = 0.05
	lamp.omni_range = 0.35
	lamp.position = Vector3(0, 0.1, 0.05)
	hand_holder.add_child(lamp)


func _slot(parent: Node3D, pos: Vector3, yaw := 0.0) -> Marker3D:
	var m := Marker3D.new()
	parent.add_child(m)
	m.position = pos
	m.rotation.y = yaw
	return m


func _deck_local(i: int) -> Vector3:
	return deck_slot.position + Vector3(0, i * Card.THICK, 0)


func _snap_to_deck(c: Card, i: int) -> void:
	c.position = _deck_local(i)
	c.rotation = Vector3(0, 0, PI)   # face down


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _make_hint() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hint = Label.new()
	hint.position = Vector2(16, 12)
	hint.add_theme_font_size_override("font_size", 18)
	layer.add_child(hint)
	_update_hint()


func _update_hint() -> void:
	hint.visible = test_keys
	hint.text = "SPACE: %s   |   P: place my cards   F: opponent folds   R: reset" % STAGES[stage]
