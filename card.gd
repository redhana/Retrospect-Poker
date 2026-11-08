class_name Card
extends Node3D
## One playing card, using Joy's artwork from res://cards/.
##   Face: res://cards/<suit>.png   (or <suit>_<rank>.png if it exists, e.g. hearts_Q.png)
##   Back: res://cards/back.png
## The rank + small suit symbol in the corners are added by code, so 4 paintings cover all 52 cards.
## Local layout: card lies flat in the XZ plane, FACE points +Y, top edge points -Z.

const SCALE := 2                         # <-- change this to resize ALL cards
const SIZE := Vector2(0.07, 0.1) * SCALE    # width (x), length (z) in metres  (7:10, same as the art)
const THICK := 0.0007
const ART_PX := Vector2(1400, 2000)         # artwork size; corner text is placed in these pixel units

const CARD_DIR := "res://cards/"
const SUIT_FILES := ["spades", "hearts", "diamonds", "clubs"]
const SUITS := ["♠", "♥", "♦", "♣"]
const FACES := {11: "J", 12: "Q", 13: "K", 14: "A"}
const INK := Color("720f19ff")               # colour of the corner numbers + symbols
const PAPER := Color8(223, 219, 201)        # card edge colour (matches the art background)
const CORNER_RADIUS := 0.06                # rounded corners, as a fraction of the card's length

var suit := 0   # 0 spades, 1 hearts, 2 diamonds, 3 clubs
var rank := 2   # 2..14 (14 = ace)

static var _shader: Shader
static var _mats := {}                      # texture path -> ShaderMaterial (shared between cards)
static var _font: Font
static var _edge_mat: StandardMaterial3D

const SHADER_CODE := """
shader_type spatial;
render_mode cull_back;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float aspect = 0.7;
uniform float radius = 0.045;
void fragment() {
	// cut the corners off in a rounded-rectangle shape
	vec2 half_size = vec2(aspect, 1.0) * 0.5;
	vec2 p = UV * vec2(aspect, 1.0) - half_size;
	vec2 q = abs(p) - (half_size - vec2(radius));
	if (length(max(q, 0.0)) > radius) {
		discard;
	}
	ALBEDO = texture(tex, UV).rgb;
	ROUGHNESS = 0.75;
}
"""


func setup(s: int, r: int) -> void:
	suit = s
	rank = r
	name = "%s%s" % [rank_text(), ["S", "H", "D", "C"][s]]
	_build()


func rank_text() -> String:
	return FACES.get(rank, str(rank))


func is_face_up() -> bool:
	return global_transform.basis.y.y > 0.0


# ---------------------------------------------------------------- animation

