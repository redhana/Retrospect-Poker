extends Node
## The rules of the game. Drives poker_table.gd

## 1 = Fold, 2 = Check/Call, 3 = Bet/Raise 

signal human_choice(action: String)

@export var table: Node3D               
@export var title_screen: Node            
@export var score_sheet: Node3D           
@export var total_rounds := 10
@export var start_chips := 500
@export var ante := 10                    ## everyone pays this at the start of a round
@export var bet_size := 20                ## minimum bet
@export var max_raises := 3               ## per betting round
@export var bot_think_time := 0.9         ## bot thinking time
@export_group("Time Jump")
@export var time_units_per_jump := 3      ## rounds to fill one line on the meter
@export var time_max_jumps := 3           ## lines on the meter (stored jumps)
@export var bot_jump_every := 3           ## bots time jump in the round after every this many rounds
@export_group("")
@export var bot_names: Array[String] = ["You", "Bot Left", "Bot Right"]

var n := 0                     # number of players
var chips: Array[int] = []
var in_hand: Array[bool] = []  # still in this round
var put_in: Array[int] = []    # chips each player put in this whole round
var street_bet: Array[int] = []  # chips each player put in this betting round
var pot := 0
var round_num := 0
var history: Array = []        # history[round] = { seat: [Vector2i, Vector2i] }  -> for time travel later

# UI
var info: Label
var players_lbl: Label
var message: Label
var buttons: HBoxContainer
var btn_fold: Button
var btn_call: Button
var btn_raise: Button
var waiting_for_human := false
var ui_layer: CanvasLayer
var bet_row: HBoxContainer
var bet_slider: HSlider
var human_current := 0

# time jump
var time_units := 0            # +1 per round; one jump = time_units_per_jump
var jump_btn: Button
var meter_fill: ColorRect
var selecting := false         # choosing which of your cards to send back
var hover_idx := -1
signal card_chosen(index: int)
var round_log: Array = []      # full record of every finished round (for the past view)
var last_winners: Array = []
var last_pot := 0
var last_reason := ""
var last_showdown := false
var in_past := false
var bot_jump_due: Array[bool] = []   # bots that will time jump on their next turn this round
var showdown_note := ""
var swapped := {}              # Card -> its real identity (Vector2i), put back after the round

# Runs once when the game starts.
# 1. wait a frame so PokerTable has built its 52 cards
# 2. turn off the table's test keys, fill in names and chips
# 3. build the on-screen UI
# 4. if there's a title screen, hide the UI and wait for "Deal"
# 5. start the game loop

func _ready() -> void:
	await get_tree().process_frame          # let the table build its deck first
	table.test_keys = false
	table._update_hint()
	n = table.num_players
	while bot_names.size() < n:
		bot_names.append("Bot %d" % bot_names.size())
	for s in n:
		chips.append(start_chips)
	_make_ui()
	if title_screen:
		ui_layer.visible = false
		await title_screen.started
		# use the amounts picked on the title screen
		start_chips = title_screen.chosen_chips
		ante = title_screen.chosen_ante
		bet_size = maxi(ante * 2, 1)
		for s in n:
			chips[s] = start_chips
		_refresh()
		ui_layer.visible = true
	await play_game()


# GAME FLOW
# The whole game: play up to total_rounds rounds, stop early if only one
# player has chips left. After each round the time meter goes up by 1.

func play_game() -> void:
	for r in range(1, total_rounds + 1):
		if _alive_count() < 2:
			break
		round_num = r
		await play_round()
		time_units = mini(time_units + 1, time_units_per_jump * time_max_jumps)
		_refresh_meter()
	_game_over()


# One full round (one "hand" of poker):
#   opening bet -> deal 2 each -> bet -> flop -> bet -> turn -> bet
#   -> river -> bet -> showdown -> record the round -> collect cards
# If everyone but one player folds at any point, that player wins early.

