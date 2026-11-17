## Rechtes Panel: zeigt und bearbeitet die Felder des ausgewählten Nodes oder Rahmens.
class_name StoryInspector
extends ScrollContainer

## Vor einer Feldänderung (für Rückgängig; gleiche Schlüssel werden zusammengefasst).
signal about_to_edit(coalesce_key: String)
signal edited()

var canvas: GraphCanvas
## Wird vom Hauptfenster gesetzt: liefert die Variablen-Definitionen.
var variables_provider: Callable

var _box: VBoxContainer
var _node: StoryEditorNode
var _frame: GraphFrame


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	margin.add_child(_box)
	show_element(null)


func show_element(e: GraphElement) -> void:
	_node = e as StoryEditorNode
	_frame = e as GraphFrame
	_rebuild()


func refresh() -> void:
	_rebuild()


func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if _node != null and is_instance_valid(_node):
		_build_node_ui()
	elif _frame != null and is_instance_valid(_frame):
		_build_frame_ui()
	else:
		_build_empty_ui()


func _build_empty_ui() -> void:
	var title := _heading("Nichts ausgewählt", Color(1, 1, 1, 0.7))
	_box.add_child(title)
	_box.add_child(_hint(
		"• Rechtsklick oder Leertaste auf der Fläche: Node hinzufügen\n" +
		"• Aus einem Ausgang ins Leere ziehen: neuen Node direkt verbinden\n" +
		"• Nodes aus der Palette links auf die Fläche ziehen\n" +
		"• Rechtsklick auf einen Eingang/Ausgang: Verbindung lösen\n" +
		"• Strg+C / Strg+V / Strg+D: Kopieren, Einfügen, Duplizieren\n" +
		"• Entf: Löschen   • Strg+Z / Strg+Y: Rückgängig / Wiederholen\n" +
		"• K: Kommentar-Rahmen um die Auswahl\n" +
		"• F5: Testlauf starten"))


func _build_frame_ui() -> void:
	_box.add_child(_heading("Kommentar-Rahmen", Color("#a0b4d8")))
	_box.add_child(_hint("Zieh Nodes in den Rahmen, um sie zu gruppieren. Verschiebst du den Rahmen, wandern sie mit."))
	var title_edit := LineEdit.new()
	title_edit.text = _frame.title
	title_edit.text_changed.connect(func(t):
		about_to_edit.emit("frame_title_" + _frame.name)
		_frame.title = t
		edited.emit())
	_add_row("Titel", title_edit)
	var color := ColorPickerButton.new()
	color.color = _frame.get_meta("color", Color("#3a4a6a"))
	color.edit_alpha = false
	color.custom_minimum_size = Vector2(0, 30)
	color.color_changed.connect(func(c):
		about_to_edit.emit("frame_color_" + _frame.name)
		canvas.set_frame_color(_frame, c)
		edited.emit())
	_add_row("Farbe", color)


func _build_node_ui() -> void:
	var def := StoryNodeTypes.get_def(_node.node_type)
	var color := StoryNodeTypes.category_color(def.get("category", ""))
	var cat_title: String = StoryNodeTypes.CATEGORIES.get(def.get("category", ""), {}).get("title", "")
	_box.add_child(_heading(def.get("title", _node.node_type), color))
	var sub := _hint("%s  ·  ID %s" % [cat_title, _node.node_id])
	_box.add_child(sub)
	if def.has("help"):
		_box.add_child(_hint(def["help"]))
	_box.add_child(HSeparator.new())

	for field in _node.data:
		if not def.get("fields", {}).has(field):
			continue
		var info := StoryNodeTypes.get_field_info(field)
		_add_row(info.get("label", field), _make_editor(field, info))

	if def.get("fields", {}).is_empty():
		_box.add_child(_hint("Dieser Node hat keine Einstellungen."))


# --- Feld-Editoren -----------------------------------------------------------

