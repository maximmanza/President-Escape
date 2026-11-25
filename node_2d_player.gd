extends CharacterBody2D

const SPEED := 290.0
const SNEAK_SPEED := 90.0
const GRAVITY := 1250.0
@onready var sprite: Sprite2D = $TrumpSprite
var walk_phase := 0.0

func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction += 1.0
	var current_speed := SNEAK_SPEED if Input.is_key_pressed(KEY_SHIFT) else SPEED
	velocity.x = clampf(direction, -1.0, 1.0) * current_speed
	if absf(direction) > 0.01:
		walk_phase += delta * (8.0 if Input.is_key_pressed(KEY_SHIFT) else 13.0)
		sprite.flip_h = direction < 0.0
		sprite.position.y = -8.0 + absf(sin(walk_phase)) * 2.2
		sprite.rotation = sin(walk_phase) * 0.025
	else:
		sprite.position.y = move_toward(sprite.position.y, -8.0, 22.0 * delta)
		sprite.rotation = move_toward(sprite.rotation, 0.0, 0.25 * delta)
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	position.x = clampf(position.x, 25.0, 2160.0)