func play_round() -> void:
	in_hand.clear()
	put_in.clear()
	pot = 0
	last_showdown = false
	showdown_note = ""
	# Bots time jump in the round after every 3rd finished round (rounds 4, 7, 10).
	var bots_jump := round_log.size() > 0 and round_log.size() % bot_jump_every == 0
	bot_jump_due.clear()
	for s in n:
		in_hand.append(chips[s] > 0)          # 0 or minus = out of the game
		put_in.append(0)
		bot_jump_due.append(bots_jump and s != 0)
	_say("Round %d of %d" % [round_num, total_rounds])

	# antes
	for s in n:
		if in_hand[s]:
			_pay(s, mini(ante, chips[s]))
	_refresh()

	# deal; anyone who is bust "folds" straight away
	# Deal 2 cards each (animation). Anyone who is out folds straight away.
	
	await table.deal_hands()
	for s in n:
		if not in_hand[s]:
			await table.fold(s)
	_record_history()

	# who acts first rotates each round
	var first := round_num % n
	
# The 4 betting rounds. Each entry is a FUNCTION to call (a Callable):
	#   pre-flop: nothing to deal (empty Callable)
	#   flop: deal 3, turn: deal 1, river: deal 1
	
	var streets := [Callable(), table.deal_flop, table.deal_one, table.deal_one]
	var names := ["Pre-flop", "Flop", "Turn", "River"]
	for i in streets.size():
		if i > 0:
			_say(names[i])
			if i == 3:
				Sound.play("heartbeat")              # the last card...
			await streets[i].call()
		var winner_by_fold := await betting_round(first)
		if winner_by_fold >= 0:
			await _award([winner_by_fold], "everyone else folded")
			_record_round()
			await _end_round()
			return

	await _showdown()
	_record_round()
	await _end_round()

# One betting round. Goes round the table until everyone still in has
# either matched the highest bet or folded.
#
# How it knows when to stop:
#   needs_to_act[seat] = true  -> that player still has to make a decision
#   Acting sets your flag to false. A RAISE sets everyone else's back to
#   true, because they now have to respond to the new, higher bet.
#   The while-loop ends when nobody has the flag.
#
# current       = the highest bet so far this round
# street_bet[p] = how much player p has put in this round
# to_call       = how much p must add to match: current - street_bet[p]

func betting_round(first: int) -> int:
	street_bet.clear()
	for s in n:
		street_bet.append(0)
	var current := 0          # highest bet this round
	var raises := 0
	var needs_to_act: Array[bool] = []
	for s in n:
		needs_to_act.append(in_hand[s] and chips[s] > 0)

	var p := first
	while needs_to_act.has(true):
		if needs_to_act[p]:
			var to_call := current - street_bet[p]
			var can_raise := raises < max_raises and chips[p] > to_call
			var action: String
			if p == 0:
				action = await _ask_human(to_call, can_raise, current)
			else:
				if bot_jump_due[p]:
					bot_jump_due[p] = false
					await _bot_time_jump(p)
					to_call = current - street_bet[p]
					can_raise = raises < max_raises and chips[p] > to_call
				action = await _ask_bot(p, to_call, can_raise)

			match action:
				"fold":
					in_hand[p] = false
					Sound.play("fold")
					_say("%s %s" % [bot_names[p], _v(p, "fold")])
					await table.fold(p)
					if _in_hand_count() == 1:
						return in_hand.find(true)
				"call":
					var amount := mini(to_call, maxi(chips[p], 0))      # can't pay from below 0
					_pay(p, amount)
					street_bet[p] += amount
					if amount == 0:
						Sound.play("check")
						_say("%s %s" % [bot_names[p], _v(p, "check")])
					elif chips[p] <= 0:
						Sound.play("raise", -3.0)
						_say("%s %s %d — ALL IN" % [bot_names[p], _v(p, "call"), amount])
					else:
						Sound.play("raise", -3.0)                 # calling = chips going in, a bit quieter
						_say("%s %s %d" % [bot_names[p], _v(p, "call"), amount])
				"raise":
					var was_bet := current == 0
					var target: int = int(bet_slider.value) if p == 0 else _bot_raise_target(p, current)
					target = maxi(target, current + 1)
					var amount := mini(target - street_bet[p], maxi(chips[p], 0))
					_pay(p, amount)
					street_bet[p] += amount
					current = maxi(current, street_bet[p])
					raises += 1
					Sound.play("raise")
					if chips[p] <= 0:
						_say("%s %s ALL IN (%d)" % [bot_names[p], "go" if p == 0 else "goes", street_bet[p]])
					else:
						_say("%s %s %d" % [bot_names[p], _v(p, "bet") if was_bet else _v(p, "raise") + " to", current])
					for s in n:   # everyone else must respond to the raise
						if s != p and in_hand[s] and chips[s] > 0:
							needs_to_act[s] = true
			needs_to_act[p] = false
			_refresh()
		p = (p + 1) % n
	return -1


