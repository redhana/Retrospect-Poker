extends GPUParticles3D
## Soft rising cigarette smoke. Attach to a GPUParticles3D placed at the glowing tip.
## Everything is set up in code, so the Inspector settings for this node don't matter.

@export var puff_size := 0.06          ## size of each wisp in metres
@export var rise_speed := 0.05         ## how fast it drifts up
@export var opacity := 0.22            ## 0 = invisible, 1 = solid
@export var smoke_color := Color(0.85, 0.85, 0.85)
@export var drift := 0.25              ## curly sideways wander (turbulence)
@export var wisps := 24                ## how many puffs exist at once


func _ready() -> void:
	amount = wisps
	lifetime = 4.0
	preprocess = 4.0                   # already smoking when the game starts
	local_coords = false               # smoke stays in the air if the cigarette moves

	# --- how the puffs move
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = puff_size * 0.08
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = rise_speed * 0.5
	pm.initial_velocity_max = rise_speed
	pm.gravity = Vector3(0, rise_speed * 0.4, 0)   # keeps gently rising
	pm.damping_min = 0.005
	pm.damping_max = 0.01
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2

	var grow := Curve.new()                        # puffs swell as they rise
	grow.add_point(Vector2(0, 0.25))
	grow.add_point(Vector2(1, 2.2))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex

	var fade := Gradient.new()                     # fade in quickly, fade out slowly
	fade.set_color(0, Color(smoke_color, 0.0))
	fade.set_color(1, Color(smoke_color, 0.0))
	fade.add_point(0.25, Color(smoke_color, opacity))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex

	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = drift
	pm.turbulence_noise_scale = 2.0
	process_material = pm

	# --- what each puff looks like: a soft round blob that always faces the camera
	var blob := Gradient.new()
	blob.set_color(0, Color(1, 1, 1, 1))
	blob.set_color(1, Color(1, 1, 1, 0))
	var blob_tex := GradientTexture2D.new()
	blob_tex.gradient = blob
	blob_tex.fill = GradientTexture2D.FILL_RADIAL
	blob_tex.fill_from = Vector2(0.5, 0.5)
	blob_tex.fill_to = Vector2(0.5, 0.0)
	blob_tex.width = 64
	blob_tex.height = 64

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = blob_tex
	mat.render_priority = draw_order   # drawn after (on top of) the camera's full-screen effect

	var quad := QuadMesh.new()
	quad.size = Vector2(puff_size, puff_size)
	quad.material = mat
	draw_pass_1 = quad

	sorting_offset = 1.0               # also nudge it ahead of other see-through things nearby
	emitting = true
	restart()
