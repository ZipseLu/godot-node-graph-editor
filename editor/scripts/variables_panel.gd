## Tab "Variablen": Story-Werte anlegen, umbenennen, Typ und Startwert festlegen.
class_name VariablesPanel
extends VBoxContainer

signal about_to_change(coalesce_key: String)
signal changed()
## Eine Variable wurde umbenannt; das Hauptfenster passt alle Verweise im Graph an.
signal variable_renamed(old_name: String, new_name: String)

const TYPE_LABELS := {"bool": "wahr/falsch", "int": "Ganzzahl", "float": "Kommazahl", "string": "Text"}

var variables: Dictionary = {}
var _list: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	margin.add_child(inner)

	var hint := Label.new()
	hint.text = "Variablen speichern den Zustand deiner Geschichte, z. B. Vertrauen, Entscheidungen oder Inventar. Du nutzt sie in Bedingungen einfach über ihren Namen."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	hint.add_theme_font_size_override("font_size", 13)
	inner.add_child(hint)

	var add := Button.new()
	add.text = "＋ Neue Variable"
	add.pressed.connect(_add_variable)
	inner.add_child(add)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	rebuild()


func set_variables(v: Dictionary) -> void:
	variables = v.duplicate(true)
	rebuild()


func rebuild() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if variables.is_empty():
		var l := Label.new()
		l.text = "Noch keine Variablen."
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
		_list.add_child(l)
	for name in variables:
		_list.add_child(_make_row(name))


func _make_row(var_name: String) -> Control:
	var v: Dictionary = variables[var_name]
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#2a2f37")
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var top := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.text = var_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.tooltip_text = "Name (Buchstaben, Ziffern, _). Umbenennen passt alle Verweise im Graph an."
	var commit := func():
		var new_name := name_edit.text.strip_edges()
		if new_name == var_name:
			return
		if not StoryGraphData.is_valid_variable_name(new_name) or variables.has(new_name):
			name_edit.text = var_name
			name_edit.modulate = Color("#ff8a80")
			create_tween().tween_property(name_edit, "modulate", Color.WHITE, 0.8)
			return
		about_to_change.emit("")
		var new_vars := {}
		for k in variables:
			new_vars[new_name if k == var_name else k] = variables[k]
		variables = new_vars
		variable_renamed.emit(var_name, new_name)
		changed.emit()
		rebuild.call_deferred()
	name_edit.text_submitted.connect(func(_t): commit.call())
	name_edit.focus_exited.connect(commit)
	top.add_child(name_edit)
	var del := Button.new()
	del.text = "✕"
	del.flat = true
	del.tooltip_text = "Variable löschen"
	del.pressed.connect(func():
		about_to_change.emit("")
		variables.erase(var_name)
		changed.emit()
		rebuild())
	top.add_child(del)
	box.add_child(top)

	var bottom := HBoxContainer.new()
	var type_btn := OptionButton.new()
	var i := 0
	for t in StoryGraphData.VARIABLE_TYPES:
		type_btn.add_item(TYPE_LABELS[t])
		type_btn.set_item_metadata(i, t)
		if t == v["type"]:
			type_btn.select(i)
		i += 1
	type_btn.item_selected.connect(func(idx):
		about_to_change.emit("")
		var t: String = type_btn.get_item_metadata(idx)
		variables[var_name] = {"type": t, "default": StoryGraphData.coerce(t, v["default"])}
		changed.emit()
		rebuild())
	bottom.add_child(type_btn)
	var start_label := Label.new()
	start_label.text = "Start:"
	start_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	bottom.add_child(start_label)
	bottom.add_child(_default_editor(var_name, v))
	box.add_child(bottom)
	return panel


func _default_editor(var_name: String, v: Dictionary) -> Control:
	var set_default := func(value):
		about_to_change.emit("var_default_" + var_name)
		variables[var_name]["default"] = value
		changed.emit()
	match v["type"]:
		"bool":
			var cb := CheckBox.new()
			cb.text = "wahr"
			cb.button_pressed = bool(v["default"])
			cb.toggled.connect(func(on): set_default.call(on))
			return cb
		"int", "float":
			var sb := SpinBox.new()
			sb.allow_greater = true
			sb.allow_lesser = true
			sb.min_value = -100000
			sb.max_value = 100000
			sb.step = 1 if v["type"] == "int" else 0.01
			sb.value = float(v["default"])
			sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sb.value_changed.connect(func(x): set_default.call(int(x) if v["type"] == "int" else x))
			return sb
		_:
			var le := LineEdit.new()
			le.text = str(v["default"])
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(func(t): set_default.call(t))
			return le


func _add_variable() -> void:
	about_to_change.emit("")
	var n := 1
	while variables.has("variable_%d" % n):
		n += 1
	variables["variable_%d" % n] = {"type": "bool", "default": false}
	changed.emit()
	rebuild()
