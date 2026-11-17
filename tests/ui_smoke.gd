## UI-Rauchtest: startet den Editor, führt typische Aktionen aus und speichert Screenshots.
## Ausführen (mit Bildschirm): godot --path . --script res://tests/ui_smoke.gd -- <ausgabeordner>
extends SceneTree

var failures := 0
var out_dir := "user://"


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
		await process_frame


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name))


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var main: Control = load("res://editor/scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(5)
	main._open_file("res://examples/verhoer.storygraph")
	await _frames(5)
	main.frame_all()
	var canvas: GraphCanvas = main.canvas
	_check(canvas.story_nodes().size() == 17, "Beispiel geladen (17 Nodes, %d)" % canvas.story_nodes().size())
	_check(canvas.get_connection_list().size() == 18, "18 Verbindungen (%d)" % canvas.get_connection_list().size())
	_check(canvas.frames().size() == 1, "Kommentar-Rahmen geladen")
	await _shot("01_uebersicht.png")

	# Auswahl -> Inspector
	var choice := canvas.get_story_node("choice")
	canvas.set_selected(choice)
	await _frames(3)
	await _shot("02_inspector_entscheidung.png")
	canvas.zoom = 0.8
	canvas.scroll_offset = (choice.position_offset + Vector2(380, 160)) * 0.8 - canvas.size * 0.5
	await _shot("00_detail.png")

	# Feld ändern -> Ausgänge passen sich an
	var n_old: int = choice.data["options"].size()
	var opts: Array = choice.data["options"].duplicate()
	opts.append("Lügen")
	main.inspector._set_list_with_port_map("options", opts, func(p: int) -> int: return p if p < n_old else p + 1)
	_check(choice.output_count() == 5, "Neue Option erzeugt zusätzlichen Ausgang")
	var timeout_ok := canvas.get_connection_list().any(func(c): return str(c["from_node"]) == "choice" and c["from_port"] == 4 and str(c["to_node"]) == "timeout")
	_check(timeout_ok, "Zeitablauf-Verbindung wandert mit auf den neuen Port")

	# Hinzufügen + Rückgängig
	var before := canvas.story_nodes().size()
	canvas.add_story_node("wait", Vector2(0, 600), "fail", 0)
	await _frames(2)
	_check(canvas.story_nodes().size() == before + 1, "Node hinzugefügt")
	main.undo()
	await _frames(2)
	_check(canvas.story_nodes().size() == before, "Rückgängig entfernt Node wieder")
	main.redo()
	await _frames(2)
	_check(canvas.story_nodes().size() == before + 1, "Wiederholen stellt Node wieder her")
	main.undo()
	await _frames(2)

	# Kopieren/Einfügen
	canvas.set_selected(canvas.get_story_node("intro"))
	await _frames(1)
	canvas.duplicate_selection()
	await _frames(2)
	_check(canvas.story_nodes().size() == before + 1, "Duplizieren")
	main.undo()
	await _frames(2)

	# Hinzufügen-Menü
	main._open_add_menu(Vector2(600, 300), Vector2(0, 0), "", -1)
	main.add_palette.search.text = "timer"
	main.add_palette.search.text_changed.emit("timer")
	await _frames(2)
	await _shot("03_hinzufuegen_menue.png")
	main.add_popup.hide()

	# Variablen-Tab
	main.right_tabs.current_tab = main.variables_panel.get_index()
	await _shot("04_variablen.png")

	# Testlauf
	main._start_test("")
	var runner: StoryGraphRunner = main.test_panel.runner
	await _frames(5)
	runner.advance()
	await _frames(5)
	runner.advance()
	await _frames(10)
	_check(runner.is_waiting_for_choice(), "Testlauf wartet auf Entscheidung")
	await _shot("05_testlauf.png")
	runner.choose(0)
	await _frames(5)
	runner.advance()
	await _frames(5)
	_check(not runner.running, "Testlauf beendet")
	_check(runner.get_var("vertrauen") == 2, "Testlauf setzt Variable")

	# Validator markiert Fehler
	main._validate()
	_check(main._issues.size() > 0, "Probleme nach Änderung erkannt (neue Option unverbunden)")

	# Speichern + Laden
	var path := OS.get_temp_dir().path_join("roundtrip.storygraph")
	main._save_to(path)
	var g := StoryGraphData.load_file(path)
	_check(g != null and g.nodes.size() == canvas.story_nodes().size(), "Speichern und Laden")
	_check(g.comments.size() == 1 and g.comments[0]["nodes"].size() > 0, "Rahmen-Zuordnung gespeichert")

	# Spielprojekt-Erkennung: Story-IDs und Ereignisse aus den Szenen
	main.dirty = false
	main._open_file("res://examples/level_demo/flucht.storygraph")
	await _frames(5)
	_check(main.scanner.root != "", "Spielprojekt gefunden")
	_check(main.scanner.actors.has("tuer") and main.scanner.actors.has("kamera_tuer"), "Story-IDs aus level.tscn gelesen")
	_check(main.scanner.events.has("tuer_erreicht"), "Ereignisse aus level.tscn gelesen")
	_check(main._issues.filter(func(i): return i["severity"] == "error").is_empty(), "Demo-Level-Graph ohne Fehler")
	main.frame_all()
	var move := canvas.get_story_node("open_fast")
	canvas.set_selected(move)
	canvas.zoom = 0.8
	canvas.scroll_offset = (move.position_offset + Vector2(0, 100)) * 0.8 - canvas.size * 0.5
	await _shot("06_szene_nodes.png")
	main._start_test("")
	await _frames(5)
	main.test_panel.runner.advance()
	await _frames(5)
	_check(main.test_panel._event_edit.text == "schluessel_aufgehoben", "Testlauf schlägt erwartetes Ereignis vor")
	main.test_panel._fire_event("schluessel_aufgehoben")
	await _frames(5)
	_check(main.test_panel.runner.get_var("hat_schluessel") == true, "Ereignis im Testlauf auslösbar, Szenen-Aktion simuliert")
	await _shot("07_testlauf_ereignis.png")
	main.test_panel.stop_run()

	print("FEHLGESCHLAGEN: %d" % failures if failures > 0 else "UI-Rauchtest bestanden.")
	main.dirty = false
	quit(1 if failures > 0 else 0)
