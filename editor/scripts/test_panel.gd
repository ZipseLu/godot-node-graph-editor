## Tab "Testlauf": spielt den Graph direkt im Editor durch, so wie er später im Spiel läuft.
## Der aktive Node wird im Graph hervorgehoben.
class_name TestPanel
extends VBoxContainer

signal node_entered(node_id: String)
signal run_finished()

## Liefert StoryGraphData des aktuellen Editor-Zustands.
var graph_provider: Callable
## Liefert die ID des ausgewählten Nodes (für "Ab Auswahl starten").
var selection_provider: Callable
var base_path := ""

var runner: StoryGraphRunner
var _log: RichTextLabel
var _choices: VBoxContainer
var _continue: Button
var _timer_bar: ProgressBar
var _timer_label: Label
var _vars_box: VBoxContainer
var _tasks_box: VBoxContainer
var _start_btn: Button
var _stop_btn: Button
var _follow: CheckBox
var _timer_total := 0.0
var _timer_left := 0.0


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var bar := HBoxContainer.new()
	_start_btn = Button.new()
	_start_btn.text = "▶ Von Start"
	_start_btn.tooltip_text = "Testlauf ab dem Start-Node (F5)"
	_start_btn.pressed.connect(func(): start_run(""))
	bar.add_child(_start_btn)
	var from_sel := Button.new()
	from_sel.text = "▶ Ab Auswahl"
	from_sel.tooltip_text = "Testlauf ab dem ausgewählten Node (Shift+F5)"
	from_sel.pressed.connect(func(): start_run(selection_provider.call()))
	bar.add_child(from_sel)
	_stop_btn = Button.new()
	_stop_btn.text = "■ Stopp"
	_stop_btn.disabled = true
	_stop_btn.pressed.connect(stop_run)
	bar.add_child(_stop_btn)
	box.add_child(bar)
	_follow = CheckBox.new()
	_follow.text = "Ansicht folgt dem aktiven Node"
	_follow.button_pressed = true
	box.add_child(_follow)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 180)
	_log.selection_enabled = true
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color("#16191e")
	log_style.set_corner_radius_all(6)
	log_style.set_content_margin_all(10)
	_log.add_theme_stylebox_override("normal", log_style)
	box.add_child(_log)

	_timer_label = Label.new()
	_timer_label.visible = false
	box.add_child(_timer_label)
	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0, 8)
	_timer_bar.visible = false
	box.add_child(_timer_bar)

	_choices = VBoxContainer.new()
	box.add_child(_choices)
	_continue = Button.new()
	_continue.text = "Weiter  ⏎"
	_continue.visible = false
	_continue.pressed.connect(func(): runner.advance())
	box.add_child(_continue)

	box.add_child(_section("Tasks"))
	_tasks_box = VBoxContainer.new()
	box.add_child(_tasks_box)
	box.add_child(_section("Variablen (live änderbar)"))
	_vars_box = VBoxContainer.new()
	box.add_child(_vars_box)

	runner = StoryGraphRunner.new()
	runner.name = "TestRunner"
	add_child(runner)
	runner.context = self
	runner.dialogue_requested.connect(_on_dialogue)
	runner.choice_requested.connect(_on_choice)
	runner.choice_timed_out.connect(func(_id):
		_clear_choices()
		_hide_timer()
		_write("[color=#ef8a7a]⏱ Zeit abgelaufen[/color]"))
	runner.variable_changed.connect(func(n, v, old):
		_write("[color=#6fd39a]%s[/color]: %s → %s" % [n, _fmt(old), _fmt(v)])
		_refresh_vars())
	runner.task_started.connect(func(id, d):
		_write("[color=#e0d060]☐ Task gestartet:[/color] %s" % (d if d != "" else id))
		_refresh_tasks())
	runner.task_finished.connect(func(id, ok):
		_write("[color=#e0d060]%s Task %s:[/color] %s" % ["☑" if ok else "☒", "erledigt" if ok else "gescheitert", id])
		_refresh_tasks())
	runner.countdown_started.connect(func(s, _id): _show_timer(s, "Countdown"))
	runner.countdown_finished.connect(func(ok, _id):
		_hide_timer()
		_write("[color=#ef8a7a]Countdown:[/color] %s" % ("geschafft" if ok else "abgelaufen")))
	runner.custom_signal.connect(func(n, p): _write("[color=#8aa4c8]📡 Signal[/color] %s %s" % [n, _fmt(p) if p != null else ""]))
	runner.node_entered.connect(func(id, _t):
		if _follow.button_pressed:
			node_entered.emit(id))
	runner.simulate_missing_methods = true
	runner.method_simulated.connect(func(path, method, args):
		_write("[color=#8aa4c8]⚙ Methode[/color] %s.%s(%s) [color=#ffffff66](im Spiel ausgeführt)[/color]" % [path, method, ", ".join(args.map(_fmt))]))
	runner.error_occurred.connect(func(m, id): _write("[color=#ff6b6b]Fehler[/color] (%s): %s" % [id, m]))
	runner.finished.connect(func(ending):
		_write("\n[b]■ Ende erreicht[/b]%s" % (": " + ending if ending != "" else ""))
		_finish())
	_write("[color=#ffffff88]Drück [b]F5[/b] oder ▶, um deine Geschichte hier durchzuspielen. Der aktive Node leuchtet im Graph gelb.[/color]")