func _showdown() -> void:
	last_showdown = true
	_say("Showdown!")
	await table.showdown()
	var board := _cards_of(table.community)
	var best_score := []
	var winners: Array[int] = []
	var lines := []
	for s in n:
		if not in_hand[s]:
			continue
		var result := HandEvaluator.evaluate(_cards_of(table.hands[s]) + board)
		lines.append("%s: %s" % [bot_names[s], result.name])
		var cmp := 1 if winners.is_empty() else HandEvaluator.compare(result.score, best_score)
		if cmp > 0:
			best_score = result.score
			winners = [s]
		elif cmp == 0:
			winners.append(s)
	showdown_note = "\n\n" + "\n".join(lines)     # everyone's hand, shown under the scores until next round
	_refresh()
	if in_hand[0]:                                  # you were in at the showdown
		Sound.play("exhale" if 0 in winners else "woodbreak")
	await _award(winners, HandEvaluator.describe(best_score))
	Sound.stop("heartbeat")


func _award(winners: Array, reason: String) -> void:
	last_winners = winners.duplicate()
	last_pot = pot
	last_reason = reason
	var share := floori(float(pot) / winners.size())
	for w in winners:
		chips[w] += share
	chips[winners[0]] += pot - share * winners.size()   # odd chip from a split
	var names := []
	for w in winners:
		names.append(bot_names[w])
	var verb := "win" if winners.size() > 1 or winners[0] == 0 else "wins"
	_say("%s %s %d  (%s)" % [" & ".join(names), verb, pot, reason], true)
	pot = 0
	_refresh()
	await get_tree().create_timer(2.5).timeout


func _end_round() -> void:
	Sound.stop("heartbeat")                        # in case the round ended without a showdown
	await table.collect_and_shuffle()
	for c in swapped:                     # time-jumped cards turn back into their real selves
		var v: Vector2i = swapped[c]
		c.morph_to(v.y, v.x, true)
	swapped.clear()


func _game_over() -> void:
	var best := 0
	for s in n:
		if chips[s] > chips[best]:
			best = s
	buttons.visible = false
	Sound.play("exhale" if best == 0 else "woodbreak")
	_say("GAME OVER — %s win%s with %d chips" % [bot_names[best], "" if best == 0 else "s", chips[best]], true)


# ================================================================ PLAYERS

func _ask_human(to_call: int, can_raise: bool, current: int) -> String:
	btn_call.text = "Check" if to_call == 0 else "Call %d" % mini(to_call, chips[0])
	btn_raise.disabled = not can_raise
	# slider: from the smallest legal bet/raise up to all-in
	human_current = current
	var max_to := street_bet[0] + chips[0]
	var min_to := mini(current + bet_size, max_to)
	bet_slider.min_value = min_to
	bet_slider.max_value = max_to
	bet_slider.step = 1                                   # smooth: moves 1 chip at a time
	bet_slider.value = min_to
	bet_row.visible = can_raise
	_update_raise_text()
	buttons.visible = true
	_say("Your turn")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE    # so you can click the buttons
	waiting_for_human = true
	_update_jump_btn()
	var a: String = await human_choice
	_stop_select()
	waiting_for_human = false
	_update_jump_btn()
	buttons.visible = false
	bet_row.visible = false
	return a


