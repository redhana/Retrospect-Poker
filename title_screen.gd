extends Node
## Title screen: a camera slowly circles the table, with the game title and a Start button.
## Press Start -> the camera glides into your seat (the player camera) and the game begins.
##
## Setup: add a plain Node called "TitleScreen" to main.tscn, attach this script,
## drag your Camera (the first-person one) into "Player Camera",
## then on your Game node drag TitleScreen into its "Title Screen" slot.

signal started

@export var player_camera: Camera3D
@export var title_text := "POKER"
@export var subtitle_text := "a game against time"
@export var title_image: Texture2D                ## your logo. Left empty = uses res://ui/Title.png if it exists
@export var title_image_size := Vector2(700, 260)  ## how big the logo shows (it never squashes)
@export var orbit_centre := Vector3(0, 10, 0)   ## point the camera circles + looks at (table centre)
@export var orbit_radius := 4
@export var orbit_height := 1.1                   ## height above the centre
@export var orbit_speed := 0.12                   ## radians per second (slow = moody)
@export var fly_in_time := 2.5                    ## seconds to glide into your seat
@export_group("Table settings")
@export var chips_min := 100
@export var chips_max := 5000
@export var chips_default := 500
@export var ante_min := 5
@export var ante_max := 100
@export var ante_default := 10

var chosen_chips := 500          # read by poker_game.gd when the game starts
var chosen_ante := 10
var menu_box: VBoxContainer
var setup_box: VBoxContainer

var orbit_cam: Camera3D
var angle := 0.0
var orbiting := true
var layer: CanvasLayer
var panel: Control


func _ready() -> void:
	# orbit camera
	orbit_cam = Camera3D.new()
	orbit_cam.name = "OrbitCamera"
	get_tree().current_scene.add_child.call_deferred(orbit_cam)
	await get_tree().process_frame
	orbit_cam.fov = player_camera.fov
	orbit_cam.make_current()
	_update_orbit(0.0)

	# freeze the player's mouse-look until the game starts
	player_camera.set_process(false)
	player_camera.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_make_ui()


func _process(delta: float) -> void:
	if orbiting and orbit_cam:
		_update_orbit(delta)


func _update_orbit(delta: float) -> void:
	angle += orbit_speed * delta
	orbit_cam.global_position = orbit_centre + Vector3(cos(angle) * orbit_radius, orbit_height, sin(angle) * orbit_radius)
	orbit_cam.look_at(orbit_centre)


func _on_start() -> void:
	orbiting = false
	# fade the menu out
	var fade := create_tween()
	fade.tween_property(panel, "modulate:a", 0.0, 0.5)
	fade.tween_callback(func(): layer.visible = false)

	# glide from wherever the orbit camera is into the player's seat
	var from := orbit_cam.global_transform
	var fov_from := orbit_cam.fov
	var fly := func(p: float) -> void:
		orbit_cam.global_transform = from.interpolate_with(player_camera.global_transform, p)
		orbit_cam.fov = lerpf(fov_from, player_camera.fov, p)
	var t := create_tween()
	t.tween_method(fly, 0.0, 1.0, fly_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished

	# hand over to the real camera
	player_camera.make_current()
	player_camera.set_process(true)
	player_camera.set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	orbit_cam.queue_free()
	started.emit()


# ---------------------------------------------------------------- UI

func _make_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)

	# dark gradient behind the text so it reads over the 3D scene
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	menu_box = box

	if title_image == null and ResourceLoader.exists("res://ui/Title.png"):
		title_image = load("res://ui/Title.png")
	if title_image:
		var logo := TextureRect.new()
		logo.texture = title_image
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = title_image_size
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(logo)
	else:
		var title := UIStyle.menu_label(title_text, 110)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)
		var sub := UIStyle.menu_label(subtitle_text, 28, Color(0.9, 0.85, 0.78, 0.9))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	box.add_child(gap)

	var start_btn := UIStyle.menu_button("Play")
	start_btn.pressed.connect(_show_setup)
	box.add_child(start_btn.get_parent())

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 0)         # space between Play and Quit (bigger = further apart)
	box.add_child(gap2)

	var quit_btn := UIStyle.menu_button("Quit")
	quit_btn.pressed.connect(_quit)
	box.add_child(quit_btn.get_parent())

	_make_setup()
	_add_click_sounds(panel)

	# fade in
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 1.2)


# ---------------------------------------------------------------- table settings panel

func _make_setup() -> void:
	chosen_chips = chips_default
	chosen_ante = ante_default

	setup_box = VBoxContainer.new()
	setup_box.set_anchors_preset(Control.PRESET_CENTER)
	setup_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	setup_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	setup_box.alignment = BoxContainer.ALIGNMENT_CENTER
	setup_box.add_theme_constant_override("separation", 10)
	setup_box.visible = false
	panel.add_child(setup_box)

	var heading := UIStyle.menu_label("The Table", 60)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	setup_box.add_child(heading)
	_spacer(setup_box, 16)

	_setting(setup_box, "Starting chips (everyone)", chips_min, chips_max, 50, chips_default,
		func(v): chosen_chips = int(v))
	_spacer(setup_box, 10)
	_setting(setup_box, "Opening bet (paid each round)", ante_min, ante_max, 5, ante_default,
		func(v): chosen_ante = int(v))

	var note := UIStyle.menu_label("the smallest bet is double the opening bet", 18, Color(0.9, 0.85, 0.78, 0.7))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	setup_box.add_child(note)
	_spacer(setup_box, 24)

	var deal := UIStyle.menu_button("Deal")
	deal.pressed.connect(_on_start)
	setup_box.add_child(deal.get_parent())
	var back := UIStyle.menu_button("Back")
	back.pressed.connect(func():
		setup_box.visible = false
		menu_box.visible = true)
	setup_box.add_child(back.get_parent())


## A title + slider + live number, stacked.
func _setting(parent: Control, title: String, lo: int, hi: int, step: int, value: int, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var t := UIStyle.menu_label(title, 24)
	row.add_child(t)
	var num := UIStyle.menu_label(str(value), 28, Color(1, 0.8, 0.6))
	row.add_child(num)
	parent.add_child(row)
	var sl := UIStyle.slider(lo, hi, step, value, 420)
	sl.value_changed.connect(func(v):
		num.text = str(int(v))
		on_change.call(v))
	parent.add_child(sl)


func _spacer(parent: Control, h: int) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	parent.add_child(c)


func _show_setup() -> void:
	menu_box.visible = false
	setup_box.visible = true


## Every button on the title screens clicks when pressed (skips any that already click).
func _add_click_sounds(root: Node) -> void:
	for b in root.find_children("*", "BaseButton", true, false):
		if b.has_meta("clicks"):
			continue
		b.set_meta("clicks", true)
		b.pressed.connect(func(): Sound.play("click"))


## Let the click sound play before the window closes.
func _quit() -> void:
	await get_tree().create_timer(0.25).timeout
	get_tree().quit()
