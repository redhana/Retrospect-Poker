class_name UIStyle
extends RefCounted
## Shared look for all menus + buttons: Joy's paper-and-tape strip, hand-printed font,
## slight random tilt, cream normally / deep red on hover.
## Files used: res://ui/paper_button.png, res://ui/PatrickHand-Regular.ttf

const BUTTON_TEX := "res://ui/paper_button.png"
const FONT_PATH := "res://ui/Cinzel.ttf"                # in-game text (was PatrickHand-Regular.ttf)
const MENU_FONT_PATH := "res://ui/Cinzel.ttf"          # carved, Roman-style capitals for menus
const ORNAMENT_PATH := "res://ui/ornament.png"         # flourish shown either side of a hovered menu option
const ORNAMENT_FLIP := false                          # true if the flourishes point the wrong way
const ORNAMENT_COLOR := Color(0.93, 0.9, 0.86)        # flourish tint (the image is white so it can be any colour)
const MENU_TEXT := Color(0.93, 0.9, 0.86)
const MENU_TEXT_HOVER := Color(1, 1, 1)

const PAPER := Color(0.96, 0.94, 0.90)       # normal paper tint (cream)
const PAPER_HOVER := Color(0.48, 0.12, 0.15) # hover tint (deep red)
const INK := Color(0.16, 0.13, 0.13)         # normal text
const INK_HOVER := Color(1, 0.97, 0.93)      # text on red
const TEXT_HOVER := Color(1, 0.55, 0.55)     # plain text buttons on hover (light red)
const MAX_TILT := 2.5                        # degrees of random wonkiness

static var _font: Font
static var _menu_font: Font


static func font() -> Font:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	return _font


static func menu_font() -> Font:
	if _menu_font == null and ResourceLoader.exists(MENU_FONT_PATH):
		_menu_font = load(MENU_FONT_PATH)
	return _menu_font


## Title-menu option: plain text in the menu font. On hover a flourish fades in on both sides.
## Add `button.get_parent()` (the row) to your VBox, not the button itself.
static func menu_button(text: String, font_size := 34) -> Button:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var left := _ornament(not ORNAMENT_FLIP)
	var b := Button.new()
	b.text = text
	b.flat = true
	if menu_font():
		b.add_theme_font_override("font", menu_font())
	b.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", MENU_TEXT)
	b.add_theme_color_override("font_hover_color", MENU_TEXT_HOVER)
	b.add_theme_color_override("font_pressed_color", MENU_TEXT_HOVER)
	b.add_theme_color_override("font_focus_color", MENU_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(MENU_TEXT, 0.35))
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("shadow_offset_y", 2)
	b.add_theme_constant_override("shadow_outline_size", 4)
	var right := _ornament(ORNAMENT_FLIP)

	row.add_child(left)
	row.add_child(b)
	row.add_child(right)
	b.mouse_entered.connect(func(): _show_ornaments(left, right, true))
	b.mouse_exited.connect(func(): _show_ornaments(left, right, false))
	return b


## Label in the menu font (headings, setting names on the title screen).
static func menu_label(text: String, font_size := 28, col := MENU_TEXT) -> Label:
	var l := label(text, font_size, col)
	if menu_font():
		l.add_theme_font_override("font", menu_font())
	l.add_theme_constant_override("shadow_outline_size", 2)   # lighter shadow suits the thin capitals
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func _ornament(flip: bool) -> TextureRect:
	var t := TextureRect.new()
	if ResourceLoader.exists(ORNAMENT_PATH):
		t.texture = load(ORNAMENT_PATH)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(46, 30)
	t.flip_h = flip
	t.modulate = Color(ORNAMENT_COLOR, 0.0)          # hidden until hover
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func _show_ornaments(left: TextureRect, right: TextureRect, on: bool) -> void:
	for o in [left, right]:
		o.create_tween().tween_property(o, "modulate:a", 1.0 if on else 0.0, 0.15)


