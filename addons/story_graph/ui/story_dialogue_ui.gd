## Fertige Dialog-, Entscheidungs- und Aufgaben-Anzeige für den StoryGraphRunner.
##
## Einfach als Node in die Szene hängen. Ohne Einstellung verbindet sie sich mit dem ersten
## StoryGraphRunner der Szene. Aussehen über die Exporte oder ein eigenes Theme anpassen.
## Steuerung: Klick/Enter/Leertaste = weiter (erst Text komplett zeigen), 1–9 = Option wählen.
@icon("res://addons/story_graph/ui/ui_icon.svg")
class_name StoryDialogueUI
extends CanvasLayer

## Leer lassen = automatisch den ersten StoryGraphRunner der Szene verwenden.
@export var runner: StoryGraphRunner
## Zeichen pro Sekunde für den Schreibmaschinen-Effekt (0 = sofort).
@export var characters_per_second := 45.0
@export var show_tasks := true
@export var panel_color := Color(0.05, 0.06, 0.08, 0.86)
@export var speaker_color := Color("#e0a33a")
@export var accent_color := Color("#5b8def")
@export var font_size := 22
## Sprecherfarben, z. B. {"Kara": Color.CYAN}.
@export var speaker_colors: Dictionary = {}

var _panel: PanelContainer
var _speaker: Label
var _text: RichTextLabel
var _hint: Label
var _choices: VBoxContainer
var _timer_bar: ProgressBar
var _tasks: VBoxContainer
var _time_left := 0.0
var _time_total := 0.0
var _typing := false


func _ready() -> void:
	layer = 50
	_build()
	if runner == null:
		_find_runner.call_deferred()
	else:
		_connect_runner()


func _find_runner() -> void:
	for n in get_tree().get_nodes_in_group(StoryTrigger.RUNNER_GROUP):
		if n is StoryGraphRunner:
			runner = n
			break
	if runner == null:
		push_warning("StoryDialogueUI: kein StoryGraphRunner in der Szene gefunden.")
		return
	_connect_runner()


func _connect_runner() -> void:
	runner.dialogue_requested.connect(_on_dialogue)
	runner.choice_requested.connect(_on_choice)
	runner.choice_timed_out.connect(func(_id): _close_choices())
	runner.task_started.connect(func(_id, _d): _refresh_tasks())
	runner.task_finished.connect(func(_id, _ok): _refresh_tasks())
	runner.finished.connect(func(_e): _panel.visible = false)


func _process(delta: float) -> void:
	if _typing and characters_per_second > 0.0:
		_text.visible_characters += maxi(1, int(characters_per_second * delta + 0.5))
		if _text.visible_characters >= _text.get_total_character_count():
			_finish_typing()
	if _timer_bar.visible and _time_total > 0.0:
		_time_left = maxf(0.0, _time_left - delta)
		_timer_bar.value = _time_left / _time_total * 100.0


func _unhandled_input(event: InputEvent) -> void:
	if runner == null or not _panel.visible:
		return
	var confirm: bool = event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if confirm and runner.is_waiting_for_advance():
		if _typing:
			_finish_typing()
		else:
			_hint.visible = false
			runner.advance()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and runner.is_waiting_for_choice():
		var idx: int = event.keycode - KEY_1
		if idx >= 0 and idx < _choices.get_child_count():
			_pick(idx)
			get_viewport().set_input_as_handled()


func _on_dialogue(speaker: String, text: String, _id: String) -> void:
	_panel.visible = true
	_close_choices()
	_speaker.text = speaker
	_speaker.visible = speaker != ""
	_speaker.add_theme_color_override("font_color", speaker_colors.get(speaker, speaker_color))
	_text.text = text
	_hint.visible = false
	if characters_per_second > 0.0:
		_text.visible_characters = 0
		_typing = true
	else:
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1
	_hint.visible = runner != null and runner.is_waiting_for_advance()


func _on_choice(prompt: String, options: Array, time_limit: float, _id: String) -> void:
	_panel.visible = true
	_hint.visible = false
	_typing = false
	if prompt != "":
		_speaker.visible = false
		_text.text = prompt
		_text.visible_characters = -1
	_close_choices()
	for i in options.size():
		var b := Button.new()
		b.text = "%d   %s" % [i + 1, options[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", font_size - 2)
		b.pressed.connect(_pick.bind(i))
		_choices.add_child(b)
	if time_limit > 0.0:
		_time_total = time_limit
		_time_left = time_limit
		_timer_bar.visible = true
	if _choices.get_child_count() > 0:
		(_choices.get_child(0) as Button).grab_focus.call_deferred()


func _pick(index: int) -> void:
	_close_choices()
	runner.choose(index)


func _close_choices() -> void:
	_timer_bar.visible = false
	for c in _choices.get_children():
		c.queue_free()


func _refresh_tasks() -> void:
	for c in _tasks.get_children():
		c.queue_free()
	if not show_tasks:
		return
	for tid in runner.tasks:
		var t: Dictionary = runner.tasks[tid]
		var l := Label.new()
		var mark: String = {"active": "◻", "done": "✔", "failed": "✘"}.get(t["status"], "")
		l.text = "%s  %s" % [mark, t["description"] if t["description"] != "" else tid]
		l.add_theme_font_size_override("font_size", font_size - 4)
		if t["status"] != "active":
			l.modulate = Color(1, 1, 1, 0.45)
		_tasks.add_child(l)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_tasks = VBoxContainer.new()
	_tasks.position = Vector2(28, 24)
	_tasks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tasks)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 60
	_panel.offset_right = -60
	_panel.offset_bottom = -30
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = panel_color
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	style.border_color = Color(accent_color, 0.5)
	style.border_width_top = 2
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", font_size - 2)
	box.add_child(_speaker)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(0, font_size * 2)
	_text.add_theme_font_size_override("normal_font_size", font_size)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0, 6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ef6a5a")
	_timer_bar.add_theme_stylebox_override("fill", fill)
	_timer_bar.visible = false
	box.add_child(_timer_bar)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	box.add_child(_choices)
	_hint = Label.new()
	_hint.text = "▼"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate = Color(1, 1, 1, 0.5)
	_hint.visible = false
	box.add_child(_hint)
