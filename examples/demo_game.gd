## Minimales Beispielspiel: zeigt, wie ein Spiel den StoryGraphRunner einbindet.
## Szene starten (F6 im Godot-Editor) und durchklicken.
extends Control

@onready var runner: StoryGraphRunner = $StoryGraphRunner
@onready var speaker: Label = %Speaker
@onready var text: Label = %Text
@onready var choices: VBoxContainer = %Choices
@onready var timer_bar: ProgressBar = %TimerBar
@onready var tasks_label: Label = %Tasks
@onready var continue_hint: Label = %ContinueHint

var _time_left := 0.0
var _time_total := 0.0


func _ready() -> void:
	runner.dialogue_requested.connect(_on_dialogue)
	runner.choice_requested.connect(_on_choice)
	runner.choice_timed_out.connect(func(_id): _clear_choices())
	runner.task_started.connect(func(_id, _d): _update_tasks())
	runner.task_finished.connect(func(_id, _ok): _update_tasks())
	runner.finished.connect(_on_finished)
	runner.custom_signal.connect(func(n, p): print("Signal aus der Story: ", n, " ", p))
	timer_bar.visible = false
	continue_hint.visible = false
	runner.start()


func _process(delta: float) -> void:
	if timer_bar.visible:
		_time_left = maxf(0.0, _time_left - delta)
		timer_bar.value = _time_left / _time_total * 100.0


func _unhandled_input(event: InputEvent) -> void:
	if runner.is_waiting_for_advance() and (event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed)):
		continue_hint.visible = false
		runner.advance()


func _on_dialogue(who: String, line: String, _id: String) -> void:
	speaker.text = who
	text.text = line
	continue_hint.visible = true


func _on_choice(prompt: String, options: Array, time_limit: float, _id: String) -> void:
	if prompt != "":
		speaker.text = ""
		text.text = prompt
	_clear_choices()
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.pressed.connect(func():
			_clear_choices()
			runner.choose(i))
		choices.add_child(b)
	if time_limit > 0.0:
		_time_total = time_limit
		_time_left = time_limit
		timer_bar.visible = true
	choices.get_child(0).grab_focus()


func _clear_choices() -> void:
	timer_bar.visible = false
	for c in choices.get_children():
		c.queue_free()


func _update_tasks() -> void:
	var lines := []
	for id in runner.tasks:
		var t: Dictionary = runner.tasks[id]
		lines.append(("☐ " if t["status"] == "active" else "☑ ") + t["description"])
	tasks_label.text = "\n".join(lines)


func _on_finished(ending: String) -> void:
	speaker.text = "ENDE"
	text.text = "Erreichtes Ende: %s\nVertrauen: %s" % [ending, runner.get_var("vertrauen")]
	continue_hint.visible = false