func _update_raise_text(_val := 0.0) -> void:
	var amt := int(bet_slider.value)
	if amt >= int(bet_slider.max_value):
		btn_raise.text = "All in (%d)" % amt
	elif human_current == 0:
		btn_raise.text = "Bet %d" % amt
	else:
		btn_raise.text = "Raise to %d" % amt


func _unhandled_input(e: InputEvent) -> void:
	if not waiting_for_human or in_past or not (e is InputEventKey and e.pressed and not e.echo):
		return
	if selecting and e.keycode == KEY_ESCAPE:
		_stop_select()
		get_viewport().set_input_as_handled()
		return
	match e.keycode:
		KEY_1: human_choice.emit("fold")
		KEY_2: human_choice.emit("call")
		KEY_3:
			if not btn_raise.disabled:
				human_choice.emit("raise")
		KEY_UP, KEY_RIGHT:
			bet_slider.value += bet_slider.step * 5
		KEY_DOWN, KEY_LEFT:
			bet_slider.value -= bet_slider.step * 5


## Simple rule-based bot: how strong is my hand vs how much does it cost to stay in?
func _ask_bot(p: int, to_call: int, can_raise: bool) -> String:
	await get_tree().create_timer(bot_think_time).timeout
	var strength := _bot_strength(p) + randf_range(-0.08, 0.08)   # a bit of unpredictability
	var pot_odds := float(to_call) / float(pot + to_call) if to_call > 0 else 0.0

	if strength > 0.75 and can_raise:
		return "raise"
	if to_call == 0:
		if can_raise and (strength > 0.55 and randf() < 0.5 or randf() < 0.08):   # value bet or bluff
			return "raise"
		return "call"   # check
	if strength >= pot_odds + 0.1:
		return "call"
	if randf() < 0.07:
		return "call"   # occasional stubborn call
	return "fold"


## How high a bot raises to: bigger with a stronger hand.
func _bot_raise_target(p: int, current: int) -> int:
	var s := _bot_strength(p)
	var mult := 1
	if s > 0.85:
		mult = randi_range(2, 4)
	elif s > 0.65:
		mult = randi_range(1, 2)
	return current + bet_size * mult


## 0.0 = rubbish, 1.0 = unbeatable (rough!)
func _bot_strength(p: int) -> float:
	return _hand_strength(_cards_of(table.hands[p]), _cards_of(table.community))


## 0.0 = rubbish, 1.0 = unbeatable, for any 2 hole cards + board.
func _hand_strength(hole: Array, board: Array) -> float:
	if board.is_empty():
		# pre-flop: judge the 2 cards alone
		var hi := maxi(hole[0].x, hole[1].x)
		var lo := mini(hole[0].x, hole[1].x)
		if hi == lo:
			return 0.5 + hi / 28.0                        # pairs: 22 = 0.57, AA = 1.0
		var s := (hi + lo) / 28.0 * 0.6                  # high cards
		if hole[0].y == hole[1].y: s += 0.05              # suited
		if hi - lo == 1: s += 0.03                       # connected
		return s
	var mine: Array = HandEvaluator.evaluate(hole + board).score
	var category_strength := [0.15, 0.4, 0.55, 0.65, 0.75, 0.8, 0.9, 0.97, 1.0]
	var s: float = category_strength[mine[0]]
	# if the board alone already makes this hand, everyone has it -> worth less
	if HandEvaluator.evaluate(board).score[0] == mine[0]:
		s *= 0.6
	return s


# ================================================================ TIME JUMP

func jumps_available() -> int:
	return time_units / time_units_per_jump


