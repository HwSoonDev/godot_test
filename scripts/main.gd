@tool
extends Node2D

const PLAYER_SCENE := preload("res://scripts/player.gd")
const PLAYER_START := Vector2(120.0, 520.0)
const WORLD_LIMIT_LEFT := -120.0
const WORLD_LIMIT_RIGHT := 2500.0

var player: CharacterBody2D
var coins_total := 0
var coins_collected := 0
var status_label: Label
var hint_label: Label
var win_label: Label
var coin_label: Label


func _ready() -> void:
	_clear_generated_nodes()
	coins_total = 0
	coins_collected = 0
	if not Engine.is_editor_hint():
		_register_input()
	_build_level()
	_build_ui()
	_update_coin_label()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if Input.is_action_just_pressed("restart"):
		_reset_level()


func _clear_generated_nodes() -> void:
	for child in get_children():
		if child.has_meta("generated_level"):
			child.queue_free()


func _register_input() -> void:
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_add_key_action("restart", [KEY_R])


func _add_key_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for key in keys:
		var already_added := false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and event.physical_keycode == key:
				already_added = true
				break

		if not already_added:
			var input := InputEventKey.new()
			input.physical_keycode = key
			InputMap.action_add_event(action, input)


func _build_level() -> void:
	RenderingServer.set_default_clear_color(Color.html("#7fc8ff"))

	var background := Node2D.new()
	background.name = "Background"
	_mark_generated(background)
	add_child(background)
	_add_backdrop(background)

	var platforms := Node2D.new()
	platforms.name = "Platforms"
	_mark_generated(platforms)
	add_child(platforms)

	_add_platform(platforms, Vector2(520, 650), Vector2(980, 60), Color.html("#376a45"))
	_add_platform(platforms, Vector2(1080, 520), Vector2(260, 44), Color.html("#426f87"))
	_add_platform(platforms, Vector2(1460, 415), Vector2(260, 44), Color.html("#426f87"))
	_add_platform(platforms, Vector2(1840, 560), Vector2(340, 44), Color.html("#426f87"))
	_add_platform(platforms, Vector2(2240, 470), Vector2(280, 44), Color.html("#426f87"))
	_add_platform(platforms, Vector2(2380, 650), Vector2(620, 60), Color.html("#376a45"))
	_add_platform(platforms, Vector2(-80, 725), Vector2(80, 220), Color.html("#2f5a3b"))
	_add_platform(platforms, Vector2(2780, 725), Vector2(80, 220), Color.html("#2f5a3b"))

	_add_hazard(Vector2(840, 610), Vector2(110, 38))
	_add_hazard(Vector2(1940, 520), Vector2(130, 38))

	for coin_position in [
		Vector2(320, 565),
		Vector2(690, 565),
		Vector2(1080, 445),
		Vector2(1460, 340),
		Vector2(1840, 485),
		Vector2(2240, 395),
	]:
		_add_coin(coin_position)

	_add_goal(Vector2(2540, 560))
	_add_player()


func _add_backdrop(parent: Node2D) -> void:
	_add_rect(parent, Vector2(1300, 745), Vector2(2800, 190), Color.html("#4ca866"))
	_add_rect(parent, Vector2(420, 285), Vector2(240, 90), Color(1.0, 1.0, 1.0, 0.32))
	_add_rect(parent, Vector2(595, 285), Vector2(160, 70), Color(1.0, 1.0, 1.0, 0.28))
	_add_rect(parent, Vector2(1680, 245), Vector2(220, 82), Color(1.0, 1.0, 1.0, 0.30))
	_add_rect(parent, Vector2(1845, 245), Vector2(145, 64), Color(1.0, 1.0, 1.0, 0.24))
	_add_rect(parent, Vector2(2310, 300), Vector2(190, 74), Color(1.0, 1.0, 1.0, 0.28))


func _add_player() -> void:
	player = CharacterBody2D.new()
	player.name = "Player"
	_mark_generated(player)
	player.set_script(PLAYER_SCENE)
	player.global_position = PLAYER_START

	var body := ColorRect.new()
	body.name = "Body"
	body.color = Color.html("#ffcf4a")
	body.size = Vector2(42, 58)
	body.position = Vector2(-21, -58)
	body.pivot_offset = Vector2(21, 58)
	player.add_child(body)

	var face := ColorRect.new()
	face.name = "Face"
	face.color = Color.html("#2a2a38")
	face.size = Vector2(18, 8)
	face.position = Vector2(2, -42)
	player.add_child(face)

	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(42, 58)
	collision.shape = shape
	collision.position = Vector2(0, -29)
	player.add_child(collision)

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = Vector2(120, -170)
	camera.zoom = Vector2(0.9, 0.9)
	camera.limit_left = int(WORLD_LIMIT_LEFT)
	camera.limit_right = int(WORLD_LIMIT_RIGHT)
	camera.limit_top = -250
	camera.limit_bottom = 760
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.enabled = true
	player.add_child(camera)

	add_child(player)
	if not Engine.is_editor_hint():
		player.connect("died", Callable(self, "_on_player_died"))


