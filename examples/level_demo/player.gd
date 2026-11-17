## Einfache Spielerbewegung (WASD/Pfeiltasten). Das ist normaler Spielcode, keine Story-Logik.
extends CharacterBody2D

@export var speed := 320.0


func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	dir += Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	velocity = dir.limit_length(1.0) * speed
	move_and_slide()