func _make_editor(field: String, info: Dictionary) -> Control:
	var value = _node.data[field]
	var kind: String = info.get("kind", "string")
	match kind:
		"multiline", "code":
			var te := TextEdit.new()
			te.text = str(value)
			te.placeholder_text = info.get("placeholder", "")
			te.custom_minimum_size = Vector2(0, 110 if kind == "multiline" else 70)
			te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			te.scroll_fit_content_height = kind == "multiline"
			var err := _error_label() if kind == "code" else null
			te.text_changed.connect(func():
				_set_field(field, te.text, false)
				if err != null:
					_validate_expression(te.text, err, false))
			if err != null:
				var box := VBoxContainer.new()
				box.add_child(te)
				box.add_child(err)
				_validate_expression(te.text, err, false)
				return box
			return te
		"expression":
			var box := VBoxContainer.new()
			var le := LineEdit.new()
			le.text = str(value)
			le.placeholder_text = info.get("placeholder", "")
			le.add_theme_font_override("font", _mono_font())
			var err := _error_label()
			le.text_changed.connect(func(t):
				_set_field(field, t, false)
				_validate_expression(t, err, false))
			box.add_child(le)
			box.add_child(_variable_insert_bar(le))
			box.add_child(err)
			_validate_expression(le.text, err, false)
			return box
		"float", "int":
			var sb := SpinBox.new()
			sb.min_value = info.get("min", -999999)
			sb.max_value = info.get("max", 999999)
			sb.step = info.get("step", 1.0 if kind == "int" else 0.1)
			sb.allow_greater = true
			sb.value = float(value)
			var structural := field in ["time_limit", "steps"]
			sb.value_changed.connect(func(v):
				_set_field(field, int(v) if kind == "int" else v, structural))
			return sb
		"bool":
			var cb := CheckBox.new()
			cb.text = "Ja"
			cb.button_pressed = bool(value)
			cb.toggled.connect(func(on): _set_field(field, on, false))
			return cb
		"enum":
			var ob := OptionButton.new()
			var options: Array = info.get("options", [])
			for i in options.size():
				ob.add_item(options[i][1])
				ob.set_item_metadata(i, options[i][0])
				if options[i][0] == value:
					ob.select(i)
			ob.item_selected.connect(func(i):
				_set_field(field, ob.get_item_metadata(i), false)
				if field == "op":
					refresh())
			return ob
		"variable":
			return _variable_picker(field, str(value))
		"label_ref":
			var ob := OptionButton.new()
			var labels := canvas.to_graph_data().label_names()
			if not str(value) in labels:
				labels.push_front(str(value))
			for i in labels.size():
				var l: String = labels[i]
				ob.add_item(l if l != "" else "(Sprungmarke wählen)")
				ob.set_item_metadata(i, l)
				if l == str(value):
					ob.select(i)
			ob.item_selected.connect(func(i): _set_field(field, ob.get_item_metadata(i), false))
			return ob
		"string_list", "int_list":
			return _list_editor(field, info, kind == "int_list")
		_:
			var le := LineEdit.new()
			le.text = str(value)
			le.placeholder_text = info.get("placeholder", "")
			le.text_changed.connect(func(t): _set_field(field, t, false))
			return le


func _variable_picker(field: String, current: String) -> Control:
	var vars: Dictionary = variables_provider.call()
	var ob := OptionButton.new()
	ob.add_item("(Variable wählen)")
	ob.set_item_metadata(0, "")
	var idx := 1
	var found := current == ""
	for name in vars:
		ob.add_item("%s   (%s)" % [name, _type_label(vars[name]["type"])])
		ob.set_item_metadata(idx, name)
		if name == current:
			ob.select(idx)
			found = true
		idx += 1
	if not found:
		ob.add_item("⚠ %s (existiert nicht)" % current)
		ob.set_item_metadata(idx, current)
		ob.select(idx)
	ob.item_selected.connect(func(i): _set_field(field, ob.get_item_metadata(i), false))
	if vars.is_empty():
		var box := VBoxContainer.new()
		box.add_child(ob)
		box.add_child(_hint("Noch keine Variablen. Lege sie im Tab 'Variablen' an."))
		return box
	return ob


## Kleine Leiste, die Variablennamen per Klick in ein Ausdrucksfeld einfügt.
func _variable_insert_bar(le: LineEdit) -> Control:
	var vars: Dictionary = variables_provider.call()
	var mb := MenuButton.new()
	mb.text = "＋ Variable einfügen"
	mb.flat = true
	mb.add_theme_font_size_override("font_size", 12)
	mb.disabled = vars.is_empty()
	var popup := mb.get_popup()
	for name in vars:
		popup.add_item(name)
	popup.index_pressed.connect(func(i):
		var name := popup.get_item_text(i)
		le.insert_text_at_caret(name)
		le.text_changed.emit(le.text)
		le.grab_focus())
	return mb


