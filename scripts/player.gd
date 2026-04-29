extends CharacterBody2D

signal died

const SPEED := 260.0
const JUMP_VELOCITY := -520.0
const GRAVITY := 1450.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.12

var spawn_position := Vector2.ZERO
var coyote_timer := 0.0
var jump_buffer_timer := 0.0

@onready var body: ColorRect = $Body


func _ready() -> void:
	spawn_position = global_position


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	velocity.x = move_toward(velocity.x, direction * SPEED, SPEED * 8.0 * delta)

	if not is_on_floor():
		velocity.y += GRAVITY * delta
		coyote_timer -= delta
	else:
		coyote_timer = COYOTE_TIME

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		jump_buffer_timer -= delta

	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0

	move_and_slide()
	_update_squash(direction)

	if global_position.y > 980.0:
		died.emit()


func reset_to_spawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO


func _update_squash(direction: float) -> void:
	body.scale.x = 1.0
	body.scale.y = 1.0

	if not is_on_floor():
		body.scale.x = 0.92
		body.scale.y = 1.08
	elif abs(direction) > 0.1:
		body.scale.x = 1.04
		body.scale.y = 0.96