func _process(delta: float) -> void:
	if _timer_bar.visible and _timer_total > 0.0:
		_timer_left = maxf(0.0, _timer_left - delta)
		_timer_bar.value = _timer_left / _timer_total * 100.0
		_timer_label.text = "⏱ %.1f s" % _timer_left


func start_run(from_id: String) -> void:
	var g: StoryGraphData = graph_provider.call()
	if g == null:
		return
	stop_run()
	_log.clear()
	runner.graph_path = base_path
	runner.tasks.clear()
	runner.history.clear()
	runner.visit_counts.clear()
	runner.set_graph(g)
	_start_btn.disabled = true
	_stop_btn.disabled = false
	_refresh_vars()
	_refresh_tasks()
	_write("[b]▶ Testlauf gestartet[/b]")
	runner.start(from_id)


func stop_run() -> void:
	if runner.running:
		runner.stop()
		_write("[color=#ffffff88]■ abgebrochen[/color]")
	_finish()


func is_running() -> bool:
	return runner.running


func _finish() -> void:
	_clear_choices()
	_hide_timer()
	_continue.visible = false
	_start_btn.disabled = false
	_stop_btn.disabled = true
	run_finished.emit()


func _unhandled_key_input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not runner.running:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode in [KEY_ENTER, KEY_KP_ENTER] and _continue.visible:
			runner.advance()
			get_viewport().set_input_as_handled()
		elif e.keycode >= KEY_1 and e.keycode <= KEY_9 and runner.is_waiting_for_choice():
			var idx: int = e.keycode - KEY_1
			if idx < _choices.get_child_count():
				runner.choose(idx)
				get_viewport().set_input_as_handled()


func _on_dialogue(speaker: String, text: String, _id: String) -> void:
	if speaker != "":
		_write("[b][color=#e0a33a]%s[/color][/b]: %s" % [speaker, text])
	else:
		_write(text)
	_continue.visible = true
	_continue.grab_focus.call_deferred()
	await runner._advanced
	_continue.visible = false


func _on_choice(prompt: String, options: Array, limit: float, _id: String) -> void:
	_clear_choices()
	if prompt != "":
		_write("[i]%s[/i]" % prompt)
	for i in options.size():
		var b := Button.new()
		b.text = "%d   %s" % [i + 1, options[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func():
			_write("[color=#7fb0ff]→ %s[/color]" % options[i])
			_clear_choices()
			_hide_timer()
			runner.choose(i))
		_choices.add_child(b)
	if limit > 0.0:
		_show_timer(limit, "Entscheidung")


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()


func _show_timer(seconds: float, label: String) -> void:
	_timer_total = seconds
	_timer_left = seconds
	_timer_bar.visible = true
	_timer_label.visible = true
	_timer_label.text = "%s: %.1f s" % [label, seconds]


func _hide_timer() -> void:
	_timer_bar.visible = false
	_timer_label.visible = false


func _refresh_vars() -> void:
	for c in _vars_box.get_children():
		c.queue_free()
	for name in runner.variables:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = name
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var value = runner.variables[name]
		if typeof(value) == TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = value
			cb.toggled.connect(func(on): runner.set_var(name, on))
			row.add_child(cb)
		else:
			var le := LineEdit.new()
			le.text = str(value)
			le.custom_minimum_size = Vector2(110, 0)
			le.text_submitted.connect(func(t): runner.set_var(name, t))
			row.add_child(le)
		_vars_box.add_child(row)


func _refresh_tasks() -> void:
	for c in _tasks_box.get_children():
		c.queue_free()
	if runner.tasks.is_empty():
		var l := Label.new()
		l.text = "–"
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
		_tasks_box.add_child(l)
	for id in runner.tasks:
		var t: Dictionary = runner.tasks[id]
		var row := HBoxContainer.new()
		var l := Label.new()
		var mark: String = {"active": "☐", "done": "☑", "failed": "☒"}.get(t["status"], "?")
		l.text = "%s %s" % [mark, t["description"] if t["description"] != "" else id]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if t["status"] == "active":
			var ok := Button.new()
			ok.text = "erledigen"
			ok.tooltip_text = "Simuliert, dass das Spiel complete_task(\"%s\") aufruft" % id
			ok.pressed.connect(func(): runner.complete_task(id, true))
			row.add_child(ok)
			var fail := Button.new()
			fail.text = "scheitern"
			fail.pressed.connect(func(): runner.complete_task(id, false))
			row.add_child(fail)
		_tasks_box.add_child(row)


func _write(text: String) -> void:
	_log.append_text(text + "\n")


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	return l


func _fmt(v: Variant) -> String:
	if typeof(v) == TYPE_STRING:
		return "\"%s\"" % v
	return str(v)
