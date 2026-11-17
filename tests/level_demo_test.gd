## Spielt das Demo-Level automatisch durch: Spieler wird in die Zonen gesetzt,
## Dialoge werden bestätigt, Entscheidungen getroffen. Prüft Szenen-Nodes, StoryTrigger und StoryDialogueUI.
## godot --path . --script res://tests/level_demo_test.gd -- [screenshot-ordner]
extends SceneTree

var failures := 0
var out_dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _shot(name: String) -> void:
	if out_dir == "" or DisplayServer.get_name() == "headless":
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name))


func _advance_until_not_dialogue(runner: StoryGraphRunner) -> void:
	for i in 10:
		await _frames(4)
		if runner.is_waiting_for_advance():
			runner.advance()
		else:
			return


func _play(choice: int, take_shots: bool) -> Dictionary:
	var level: Node = load("res://examples/level_demo/level.tscn").instantiate()
	root.add_child(level)
	var runner: StoryGraphRunner = level.get_node("StoryGraphRunner")
	var player: Node2D = level.get_node("Spieler")
	var result := {"ending": "", "level": level}
	runner.finished.connect(func(e): result["ending"] = e)
	await _frames(10)
	if take_shots:
		await _shot("level_01_start.png")
	await _advance_until_not_dialogue(runner)
	_check(runner.is_task_active("schluessel"), "Task 'Finde den Schlüssel' aktiv")

	player.global_position = level.get_node("Schluessel").global_position
	await _frames(6)
	_check(not level.get_node("Schluessel").visible, "Schlüssel ausgeblendet nach Ereignis")
	_check(runner.get_var("hat_schluessel") == true, "Variable hat_schluessel gesetzt")

	player.global_position = level.get_node("TuerZone").global_position
	await _frames(6)
	_check(level.get_node("KameraTuer").is_current(), "Kamera auf die Tür gewechselt")
	await _advance_until_not_dialogue(runner)
	_check(runner.is_waiting_for_choice(), "Entscheidung angezeigt")
	if take_shots:
		await _shot("level_02_entscheidung.png")
	runner.choose(choice)
	await _frames(int(2.0 * 60))
	_check(level.get_node("Tuer").global_position.distance_to(level.get_node("TuerOffen").global_position) < 1.0, "Tür ist aufgeschoben")
	_check(level.get_node("KameraRaum").is_current(), "Kamera zurück im Raum")
	if choice == 1:
		_check((level.get_node("Lampe") as Polygon2D).color.g < 0.3, "Lampe leuchtet rot (Eigenschaft mit Überblendung)")
	if take_shots:
		await _shot("level_03_tuer_offen.png")

	player.global_position = level.get_node("Ausgang").global_position
	await _frames(6)
	await _advance_until_not_dialogue(runner)
	await _frames(4)
	level.queue_free()
	await _frames(2)
	return result


func _run() -> void:
	root.size = Vector2i(1600, 900)
	print("Demo-Level, leise öffnen:")
	var r := await _play(0, true)
	_check(r["ending"] == "entkommen", "Ende = entkommen (war '%s')" % r["ending"])
	print("Demo-Level, Tür auframmen:")
	r = await _play(1, false)
	_check(r["ending"] == "entdeckt", "Ende = entdeckt (war '%s')" % r["ending"])
	print("FEHLGESCHLAGEN: %d" % failures if failures > 0 else "Demo-Level-Test bestanden.")
	quit(1 if failures > 0 else 0)