## Time Jump pressed: outline your 2 cards red, hover = green, click one to choose it.
func _on_time_jump() -> void:
	Sound.play("click")
	if selecting:
		_stop_select()          # pressing it again cancels
		return
	if jumps_available() == 0 or round_log.is_empty() or table.hands.is_empty() or 0 in table.folded:
		return
	selecting = true
	hover_idx = -1
	for c in table.hands[0]:
		c.set_outline(OUTLINE_RED)
	_say("Choose a card to send back in time")
	var i: int = await card_chosen
	if i < 0:
		return
	var chosen: Card = table.hands[0][i]
	var give := Vector2i(chosen.rank, chosen.suit)

	# into the past: hide the turn UI, show the black-and-white past view
	in_past = true
	buttons.visible = false
	bet_row.visible = false
	_update_jump_btn()
	info.visible = false
	players_lbl.visible = false
	message.text = ""
	Sound.enter_past()
	var pv := PastView.new()
	add_child(pv)
	var visible_now := _cards_of(table.hands[0]) + _cards_of(table.community)
	var pick: Dictionary = await pv.open(table, round_log, give, visible_now)
	pv.queue_free()
	Sound.leave_past()
	info.visible = score_sheet == null
	players_lbl.visible = score_sheet == null
	if not pick.is_empty():
		await _apply_time_jump(0, i, pick.round_index, pick.card_index)   # buttons stay hidden during this
	in_past = false
	_update_jump_btn()
	if waiting_for_human:
		buttons.visible = true
		bet_row.visible = not btn_raise.disabled
		_say("Your turn")


## The swap itself. Works for any seat, so bots (and later other players) use it too.
##   seat       - who is jumping
##   hand_idx   - which of their current cards goes back in time
##   round_idx  - which recorded round
##   past_idx   - which of their cards in that round they take
func _apply_time_jump(seat: int, hand_idx: int, round_idx: int, past_idx: int) -> void:
	var rec: Dictionary = round_log[round_idx]
	var card: Card = table.hands[seat][hand_idx]
	var give := Vector2i(card.rank, card.suit)
	var take: Vector2i = rec.hands[seat][past_idx]
	if seat == 0:
		time_units -= time_units_per_jump
		_refresh_meter()
	else:
		_say("%s jumps back to round %d..." % [bot_names[seat], rec.round], true)
		Sound.play("time_reverse")
		await _time_flash()
	var my_before := chips[0]

	# present: the card in your hand becomes the past card
	if not swapped.has(card):
		swapped[card] = give
	card.morph_to(take.y, take.x)

	# past: your old card goes into that round, which is re-played
	var result := _rewrite_round(rec, seat, past_idx, give)
	_refresh()
	var who: String = bot_names[seat]
	var d0 := chips[0] - my_before                      # what it did to YOUR chips
	var extra := ""
	if d0 != 0:
		extra = "  ·  You %s" % (("+%d" % d0) if d0 > 0 else str(d0))
	_say("%s rewrote round %d: %s%s" % [who, rec.round, result, extra], true)
	await get_tree().create_timer(3.0).timeout


## A bot's time jump: try every legal swap, keep the one that helps most.
## Score = chips it would gain from rewriting the past + how much better its hand is now.
func _bot_time_jump(p: int) -> void:
	if round_log.is_empty() or table.hands[p].size() < 2:
		return
	var hole := _cards_of(table.hands[p])
	var board := _cards_of(table.community)
	var visible := hole + board                     # what this bot can see (same rule as you)
	var now_strength := _hand_strength(hole, board)
	var best_score := -INF
	var best := []
	for hand_idx in hole.size():
		var give: Vector2i = hole[hand_idx]
		for ri in round_log.size():
			var rec: Dictionary = round_log[ri]
			if give in rec.community or rec.hands[p].size() < 2:
				continue
			for k in rec.hands[p].size():
				var take: Vector2i = rec.hands[p][k]
				if take in visible:
					continue
				# test it on copies, nothing real changes
				var sim_chips := chips.duplicate()
				_rewrite_round(rec.duplicate(true), p, k, give, sim_chips)
				var gain: int = sim_chips[p] - chips[p]
				var new_hole := hole.duplicate()
				new_hole[hand_idx] = take
				var score := gain + 150.0 * (_hand_strength(new_hole, board) - now_strength)
				if score > best_score:
					best_score = score
					best = [hand_idx, ri, k]
	if best.is_empty():
		return                                       # nothing legal to swap
	await _apply_time_jump(p, best[0], best[1], best[2])


