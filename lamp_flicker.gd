extends SpotLight3D

@export var min_wait := 2.0        ## seconds between flickers (shortest)
@export var max_wait := 5.0        ## seconds between flickers (longest)
@export var dim := 0.85            ## how low it dips (0.85 = 15% dimmer)
@export var dim_time := 0.3        ## how long each dip lasts (seconds)
@export var blinks := 2            ## dips per flicker

var base := 0.0

func _ready():
	base = light_energy
	_flicker_loop()

func _flicker_loop() -> void:
	while true:
		await get_tree().create_timer(randf_range(min_wait, max_wait)).timeout
		for i in randi_range(1, blinks):
			light_energy = base * randf_range(dim, 1.0 - (1.0 - dim) / 2)
			await get_tree().create_timer(dim_time * randf_range(0.7, 1.3)).timeout
			light_energy = base
			await get_tree().create_timer(randf_range(0.05, 0.15)).timeout