func _list_editor(field: String, info: Dictionary, ints: bool) -> Control:
	var box := VBoxContainer.new()
	var items: Array = _node.data[field]
	var is_expr: bool = info.get("expression", false)
	for i in items.size():
		var row := HBoxContainer.new()
		var editor: Control
		if ints:
			var sb := SpinBox.new()
			sb.min_value = 0
			sb.max_value = 1000
			sb.value = float(items[i])
			sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sb.value_changed.connect(func(v):
				var list: Array = _node.data[field].duplicate()
				list[i] = int(v)
				_set_field(field, list, true))
			editor = sb
		else:
			var le := LineEdit.new()
			le.text = str(items[i])
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if is_expr:
				le.add_theme_font_override("font", _mono_font())
			le.text_changed.connect(func(t):
				var list: Array = _node.data[field].duplicate()
				list[i] = t
				_set_field(field, list, field in ["options", "cases"], "%s_%d" % [field, i]))
			editor = le
		row.add_child(editor)
		var up := Button.new()
		up.text = "▲"
		up.flat = true
		up.tooltip_text = "Nach oben"
		up.disabled = i == 0
		up.pressed.connect(func(): _move_item(field, i, -1))
		row.add_child(up)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "Entfernen (Verbindung dieses Ausgangs geht verloren)"
		del.pressed.connect(func():
			var list: Array = _node.data[field].duplicate()
			var n_old := list.size()
			list.remove_at(i)
			_set_list_with_port_map(field, list, func(p: int) -> int:
				if p < i: return p
				if p == i: return -1
				if p < n_old: return p - 1
				return p - 1)
			refresh())
		row.add_child(del)
		box.add_child(row)
	var add := Button.new()
	add.text = "＋ Hinzufügen"
	add.pressed.connect(func():
		var list: Array = _node.data[field].duplicate()
		var n_old := list.size()
		list.append(info.get("item_default", 0 if ints else ""))
		_set_list_with_port_map(field, list, func(p: int) -> int: return p if p < n_old else p + 1)
		refresh())
	box.add_child(add)
	return box


func _move_item(field: String, i: int, dir: int) -> void:
	var list: Array = _node.data[field].duplicate()
	var j := i + dir
	if j < 0 or j >= list.size():
		return
	var tmp = list[i]
	list[i] = list[j]
	list[j] = tmp
	# Verbindungen der beiden Ausgänge mittauschen, damit die Logik erhalten bleibt.
	_set_list_with_port_map(field, list, func(p: int) -> int:
		if p == i: return j
		if p == j: return i
		return p)
	refresh()


## Listenfeld setzen, das Ausgänge erzeugt (Optionen, Fälle, Gewichtungen), und Verbindungen umhängen.
func _set_list_with_port_map(field: String, list: Array, port_map: Callable) -> void:
	about_to_edit.emit("")
	_node.data[field] = list
	if field in ["options", "cases", "weights"]:
		canvas.rebuild_node_with_port_map(_node, port_map)
	else:
		canvas.refresh_node(_node)
	edited.emit()


func _set_field(field: String, value: Variant, structural: bool, key_suffix := "") -> void:
	about_to_edit.emit("%s.%s%s" % [_node.node_id, field, key_suffix])
	_node.data[field] = value
	if structural:
		canvas.refresh_node(_node)
	else:
		_node.refresh()
	edited.emit()


func _validate_expression(text: String, label: Label, required: bool) -> void:
	if text.strip_edges() == "":
		label.text = "Ausdruck fehlt." if required else ""
		label.visible = required
		return
	var names := PackedStringArray(variables_provider.call().keys())
	names.append_array(["ctx", "runner"])
	var expr := Expression.new()
	if expr.parse(text, names) != OK:
		label.text = "⚠ " + expr.get_error_text()
		label.visible = true
	else:
		label.text = ""
		label.visible = false


# --- UI-Helfer ---------------------------------------------------------------

func _add_row(label_text: String, editor: Control) -> void:
	var l := Label.new()
	l.text = label_text
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	l.add_theme_font_size_override("font_size", 13)
	_box.add_child(l)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(editor)


func _heading(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color.lightened(0.2))
	return l


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	l.add_theme_font_size_override("font_size", 13)
	return l


func _error_label() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color("#ff7a6e"))
	l.add_theme_font_size_override("font_size", 12)
	l.visible = false
	return l


func _type_label(t: String) -> String:
	return {"bool": "wahr/falsch", "int": "Ganzzahl", "float": "Kommazahl", "string": "Text"}.get(t, t)


static var _mono: Font
func _mono_font() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["JetBrains Mono", "Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
		_mono = f
	return _mono