## Quick black-and-white pulse when someone else jumps.
func _time_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PastView.GREY_SHADER
	sm.shader = sh
	r.material = sm
	layer.add_child(r)
	var set_amt := func(v: float): sm.set_shader_parameter("amount", v)
	var t := create_tween()
	t.tween_method(set_amt, 0.0, 1.0, 0.4)
	t.tween_interval(0.6)
	t.tween_method(set_amt, 1.0, 0.0, 0.5)
	await t.finished
	layer.queue_free()


## Put `new_card` into `seat`'s hand in a recorded round, re-work out who won, and move the money.
## Returns a short description of the new result.
func _rewrite_round(rec: Dictionary, seat: int, past_idx: int, new_card: Vector2i, ch = null) -> String:
	if ch == null:
		ch = chips                            # the real chips (bots pass a copy to test ideas)
	rec.hands[seat][past_idx] = new_card
	var old_pot: int = rec.pot

	# un-fold: pay what you'd have needed to stay in
	if rec.folded[seat]:
		var cost := PastView.unfold_cost(rec, seat)
		ch[seat] -= cost
		rec.put_in[seat] += cost
		rec.pot += cost
		rec.folded[seat] = false

	# undo the old payout
	_pay_out(rec.winners, old_pot, -1, ch)

	# who wins now? (only the cards that were actually dealt)
	var alive := []
	for s in rec.hands.size():
		if not rec.folded[s]:
			alive.append(s)
	var winners := []
	var reason := "everyone else folded"
	if alive.size() == 1:
		winners = alive
	else:
		var best := []
		for s in alive:
			var sc: Array = HandEvaluator.evaluate(rec.hands[s] + rec.community).score
			var cmp := 1 if winners.is_empty() else HandEvaluator.compare(sc, best)
			if cmp > 0:
				best = sc
				winners = [s]
			elif cmp == 0:
				winners.append(s)
		reason = HandEvaluator.describe(best)
		rec.showdown = true

	_pay_out(winners, rec.pot, 1, ch)
	rec.winners = winners

	var names := []
	for w in winners:
		names.append(bot_names[w])
	var verb := "win" if winners.size() > 1 or winners[0] == 0 else "wins"
	var text := "%s %s %d (%s)" % [" & ".join(names), verb, rec.pot, reason]
	rec.summary = "Rewritten: " + text
	return text


## Give (sign = 1) or take back (sign = -1) a pot split between winners. Chips can go below 0.
func _pay_out(winners: Array, amount: int, sign: int, ch: Array) -> void:
	if winners.is_empty():
		return
	var share := floori(float(amount) / winners.size())
	for w in winners:
		ch[w] += sign * share
	ch[winners[0]] += sign * (amount - share * winners.size())


func _stop_select() -> void:
	if not selecting:
		return
	selecting = false
	if not table.hands.is_empty():
		for c in table.hands[0]:
			c.set_outline(Color(0, 0, 0, 0))
	card_chosen.emit(-1)


func _process(_delta: float) -> void:
	if not selecting:
		return
	# which of your cards is under the mouse? (ray vs each card's flat face)
	var cam: Camera3D = get_viewport().get_camera_3d()
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var best := -1
	var best_t := INF
	for i in table.hands[0].size():
		var c: Card = table.hands[0][i]
		var n: Vector3 = c.global_basis.y
		var denom := n.dot(dir)
		if absf(denom) < 0.0001:
			continue
		var t := n.dot(c.global_position - from) / denom
		if t <= 0.0 or t >= best_t:
			continue
		var local: Vector3 = c.global_transform.affine_inverse() * (from + dir * t)
		if absf(local.x) <= Card.SIZE.x / 2 and absf(local.z) <= Card.SIZE.y / 2:
			best = i
			best_t = t
	if best != hover_idx:
		hover_idx = best
		for i in table.hands[0].size():
			table.hands[0][i].set_outline(OUTLINE_GREEN if i == hover_idx else OUTLINE_RED)


func _input(e: InputEvent) -> void:
	# clicking a card while choosing (handled before the camera grabs the mouse)
	if selecting and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and hover_idx >= 0:
		get_viewport().set_input_as_handled()
		Sound.play("click")
		var i := hover_idx
		selecting = false
		for c in table.hands[0]:
			c.set_outline(Color(0, 0, 0, 0))
		card_chosen.emit(i)


