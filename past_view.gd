class_name PastView
extends Node
## Time Jump "past view": the screen goes black and white and the table shows a recorded round.
## < > browse rounds. Click one of your own past cards to pick it; Esc / "Back to the present" cancels.
##
## Used by poker_game.gd:   var pick := await past_view.open(table, round_log, give_card, visible_now)
## Returns {} if cancelled, otherwise {"round_index", "card_index", "card"}.

signal _picked(result: Dictionary)

# colours don't survive black-and-white, so in the past: soft grey outline, hover = bright white
const OUTLINE_IDLE := Color(0.45, 0.45, 0.45)
const OUTLINE_HOVER := Color(1.0, 1.0, 1.0)
const SUIT_SYMBOLS := ["♠", "♥", "♦", "♣"]
const RANKS := {11: "J", 12: "Q", 13: "K", 14: "A"}

const GREY_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(g) * vec3(1.02, 1.0, 0.97), amount), 1.0);   // slightly warm grey
}
"""

var table: Node3D
var rounds: Array = []
var give: Vector2i
var visible_now: Array = []
var idx := 0
var active := false

var ghosts: Array[Card] = []
var pickable: Array = []          # [[ghost Card, index in past hand], ...]
var hover: Card = null
var hidden: Array = []

var grey_layer: CanvasLayer
var grey: ColorRect
var ui: CanvasLayer
var title: Label
var info: Label
var note: Label
var left_btn: Button
var right_btn: Button


func open(p_table: Node3D, p_rounds: Array, p_give: Vector2i, p_visible_now: Array) -> Dictionary:
	table = p_table
	rounds = p_rounds
	give = p_give
	visible_now = p_visible_now
	idx = rounds.size() - 1                       # start on the most recent round
	_make_ui()

	# hide the present-day cards on the table (the deck stays)
	for c in table.all_cards:
		if c.visible and not (c in table.deck):
			c.visible = false
			hidden.append(c)

	active = true
	create_tween().tween_method(_set_grey, 0.0, 1.0, 0.7)
	_show_round()

	var result: Dictionary = await _picked

	# back to the present
	active = false
	_clear_ghosts()
	for c in hidden:
		c.visible = true
	hidden.clear()
	ui.visible = false
	var t := create_tween()
	t.tween_method(_set_grey, 1.0, 0.0, 0.7)
	await t.finished
	grey_layer.queue_free()
	ui.queue_free()
	return result


#  showing a round

func _show_round() -> void:
	_clear_ghosts()
	var rec: Dictionary = rounds[idx]
	var n: int = rec.hands.size()
	var round_blocked: bool = give in rec.community   # your card was on the table back then

	title.text = "Round %d" % rec.round
	info.text = rec.summary
	note.text = ""

	# community cards that were dealt
	for i in rec.community.size():
		_ghost(rec.community[i], table.community_slots[i], true)

	# bots: revealed at showdown -> face up on the table; still in -> floating backs; folded -> gone
	for s in range(1, n):
		if rec.folded[s]:
			continue
		for k in rec.hands[s].size():
			if rec.showdown:
				_ghost(rec.hands[s][k], table.seat_slots[s][k], true)
			else:
				_ghost(rec.hands[s][k], table.opp_hand_slots[s][k], true)

	# your past hand, floating in front of you
	for k in rec.hands[0].size():
		var v: Vector2i = rec.hands[0][k]
		var g := _ghost(v, table.hand_slots[k], true)
		if round_blocked or v in visible_now:
			g.set_dimmed(true)
		else:
			g.set_outline(OUTLINE_IDLE)
			pickable.append([g, k])

	if round_blocked:
		note.text = "Your %s was on the table this round, so you can't send it here" % _name(give)
	elif pickable.is_empty():
		note.text = "Both of these cards are in play right now"
	elif rec.folded[0]:
		note.text = "You folded this round. Un-folding costs %d" % unfold_cost(rec)

	left_btn.disabled = idx == 0
	right_btn.disabled = idx == rounds.size() - 1


## Chips you'd still have needed to put in to stay in a round you folded.
static func unfold_cost(rec: Dictionary, seat := 0) -> int:
	var top := 0
	for s in rec.put_in.size():
		if not rec.folded[s]:
			top = maxi(top, rec.put_in[s])
	return maxi(top - rec.put_in[seat], 0)


func _ghost(v: Vector2i, slot: Node3D, face_up: bool) -> Card:
	var g := Card.new()
	slot.add_child(g)
	g.setup(v.y, v.x)
	g.transform = Transform3D.IDENTITY if face_up else Transform3D(Basis(Vector3(0, 0, 1), PI), Vector3.ZERO)
	g.scale = Vector3.ONE * 0.6
	g.create_tween().tween_property(g, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ghosts.append(g)
	return g


func _clear_ghosts() -> void:
	for g in ghosts:
		g.queue_free()
	ghosts.clear()
	pickable.clear()
	hover = null


func _browse(step: int) -> void:
	var new_idx := clampi(idx + step, 0, rounds.size() - 1)
	if new_idx == idx:
		return
	idx = new_idx
	Sound.play("click")
	_show_round()


#  picking

func _process(_delta: float) -> void:
	if not active or pickable.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var best: Card = null
	var best_t := INF
	for pair in pickable:
		var c: Card = pair[0]
		var nrm: Vector3 = c.global_basis.y
		var denom := nrm.dot(dir)
		if absf(denom) < 0.0001:
			continue
		var t := nrm.dot(c.global_position - from) / denom
		if t <= 0.0 or t >= best_t:
			continue
		var local: Vector3 = c.global_transform.affine_inverse() * (from + dir * t)
		if absf(local.x) <= Card.SIZE.x / 2 and absf(local.z) <= Card.SIZE.y / 2:
			best = c
			best_t = t
	if best != hover:
		hover = best
		for pair in pickable:
			var g: Card = pair[0]
			var on: bool = g == hover
			g.set_outline(OUTLINE_HOVER if on else OUTLINE_IDLE)
			var t := g.create_tween().set_parallel()
			t.tween_property(g, "scale", Vector3.ONE * (1.1 if on else 1.0), 0.12)
			t.tween_property(g, "position:y", 0.012 if on else 0.0, 0.12)   # lifts toward you


func _input(e: InputEvent) -> void:
	if not active:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				Sound.play("click")
				_picked.emit({})
			KEY_LEFT:
				get_viewport().set_input_as_handled()
				if idx > 0: _browse(-1)
			KEY_RIGHT:
				get_viewport().set_input_as_handled()
				if idx < rounds.size() - 1: _browse(1)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and hover != null:
		get_viewport().set_input_as_handled()
		for pair in pickable:
			if pair[0] == hover:
				Sound.play("click")
				var rec: Dictionary = rounds[idx]
				_picked.emit({"round_index": idx, "card_index": pair[1], "card": rec.hands[0][pair[1]]})
				return


#  UI

func _make_ui() -> void:
	grey_layer = CanvasLayer.new()
	grey_layer.layer = 5                            # above the 3D + game HUD, below this view's UI
	add_child(grey_layer)
	grey = ColorRect.new()
	grey.set_anchors_preset(Control.PRESET_FULL_RECT)
	grey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GREY_SHADER
	sm.shader = sh
	grey.material = sm
	grey_layer.add_child(grey)

	ui = CanvasLayer.new()
	ui.layer = 6
	add_child(ui)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 16
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	ui.add_child(top)
	title = UIStyle.label("", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	info = UIStyle.label("", 28)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(info)
	note = UIStyle.label("", 26, Color(1, 0.75, 0.7))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(note)

	# < and > on each side
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(row)
	left_btn = UIStyle.text_button("<", 110)
	left_btn.pressed.connect(_browse.bind(-1))
	var lh := left_btn.get_parent() as Control
	lh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lh)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	right_btn = UIStyle.text_button(">", 110)
	right_btn.pressed.connect(_browse.bind(1))
	var rh := right_btn.get_parent() as Control
	rh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rh)

	_make_give_card()

	# back to the present
	var back := UIStyle.text_button("Back to the present", 30)
	back.pressed.connect(func():
		Sound.play("click")
		_picked.emit({}))
	top.add_child(back.get_parent())


## The card you're sending back, shown in full colour on the left (drawn above the grey filter).
func _make_give_card() -> void:
	var side := VBoxContainer.new()
	side.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	side.offset_left = 110
	side.offset_top = -150
	side.add_theme_constant_override("separation", 8)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(side)

	var lbl := UIStyle.label("Sending back", 26)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(lbl)

	# rounded card with the artwork, clipped to its shape
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(150, 214)                 # 7:10, same as the cards
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var sb := StyleBoxFlat.new()
	sb.bg_color = Card.PAPER
	sb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", sb)
	side.add_child(frame)

	var art_path := _art_path(give)
	if art_path != "":
		var art := TextureRect.new()
		art.texture = load(art_path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(art)

	# corner index, same colour + font as the real cards
	Card._load_shared()
	for flip in [false, true]:
		var idx_lbl := Label.new()
		idx_lbl.text = _name_lines(give)
		idx_lbl.add_theme_font_override("font", Card._font)
		idx_lbl.add_theme_font_size_override("font_size", 24)
		idx_lbl.add_theme_color_override("font_color", Card.INK)
		idx_lbl.add_theme_constant_override("line_spacing", -6)
		idx_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		idx_lbl.size = Vector2(30, 60)
		if flip:
			idx_lbl.position = frame.custom_minimum_size - Vector2(38, 66)
			idx_lbl.pivot_offset = idx_lbl.size / 2
			idx_lbl.rotation_degrees = 180
		else:
			idx_lbl.position = Vector2(8, 6)
		frame.add_child(idx_lbl)

	# soft white border so it stands out
	var border := Panel.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0, 0, 0, 0)
	bsb.border_color = Color(1, 1, 1, 0.9)
	bsb.set_border_width_all(3)
	bsb.set_corner_radius_all(10)
	border.add_theme_stylebox_override("panel", bsb)
	frame.add_child(border)

	var name_lbl := UIStyle.label(_name(give), 30)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(name_lbl)


func _art_path(v: Vector2i) -> String:
	var base: String = Card.CARD_DIR + Card.SUIT_FILES[v.y]
	for path in [base + "_" + RANKS.get(v.x, str(v.x)) + ".png", base + ".png"]:
		if ResourceLoader.exists(path):
			return path
	return ""


func _name_lines(v: Vector2i) -> String:
	return RANKS.get(v.x, str(v.x)) + "\n" + SUIT_SYMBOLS[v.y]


func _set_grey(v: float) -> void:
	(grey.material as ShaderMaterial).set_shader_parameter("amount", v)


func _name(v: Vector2i) -> String:
	return RANKS.get(v.x, str(v.x)) + SUIT_SYMBOLS[v.y]