func _add_platform(parent: Node2D, center: Vector2, size: Vector2, color: Color) -> void:
	var body := StaticBody2D.new()
	body.name = "Platform"
	body.position = center
	parent.add_child(body)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	_add_rect(body, Vector2.ZERO, size, color)
	_add_rect(body, Vector2(0, -size.y * 0.5 + 5), Vector2(size.x, 10), Color.html("#6ec17a"))


func _add_coin(position: Vector2) -> void:
	coins_total += 1

	var coin := Area2D.new()
	coin.name = "Coin"
	_mark_generated(coin)
	coin.position = position
	add_child(coin)

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 18
	collision.shape = shape
	coin.add_child(collision)

	var visual := ColorRect.new()
	visual.name = "Visual"
	visual.color = Color.html("#ffd34d")
	visual.size = Vector2(28, 28)
	visual.position = Vector2(-14, -14)
	coin.add_child(visual)

	if not Engine.is_editor_hint():
		coin.body_entered.connect(func(body: Node) -> void:
			if body == player:
				coin.queue_free()
				coins_collected += 1
				_update_coin_label()
		)


func _add_hazard(position: Vector2, size: Vector2) -> void:
	var hazard := Area2D.new()
	hazard.name = "Hazard"
	_mark_generated(hazard)
	hazard.position = position
	add_child(hazard)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	hazard.add_child(collision)

	_add_rect(hazard, Vector2.ZERO, size, Color.html("#db3f3f"))
	_add_rect(hazard, Vector2(0, -size.y * 0.25), Vector2(size.x * 0.86, size.y * 0.28), Color.html("#ff7a4f"))

	if not Engine.is_editor_hint():
		hazard.body_entered.connect(func(body: Node) -> void:
			if body == player:
				_on_player_died()
		)


func _add_goal(position: Vector2) -> void:
	var goal := Area2D.new()
	goal.name = "Goal"
	_mark_generated(goal)
	goal.position = position
	add_child(goal)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(70, 130)
	collision.shape = shape
	collision.position = Vector2(25, -65)
	goal.add_child(collision)

	_add_rect(goal, Vector2(0, -65), Vector2(10, 140), Color.html("#313848"))
	_add_rect(goal, Vector2(45, -108), Vector2(80, 46), Color.html("#f05a5a"))

	if not Engine.is_editor_hint():
		goal.body_entered.connect(func(body: Node) -> void:
			if body == player and coins_collected == coins_total:
				_win()
			elif body == player:
				_flash_status("코인을 모두 모아야 해요")
		)


func _add_rect(parent: Node, center: Vector2, size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = size
	rect.position = center - size * 0.5
	parent.add_child(rect)
	return rect


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	_mark_generated(canvas)
	add_child(canvas)

	coin_label = Label.new()
	coin_label.position = Vector2(24, 18)
	coin_label.add_theme_font_size_override("font_size", 26)
	canvas.add_child(coin_label)

	hint_label = Label.new()
	hint_label.text = "A/D 또는 방향키 이동  |  Space 점프  |  R 재시작"
	hint_label.position = Vector2(24, 54)
	hint_label.add_theme_font_size_override("font_size", 18)
	canvas.add_child(hint_label)

	status_label = Label.new()
	status_label.position = Vector2(24, 86)
	status_label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(status_label)

	win_label = Label.new()
	win_label.text = ""
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	win_label.position = Vector2(220, 210)
	win_label.size = Vector2(720, 120)
	win_label.add_theme_font_size_override("font_size", 42)
	canvas.add_child(win_label)


func _update_coin_label() -> void:
	if coin_label != null:
		coin_label.text = "Coins: %d / %d" % [coins_collected, coins_total]


func _flash_status(text: String) -> void:
	status_label.text = text
	var tween := create_tween()
	tween.tween_property(status_label, "modulate:a", 1.0, 0.05)
	tween.tween_interval(1.0)
	tween.tween_property(status_label, "modulate:a", 0.0, 0.35)


func _on_player_died() -> void:
	_flash_status("다시 도전!")
	player.call("reset_to_spawn")


func _win() -> void:
	win_label.text = "클리어!"
	player.set_physics_process(false)


func _reset_level() -> void:
	get_tree().reload_current_scene()


func _mark_generated(node: Node) -> void:
	node.set_meta("generated_level", true)