func _card_name(v: Vector2i) -> String:
	return Card.FACES.get(v.x, str(v.x)) + Card.SUITS[v.y]


const OUTLINE_RED := Color(1.0, 0.15, 0.15)
const OUTLINE_GREEN := Color(0.2, 1.0, 0.35)


func _refresh_meter() -> void:
	if meter_fill == null:
		return
	var full := float(time_units_per_jump * time_max_jumps)
	var w := METER_SIZE.x * time_units / full
	var t := create_tween()
	t.tween_property(meter_fill, "size:x", w, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_update_jump_btn()


## The "1 jump" text is the button: yellow + clickable on your turn when you have a jump.
func _update_jump_btn() -> void:
	if jump_btn == null:
		return
	var j := jumps_available()
	jump_btn.text = "%d jump%s" % [j, "" if j == 1 else "s"]
	jump_btn.disabled = not (waiting_for_human and not in_past and j > 0 and not round_log.is_empty())


const METER_SIZE := Vector2(200, 8)    # long, thin, horizontal bar
const METER_RIGHT := 40.0              # gap from the right edge of the screen
const METER_BOTTOM := 70.0             # gap from the bottom (leaves room for "1 jump" underneath)
const JUMP_READY := Color(1.0, 0.82, 0.3)   # yellow when you can jump


func _make_meter(layer: CanvasLayer) -> void:
	# thin horizontal bar, bottom right, with a tick for each stored jump
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)    # bottom right of the screen
	root.offset_left = -METER_RIGHT - METER_SIZE.x
	root.offset_right = -METER_RIGHT
	root.offset_top = -METER_BOTTOM - METER_SIZE.y
	root.offset_bottom = -METER_BOTTOM
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.size = METER_SIZE
	root.add_child(bg)

	meter_fill = ColorRect.new()
	meter_fill.color = Color(0.95, 0.75, 0.45)          # warm sand, fills left -> right
	meter_fill.size = Vector2(0, METER_SIZE.y)
	root.add_child(meter_fill)

	for k in range(1, time_max_jumps + 1):              # the ticks
		var tick := ColorRect.new()
		tick.color = Color(1, 0.97, 0.9)
		tick.size = Vector2(2, METER_SIZE.y + 10)
		tick.position = Vector2(METER_SIZE.x * float(k) / time_max_jumps - 1, -5)
		root.add_child(tick)

	var frame := ReferenceRect.new()
	frame.border_color = Color(1, 0.97, 0.9, 0.8)
	frame.border_width = 1
	frame.editor_only = false
	frame.size = METER_SIZE
	root.add_child(frame)

	# "0 jumps" under the bar, against the right margin - and it's the Time Jump button
	jump_btn = UIStyle.text_button("0 jumps", 24)
	jump_btn.add_theme_color_override("font_color", JUMP_READY)
	jump_btn.add_theme_color_override("font_hover_color", JUMP_READY.lightened(0.4))
	jump_btn.add_theme_color_override("font_focus_color", JUMP_READY)
	jump_btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	var holder := jump_btn.get_parent() as Control
	root.add_child(holder)
	var place := func(): holder.position = Vector2(METER_SIZE.x + 12 - holder.size.x, METER_SIZE.y + 6)
	holder.resized.connect(place)
	place.call()
	jump_btn.pressed.connect(_on_time_jump)
	_refresh_meter()


# ================================================================ HELPERS

## "You fold" / "Bot Left folds"
func _v(p: int, verb: String) -> String:
	return verb if p == 0 else verb + "s"


func _pay(s: int, amount: int) -> void:
	chips[s] -= amount
	put_in[s] += amount
	pot += amount


func _cards_of(cards: Array) -> Array:
	var out := []
	for c in cards:
		out.append(Vector2i(c.rank, c.suit))
	return out


