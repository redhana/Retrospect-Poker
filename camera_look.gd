extends Camera3D

@export var sens := 0.002        # mouse sensitivity
@export var yaw_limit := 25.0    # degrees left/right (was 60)
@export var pitch_up := 20.0     # degrees up (was 30)
@export var pitch_down := 15.0   # degrees down (was 40)
@export var smoothing := 6.0     # lower = slower/laggier, higher = snappier
@export var follow_mouse := true          ## when the mouse is visible, the view follows it
@export var follow_amount := 0.6          ## 1 = mouse at the screen edge turns all the way to your limit

var start_rot: Vector3
var target_yaw := 0.0
var target_pitch := 0.0
var yaw := 0.0
var pitch := 0.0

func _ready():
	start_rot = rotation
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e):
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		target_yaw   -= e.relative.x * sens
		target_pitch -= e.relative.y * sens
		target_yaw   = clamp(target_yaw,   deg_to_rad(-yaw_limit),  deg_to_rad(yaw_limit))
		target_pitch = clamp(target_pitch, deg_to_rad(-pitch_down), deg_to_rad(pitch_up))
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	

func _process(delta):
	# move a fraction of the remaining gap each frame → smooth ease-out
	if follow_mouse and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		var vp := get_viewport()
		var m := vp.get_mouse_position() / vp.get_visible_rect().size - Vector2(0.5, 0.5)   # -0.5 .. 0.5
		target_yaw = -m.x * 2.0 * deg_to_rad(yaw_limit) * follow_amount
		var lim := pitch_down if m.y > 0 else pitch_up
		target_pitch = -m.y * 2.0 * deg_to_rad(lim) * follow_amount
	
	var t = 1.0 - exp(-smoothing * delta)
	yaw   = lerp(yaw,   target_yaw,   t)
	pitch = lerp(pitch, target_pitch, t)
	rotation = start_rot + Vector3(pitch, yaw, 0)
