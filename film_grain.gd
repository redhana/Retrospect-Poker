extends TextureRect
@onready var rng = RandomNumberGenerator.new()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	texture.noise.seed = rng.randi()