## A paper-strip button. size keeps roughly the strip's 4:1 shape.
## The button sits inside a plain "holder" Control so containers don't undo its tilt:
## add `button.get_parent()` to your VBox/HBox, not the button itself.
static func paper_button(text: String, size := Vector2(300, 74), font_size := 34) -> Button:
	var holder := Control.new()
	holder.custom_minimum_size = size
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.text = text
	holder.add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if font():
		b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", font_size)

	b.add_theme_stylebox_override("normal", _paper(PAPER))
	b.add_theme_stylebox_override("hover", _paper(PAPER_HOVER))
	b.add_theme_stylebox_override("pressed", _paper(PAPER_HOVER.darkened(0.2)))
	b.add_theme_stylebox_override("disabled", _paper(Color(0.6, 0.58, 0.55, 0.55)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK_HOVER)
	b.add_theme_color_override("font_pressed_color", INK_HOVER)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_disabled_color", Color(0.3, 0.28, 0.28, 0.6))

	# hand-placed look: tiny random tilt, pivot in the middle
	b.rotation_degrees = randf_range(-MAX_TILT, MAX_TILT)
	b.resized.connect(func(): b.pivot_offset = b.size / 2)

	# grow a little on hover
	b.mouse_entered.connect(func(): _hover(b, true))
	b.mouse_exited.connect(func(): _hover(b, false))
	return b


static func _hover(b: Button, on: bool) -> void:
	var target := Vector2(1.06, 1.06) if on and not b.disabled else Vector2.ONE
	b.create_tween().tween_property(b, "scale", target, 0.12)


## Plain text button: white hand-printed text with a shadow, no background.
## Turns warm on hover and grows slightly. Add `button.get_parent()` to containers.
static func text_button(text: String, font_size := 36) -> Button:
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.text = text
	b.flat = true
	holder.add_child(b)
	if font():
		b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(1, 0.98, 0.95))
	b.add_theme_color_override("font_hover_color", TEXT_HOVER)
	b.add_theme_color_override("font_pressed_color", TEXT_HOVER.darkened(0.2))
	b.add_theme_color_override("font_focus_color", Color(1, 0.98, 0.95))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	
	# size the holder to the text, keep the pivot centred for the hover grow
	var fit := func():
		holder.custom_minimum_size = b.get_combined_minimum_size() + Vector2(24, 8)
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.pivot_offset = holder.custom_minimum_size / 2
	fit.call()
	b.minimum_size_changed.connect(fit)
	b.mouse_entered.connect(func(): _hover(b, true))
	b.mouse_exited.connect(func(): _hover(b, false))
	return b


## A slider in the same style: thin dark track, cream fill, round grabber.
static func slider(min_v: float, max_v: float, step: float, value: float, width := 360.0) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step
	sl.value = value
	sl.custom_minimum_size = Vector2(width, 32)
	sl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.22)           # faint light line (visible on dark backgrounds)
	track.set_corner_radius_all(4)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := StyleBoxFlat.new()
	fill.bg_color = PAPER
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	var fill_hover := fill.duplicate()
	fill_hover.bg_color = TEXT_HOVER
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill_hover)
	sl.add_theme_icon_override("grabber", _diamond(Color.WHITE))
	sl.add_theme_icon_override("grabber_highlight", _diamond(TEXT_HOVER))
	sl.focus_mode = Control.FOCUS_NONE
	return sl

## Small diamond for slider handles (soft-edged so it isn't jagged).
static func _diamond(col: Color, d := 16) -> Texture2D:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d / 2.0
	for y in d:
		for x in d:
			var dist := absf(x + 0.5 - r) + absf(y + 0.5 - r)   # "diamond distance" from the centre
			var a := clampf(r - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)

static func _dot(col: Color, d := 22) -> Texture2D:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d / 2.0
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - dist, 0.0, 1.0)              # soft edge
			var c := col if dist < r - 3 else Color(0.1, 0.08, 0.08)   # dark outline
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


## A text label in the hand-printed font with a soft shadow (for captions, HUD).
static func label(text: String, font_size := 28, col := Color(0.97, 0.94, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	if font():
		l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l
	return l


static func _paper(tint: Color) -> StyleBox:
	if not ResourceLoader.exists(BUTTON_TEX):
		var flat := StyleBoxFlat.new()        # fallback if the image is missing
		flat.bg_color = tint
		flat.set_corner_radius_all(4)
		return flat
	var sb := StyleBoxTexture.new()
	sb.texture = load(BUTTON_TEX)
	sb.modulate_color = tint
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	return sb