## Fly to a slot (any Node3D). Re-reads the slot's position every frame,
## so it can chase a moving target (e.g. a slot attached to the camera).
## attach = become the slot's child at the end (so it then follows it).
func fly_to(target: Node3D, face_up: bool, duration := 0.4, arc := 0.1,
		attach := false, offset := Vector3.ZERO) -> void:
	var start := global_transform
	var down := Basis(Vector3(0, 0, 1), PI)
	var step := func(p: float) -> void:
		var goal := target.global_transform
		if not face_up:
			goal.basis = goal.basis * down
		goal.origin += offset
		var g := start.interpolate_with(goal, p)
		g.origin += Vector3.UP * sin(p * PI) * arc   # little hop
		global_transform = g
	var t := create_tween()
	t.tween_method(step, 0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t.finished
	if attach:
		reparent(target)
		transform = Transform3D(Basis.IDENTITY if face_up else down, Vector3.ZERO)


## Flip over in place along the card's long edge, with a small lift.
func flip(duration := 0.35, lift := 0.05) -> void:
	Sound.play("flip")
	var start := global_transform
	var step := func(p: float) -> void:
		var g := start
		g.basis = start.basis * Basis(Vector3(0, 0, 1), PI * p)
		g.origin = start.origin + Vector3.UP * sin(p * PI) * lift
		global_transform = g
	var t := create_tween()
	t.tween_method(step, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished


# ---------------------------------------------------------------- visuals

func _build() -> void:
	_load_shared()

	# card body: two crossed thin boxes = a rectangle with notched corners,
	# so no square corner sticks out past the rounded face
	var r := CORNER_RADIUS * SIZE.y
	_box(Vector3(SIZE.x - 0.0004, THICK, SIZE.y - 2 * r))
	_box(Vector3(SIZE.x - 2 * r, THICK, SIZE.y - 0.0004))

	# face (+Y) and back (-Y)
	var face_tex := _find_face()
	_plane(face_tex, false)
	_plane(CARD_DIR + "back.png", true)

	# corner index: rank + suit, top-left and (upside down) bottom-right
	var suit_size := 120 if face_tex != "" else 400
	_label(rank_text(), 350, Vector2(230, 250), false)
	_label(SUITS[suit], 280, Vector2(230, 520), false)
	_label(rank_text(), 350, Vector2(230, 250), true)
	_label(SUITS[suit], 280, Vector2(230, 520), true)
	if face_tex == "":
		_label(SUITS[suit], 400, ART_PX / 2, false)   # no artwork found: big symbol instead


func _find_face() -> String:
	var base: String = CARD_DIR + SUIT_FILES[suit]
	for path in [base + "_" + rank_text() + ".png", base + ".png"]:
		if ResourceLoader.exists(path):
			return path
	push_warning("Card art missing: " + base + ".png")
	return ""


func _plane(tex_path: String, is_back: bool) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = SIZE
	plane.flip_faces = is_back          # back plane is visible from below (-Y)
	mi.mesh = plane
	mi.material_override = _material(tex_path)
	mi.position.y = (THICK / 2 + 0.0001) * (-1.0 if is_back else 1.0)
	add_child(mi)


func _box(size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _edge_mat
	mi.mesh = box
	add_child(mi)


func _material(tex_path: String) -> Material:
	if _mats.has(tex_path):
		return _mats[tex_path]
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("aspect", SIZE.x / SIZE.y)
	m.set_shader_parameter("radius", CORNER_RADIUS)
	if tex_path != "" and ResourceLoader.exists(tex_path):
		m.set_shader_parameter("tex", load(tex_path))
	else:
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(PAPER)
		m.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	_mats[tex_path] = m
	return m


## Text placed using artwork pixel coordinates (0,0 = top-left of the 1400x2000 art).
func _label(text: String, size_px: int, art_pos: Vector2, upside_down: bool) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = size_px
	l.pixel_size = SIZE.y / ART_PX.y      # 1 font pixel = 1 artwork pixel
	l.modulate = INK
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pos := art_pos
	if upside_down:
		pos = ART_PX - art_pos
	l.position = Vector3((pos.x / ART_PX.x - 0.5) * SIZE.x, THICK / 2 + 0.0003, (pos.y / ART_PX.y - 0.5) * SIZE.y)
	l.rotation = Vector3(-PI / 2, PI if upside_down else 0.0, 0)
	add_child(l)


static func _load_shared() -> void:
	if _shader != null:
		return
	_shader = Shader.new()
	_shader.code = SHADER_CODE
	_edge_mat = StandardMaterial3D.new()
	_edge_mat.albedo_color = PAPER
	_edge_mat.roughness = 0.8
	# serif font for numbers, with a fallback font that has the ♠♥♦♣ symbols
	var main_path := CARD_DIR + "PlayfairDisplay.ttf"
	var sym_path := CARD_DIR + "DejaVuSerif.ttf"
	if ResourceLoader.exists(main_path):
		_font = load(main_path).duplicate()
		if ResourceLoader.exists(sym_path):
			_font.fallbacks = [load(sym_path)]
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Baskerville", "Georgia", "Times New Roman", "DejaVu Serif"])
		_font = sf


# ---------------------------------------------------------------- outline (Time Jump selection)

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 col : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform float aspect = 0.7;
uniform float radius = 0.07;
void fragment() {
	vec2 half_size = vec2(aspect, 1.0) * 0.5;
	vec2 p = UV * vec2(aspect, 1.0) - half_size;
	vec2 q = abs(p) - (half_size - vec2(radius));
	if (length(max(q, 0.0)) > radius) {
		discard;
	}
	ALBEDO = col.rgb * (0.85 + 0.15 * sin(TIME * 5.0));   // gentle pulse
	
}
"""

static var _outline_shader: Shader
var _outline: MeshInstance3D


## Glowing outline round the card face. Pass Color(0, 0, 0, 0) to hide it.
func set_outline(col: Color) -> void:
	if _outline == null:
		if _outline_shader == null:
			_outline_shader = Shader.new()
			_outline_shader.code = OUTLINE_SHADER
		_outline = MeshInstance3D.new()
		var plane := PlaneMesh.new()
		var pad := SIZE.y * 0.06                       # outline thickness
		plane.size = SIZE + Vector2(pad, pad)
		_outline.mesh = plane
		var m := ShaderMaterial.new()
		m.shader = _outline_shader
		m.set_shader_parameter("aspect", plane.size.x / plane.size.y)
		_outline.material_override = m
		_outline.position.y = THICK / 2 + 0.00005       # just under the face picture
		_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_outline)
	_outline.visible = col.a > 0.0
	(_outline.material_override as ShaderMaterial).set_shader_parameter("col", col)

# ---------------------------------------------------------------- dimmed (greyed out in the past view)

var _dim: MeshInstance3D


## Darken the card face (can't be picked).
func set_dimmed(on: bool) -> void:
	if _dim == null:
		if _outline_shader == null:
			_outline_shader = Shader.new()
			_outline_shader.code = OUTLINE_SHADER
		_dim = MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = SIZE
		_dim.mesh = plane
		var m := ShaderMaterial.new()
		m.shader = _outline_shader                        # same rounded shape as the card
		m.set_shader_parameter("aspect", SIZE.x / SIZE.y)
		m.set_shader_parameter("radius", CORNER_RADIUS)
		m.set_shader_parameter("col", Color(0, 0, 0, 0.7))
		_dim.material_override = m
		_dim.position.y = THICK / 2 + 0.0006            # above the picture and corner text
		_dim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_dim)
	_dim.visible = on
	
	
	# ---------------------------------------------------------------- morph (Time Jump swap)

## Turn this card into a different one with a quick squash-and-reveal.
## instant = no animation (used when putting cards back to normal after a round).
func morph_to(s: int, r: int, instant := false) -> void:
	if instant:
		_rebuild(s, r)
		return
	var t := create_tween()
	t.tween_property(self, "scale:x", 0.02, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished
	_rebuild(s, r)
	var t2 := create_tween()
	t2.tween_property(self, "scale:x", 1.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t2.finished


func _rebuild(s: int, r: int) -> void:
	for child in get_children():
		child.free()
	_outline = null
	_dim = null
	setup(s, r)
