## Headless-Tests für den Laufzeit-Interpreter.
## Ausführen: godot --headless --path . --script res://tests/run_tests.gd
extends SceneTree

var failures := 0


func _initialize() -> void:
	print("Starte Tests …")
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg)


func _make_runner(path: String, choice: int) -> StoryGraphRunner:
	var r := StoryGraphRunner.new()
	root.add_child(r)
	r.load_graph(path)
	r.dialogue_requested.connect(func(_s, _t, _id): r.advance.call_deferred())
	r.choice_requested.connect(func(_p, _o, _l, _id):
		if choice >= 0:
			r.choose(choice))  # absichtlich synchron
	r.error_occurred.connect(func(m, id): printerr("    runner error: ", m, " ", id))
	return r


func _run() -> void:
	print("Verhör-Demo, Option 0 (Verständnis):")
	var r := _make_runner("res://examples/verhoer.storygraph", 0)
	r.start()
	var ending: String = await r.finished
	_check(ending == "gestaendnis", "Ende = gestaendnis (war '%s')" % ending)
	_check(r.get_var("vertrauen") == 2, "vertrauen = 2")
	_check(r.tasks["gestaendnis"]["status"] == "done", "Task abgeschlossen")
	r.queue_free()

	print("Verhör-Demo, Option 1 (Drohen):")
	r = _make_runner("res://examples/verhoer.storygraph", 1)
	r.start()
	ending = await r.finished
	_check(ending == "schweigen", "Ende = schweigen")
	_check(r.get_var("vertrauen") == -1, "vertrauen = -1")
	r.queue_free()

	print("Verhör-Demo, Zeitlimit läuft ab:")
	r = _make_runner("res://examples/verhoer.storygraph", -1)
	var timed_out := [false]
	r.choice_timed_out.connect(func(_id): timed_out[0] = true)
	r.start()
	ending = await r.finished
	_check(timed_out[0], "choice_timed_out gesendet")
	_check(ending == "schweigen", "Ende = schweigen nach Zeitablauf und Sprung")
	r.queue_free()

	print("Logik, Switch, Sequenz, Tasks, Ausdrücke:")
	var g := StoryGraphData.from_dict({
		"format": "story_graph", "version": 1,
		"variables": {"x": {"type": "int", "default": 3}, "s": {"type": "string", "default": "b"}, "log": {"type": "string", "default": ""}},
		"nodes": [
			{"id": "st", "type": "start", "data": {}},
			{"id": "seq", "type": "sequence", "data": {"steps": 2}},
			{"id": "a1", "type": "set_var", "data": {"variable": "log", "op": "+=", "value": "\"A\""}},
			{"id": "b1", "type": "set_var", "data": {"variable": "log", "op": "+=", "value": "\"B\""}},
			{"id": "any", "type": "all_any", "data": {"mode": "any", "conditions": ["x > 10", "not (x == 1)"]}},
			{"id": "sw", "type": "switch", "data": {"variable": "s", "cases": ["a", "b"]}},
			{"id": "ts", "type": "task_start", "data": {"task_id": "t1", "description": "Test"}},
			{"id": "tw", "type": "task_wait", "data": {"task_ids": ["t1"], "mode": "all"}},
			{"id": "ex", "type": "expression", "data": {"code": "runner.set_var(\"x\", x * 10)"}},
			{"id": "sig", "type": "emit_signal", "data": {"signal_name": "kamera", "payload": "{\"nr\": x}"}},
			{"id": "w", "type": "wait", "data": {"seconds": 0.1}},
			{"id": "e_ok", "type": "end", "data": {"ending_id": "ok"}},
			{"id": "e_bad", "type": "end", "data": {"ending_id": "bad"}},
		],
		"connections": [
			{"from": "st", "from_port": 0, "to": "seq"},
			{"from": "seq", "from_port": 0, "to": "a1"},
			{"from": "seq", "from_port": 1, "to": "b1"},
			{"from": "b1", "from_port": 0, "to": "any"},
			{"from": "any", "from_port": 0, "to": "sw"},
			{"from": "any", "from_port": 1, "to": "e_bad"},
			{"from": "sw", "from_port": 1, "to": "ts"},
			{"from": "sw", "from_port": 0, "to": "e_bad"},
			{"from": "sw", "from_port": 2, "to": "e_bad"},
			{"from": "ts", "from_port": 0, "to": "tw"},
			{"from": "tw", "from_port": 0, "to": "ex"},
			{"from": "ex", "from_port": 0, "to": "sig"},
			{"from": "sig", "from_port": 0, "to": "w"},
			{"from": "w", "from_port": 0, "to": "e_ok"},
		],
	})
	r = StoryGraphRunner.new()
	root.add_child(r)
	r.set_graph(g)
	r.error_occurred.connect(func(m, id): printerr("    runner error: ", m, " ", id))
	var payload := [null]
	r.custom_signal.connect(func(n, p): payload[0] = [n, p])
	r.task_started.connect(func(id, _d): r.complete_task.call_deferred(id, true))
	r.start()
	ending = await r.finished
	_check(ending == "ok", "Ende = ok (war '%s')" % ending)
	_check(r.get_var("log") == "AB", "Sequenz-Reihenfolge AB (war '%s')" % r.get_var("log"))
	_check(r.get_var("x") == 30, "Ausdruck mit runner.set_var (x = %s)" % str(r.get_var("x")))
	_check(payload[0] != null and payload[0][0] == "kamera" and payload[0][1]["nr"] == 30, "custom_signal mit Daten")

	print("Validator:")
	var issues := StoryGraphValidator.validate(StoryGraphData.load_file("res://examples/verhoer.storygraph"))
	var errors := issues.filter(func(i): return i["severity"] == "error")
	_check(errors.is_empty(), "Demo-Graph ohne Fehler (%s)" % str(errors))
	var bad := StoryGraphData.from_dict({"nodes": [{"id": "j", "type": "jump", "data": {"label_target": "nix"}},
		{"id": "b", "type": "branch", "data": {"condition": "unbekannt >"}}]})
	var msgs := StoryGraphValidator.validate(bad).map(func(i): return i["message"])
	_check(msgs.any(func(m): return "keinen Start" in m), "fehlender Start erkannt")
	_check(msgs.any(func(m): return "Sprungziel" in m), "falsches Sprungziel erkannt")
	_check(msgs.any(func(m): return "ungültig" in m), "kaputter Ausdruck erkannt")

	print("")
	print("FEHLGESCHLAGEN: %d" % failures if failures > 0 else "Alle Tests bestanden.")
	quit(1 if failures > 0 else 0)