## Save everything about the round that just finished, so the past view can rebuild it.
func _record_round() -> void:
	var names := []
	for w in last_winners:
		names.append(bot_names[w])
	var verb := "win" if last_winners.size() > 1 or last_winners[0] == 0 else "wins"
	var rec := {
		"round": round_num,
		"hands": [],
		"community": _cards_of(table.community),
		"folded": [],
		"put_in": put_in.duplicate(),
		"pot": last_pot,
		"winners": last_winners.duplicate(),
		"showdown": last_showdown,
		"summary": "%s %s %d (%s)" % [" & ".join(names), verb, last_pot, last_reason],
	}
	for s in n:
		rec.hands.append(_cards_of(table.hands[s]) if s < table.hands.size() else [])
		rec.folded.append(not in_hand[s])
	round_log.append(rec)


func _record_history() -> void:
	var snap := {}
	for s in n:
		snap[s] = _cards_of(table.hands[s])
	history.append(snap)


func _alive_count() -> int:
	var k := 0
	for c in chips:
		if c > 0:
			k += 1
	return k


func _in_hand_count() -> int:
	return in_hand.count(true)


# ================================================================ UI

func _make_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_layer = layer

	info = _ui_label(layer, Vector2(16, 12), 20)
	players_lbl = _ui_label(layer, Vector2(16, 48), 18)
	info.visible = score_sheet == null           # with a score sheet, the scores live on the table
	players_lbl.visible = score_sheet == null

	# one centred column at the top: caption, then buttons, then bet slider (they can't overlap)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -CAPTION_WIDTH / 2
	top.offset_right = CAPTION_WIDTH / 2
	top.offset_top = 14
	top.add_theme_constant_override("separation", 2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)

	message = UIStyle.label("", CAPTION_SIZE)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART      # long captions wrap instead of spilling over
	message.custom_minimum_size = Vector2(CAPTION_WIDTH, 0)
	top.add_child(message)

	buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	top.add_child(buttons)
	btn_fold = _ui_button("Fold", "fold")
	btn_call = _ui_button("Check", "call")
	btn_raise = _ui_button("Bet", "raise")
	buttons.visible = false

	# bet slider, tucked right under the buttons (only on your turn when you can bet)
	bet_row = HBoxContainer.new()
	bet_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(bet_row)
	bet_slider = UIStyle.slider(bet_size, start_chips, 1, bet_size, SLIDER_WIDTH)
	bet_slider.value_changed.connect(_update_raise_text)
	bet_row.add_child(bet_slider)
	bet_row.visible = false
	_make_meter(layer)
	_refresh()


const CAPTION_WIDTH := 620.0   # captions wrap onto a 2nd line past this width
const CAPTION_SIZE := 28        # normal caption size
const CAPTION_BIG := 32         # results, game over
const SLIDER_WIDTH := 300.0


func _ui_label(parent: Node, pos: Vector2, size: int) -> Label:
	var l := UIStyle.label("", size + 4)
	l.position = pos
	parent.add_child(l)
	return l


func _ui_button(text: String, action: String) -> Button:
	var b := UIStyle.text_button(text, 34)
	b.pressed.connect(func(): human_choice.emit(action))
	buttons.add_child(b.get_parent())
	return b


func _refresh() -> void:
	info.text = "Round %d / %d      Pot: %d" % [round_num, total_rounds, pot]
	players_lbl.text = _players_text() + showdown_note
	if score_sheet:
		score_sheet.set_text("Round %d / %d\nPot %d\n\n%s%s" % [round_num, total_rounds, pot, _players_text(), showdown_note])


func _players_text() -> String:
	var lines := []
	for s in n:
		var status := ""
		if chips[s] == 0 and (s >= in_hand.size() or not in_hand[s]):
			status = "  (out)"
		elif s < in_hand.size() and not in_hand[s]:
			status = "  (folded)"
		lines.append("%s: %d%s" % [bot_names[s], chips[s], status])
	return "\n".join(lines)


func _say(text: String, big := false) -> void:
	message.text = text
	message.add_theme_font_size_override("font_size", CAPTION_BIG if big else CAPTION_SIZE)
	print(text)
