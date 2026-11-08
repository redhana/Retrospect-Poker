@tool
class_name ScoreSheet
extends Node3D
## A sheet of paper lying on the table with the round, pot and everyone's chips written on it.
## poker_game.gd writes to it with set_text() whenever the scores change.


@export var auto_fit := false:          ## on = paper shrinks/grows to fit the writing. Off = fixed paper
	set(v):
		auto_fit = v
		_rebuild()
@export var align_left := true:         ## on = text starts at the left margin. Off = centred
	set(v):
		align_left = v
		_rebuild()
@export var margin := 0.025:            ## gap between the paper edge and the writing, in metres
	set(v):
		margin = v
		_rebuild()
@export var paper_size := Vector2(0.34, 0.36):   ## paper width, length in metres
	set(v):
		paper_size = v
		_rebuild()
@export var paper_color := Color(0.78, 0.72, 0.6):
	set(v):
		paper_color = v
		_rebuild()
@export var ink_color := Color(0.2, 0.12, 0.12):
	set(v):
		ink_color = v
		_rebuild()
@export_file("*.ttf", "*.otf") var font_path := "res://ui/Caveat.ttf":
	set(v):
		font_path = v
		_rebuild()
@export var font_size := 52:            ## text size (bigger = easier to read through the pixel effect)
	set(v):
		font_size = v
		_rebuild()
@export var line_gap := -6.0:          ## space between lines (negative = closer together)
	set(v):
		line_gap = v
		_rebuild()
@export_range(0.0, 1.0) var glow := 0.08:   ## how much the paper lights itself (readable in the dark)
	set(v):
		glow = v
		_rebuild()
@export_multiline var preview_text := "Round 1 / 10\nPot 30\n\nYou  490\nBot Left  490\nBot Right  490":
	set(v):
		preview_text = v
		_rebuild()

var _label: Label3D
var _paper: MeshInstance3D
var _plane: PlaneMesh


func _ready() -> void:
	_rebuild()


## Called by the game to write on the sheet.
func set_text(t: String) -> void:
	if _label:
		_label.text = t
		_fit_paper()
		_place_text()


## Slide the text so its left edge sits on the paper's left margin (waits a frame for the layout).
func _place_text() -> void:
	if auto_fit or not align_left or _label == null:
		return
	await get_tree().process_frame
	if _label == null:
		return
	var box := _label.get_aabb()                        # box.position.x = left edge, relative to the label
	_label.position.x = (-paper_size.x / 2 + margin) - box.position.x


## Resize the paper around the writing (waits a frame so the text has been laid out).
func _fit_paper() -> void:
	if not auto_fit or _label == null:
		return
	await get_tree().process_frame
	if _label == null or _plane == null:
		return
	var box := _label.get_aabb()                       # text size, in the label's own flat space
	_plane.size = Vector2(box.size.x, box.size.y) + Vector2(margin, margin) * 2
	var c := box.get_center()
	_paper.position = Vector3(c.x, _paper.position.y, -c.y)   # keep paper centred under the text


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta("score_sheet_part"):
			c.free()

	# the paper
	var paper := MeshInstance3D.new()
	paper.set_meta("score_sheet_part", true)
	var plane := PlaneMesh.new()
	plane.size = paper_size
	paper.mesh = plane
	_paper = paper
	_plane = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = paper_color
	mat.roughness = 0.95
	mat.emission_enabled = true
	mat.emission = paper_color
	mat.emission_energy_multiplier = glow
	paper.material_override = mat
	paper.position.y = 0.0005                     # just above the felt
	add_child(paper)

	# the writing, lying flat on the paper
	_label = Label3D.new()
	_label.set_meta("score_sheet_part", true)
	_label.text = preview_text
	if ResourceLoader.exists(font_path):
		_label.font = load(font_path)
	_label.font_size = font_size
	_label.pixel_size = 0.0008
	_label.modulate = ink_color
	_label.outline_size = 0
	_label.shaded = false                         # always readable, even in shadow
	_label.double_sided = false
	_label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if align_left else HORIZONTAL_ALIGNMENT_CENTER
	_label.line_spacing = line_gap
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER   # text block sits in the middle of the paper
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label.rotation.x = -PI / 2                   # lie flat, top of the text away from you
	_label.position.y = 0.001
	add_child(_label)
	_fit_paper()
	_place_text()
