## Hauptfenster des Story Graph Editors: Layout, Dateien, Rückgängig/Wiederholen, Tastenkürzel.
extends Control

const SETTINGS_PATH := "user://editor_settings.cfg"
const MAX_UNDO := 200
const EXAMPLE_PATH := "res://examples/verhoer.storygraph"

var canvas: GraphCanvas
var palette: NodePalette
var inspector: StoryInspector
var variables_panel: VariablesPanel
var test_panel: TestPanel
var right_tabs: TabContainer
var problems: ItemList
var problems_header: Label
var status_label: Label
var file_label: Label
var undo_btn: Button
var redo_btn: Button

var add_popup: PopupPanel
var add_palette: NodePalette
var _pending_add := {}  # graph_position, from_node, from_port

var file_dialog: FileDialog
var confirm_dialog: ConfirmationDialog
var _confirm_action: Callable

var current_path := ""
var meta: Dictionary = {}
var dirty := false

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _last_coalesce_key := ""
var _restoring := false
var _validate_timer: Timer
var _issues: Array[Dictionary] = []


func _ready() -> void:
	get_tree().auto_accept_quit = false
	theme = _make_theme()
	_build_ui()
	_validate_timer = Timer.new()
	_validate_timer.one_shot = true
	_validate_timer.wait_time = 0.35
	_validate_timer.timeout.connect(_validate)
	add_child(_validate_timer)

	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	var last: String = settings.get_value("files", "last", "")
	if last != "" and FileAccess.file_exists(last):
		_open_file(last)
	else:
		_new_graph()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_confirm_discard(func(): get_tree().quit())


# --- Aufbau ------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#1b1e23")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_toolbar())

	var main_split := HSplitContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main_split)

	# Links: Palette
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.add_theme_stylebox_override("panel", _panel_style(Color("#20242a")))
	var left_box := VBoxContainer.new()
	left.add_child(left_box)
	left_box.add_child(_section_label("NODES"))
	palette = NodePalette.new()
	palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette.type_activated.connect(func(t): canvas.add_story_node(t, canvas.view_center_in_graph()))
	left_box.add_child(palette)
	var tip := Label.new()
	tip.text = "Doppelklick oder auf die Fläche ziehen"
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	left_box.add_child(tip)
	main_split.add_child(left)

	var center_split := HSplitContainer.new()
	center_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.add_child(center_split)

	# Mitte: Graph + Probleme
	var v_split := VSplitContainer.new()
	v_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_split.add_child(v_split)
	canvas = GraphCanvas.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.about_to_change.connect(_push_undo)
	canvas.changed.connect(_on_changed)
	canvas.selection_changed.connect(func(e): inspector.show_element(e))
	canvas.add_menu_requested.connect(_open_add_menu)
	v_split.add_child(canvas)

	var bottom := PanelContainer.new()
	bottom.custom_minimum_size = Vector2(0, 120)
	bottom.add_theme_stylebox_override("panel", _panel_style(Color("#20242a")))
	var bottom_box := VBoxContainer.new()
	bottom.add_child(bottom_box)
	problems_header = _section_label("PROBLEME")
	bottom_box.add_child(problems_header)
	problems = ItemList.new()
	problems.size_flags_vertical = Control.SIZE_EXPAND_FILL
	problems.item_activated.connect(_on_problem_activated)
	problems.item_selected.connect(_on_problem_activated)
	bottom_box.add_child(problems)
	v_split.add_child(bottom)

	# Rechts: Inspector / Variablen / Testlauf
	right_tabs = TabContainer.new()
	right_tabs.custom_minimum_size = Vector2(360, 0)
	center_split.add_child(right_tabs)
	inspector = StoryInspector.new()
	inspector.name = "Inspector"
	inspector.canvas = canvas
	inspector.variables_provider = func(): return variables_panel.variables
	inspector.about_to_edit.connect(_push_undo)
	inspector.edited.connect(_on_changed)
	right_tabs.add_child(inspector)
	variables_panel = VariablesPanel.new()
	variables_panel.name = "Variablen"
	variables_panel.about_to_change.connect(_push_undo)
	variables_panel.changed.connect(func():
		_on_changed()
		inspector.refresh())
	variables_panel.variable_renamed.connect(_rename_variable)
	right_tabs.add_child(variables_panel)
	test_panel = TestPanel.new()
	test_panel.name = "Testlauf"
	test_panel.graph_provider = _current_graph
	test_panel.selection_provider = func():
		var sel := canvas._selected.filter(func(e): return e is StoryEditorNode)
		return sel.back().node_id if not sel.is_empty() else ""
	test_panel.node_entered.connect(func(id): canvas.highlight_node(id))
	test_panel.run_finished.connect(func(): canvas.clear_highlight.call_deferred())
	right_tabs.add_child(test_panel)

	# Statusleiste
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", _panel_style(Color("#16191e"), 4))
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	status.add_child(status_label)
	root.add_child(status)

	# Hinzufügen-Menü
	add_popup = PopupPanel.new()
	add_popup.size = Vector2i(300, 420)
	add_palette = NodePalette.new()
	add_palette.custom_minimum_size = Vector2(300, 420)
	add_palette.type_activated.connect(_on_add_menu_chosen)
	add_popup.add_child(add_palette)
	add_child(add_popup)

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.%s ; Story Graph" % StoryNodeTypes.FILE_EXTENSION])
	file_dialog.use_native_dialog = true
	file_dialog.size = Vector2i(900, 600)
	add_child(file_dialog)

	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Ungespeicherte Änderungen"
	confirm_dialog.dialog_text = "Es gibt ungespeicherte Änderungen. Trotzdem fortfahren und verwerfen?"
	confirm_dialog.ok_button_text = "Verwerfen"
	confirm_dialog.cancel_button_text = "Abbrechen"
	confirm_dialog.confirmed.connect(func(): _confirm_action.call())
	add_child(confirm_dialog)


func _build_toolbar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#262a31"), 6))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	panel.add_child(bar)

	var file_menu := MenuButton.new()
	file_menu.text = "Datei"
	file_menu.flat = false
	var p := file_menu.get_popup()
	p.add_item("Neu                       Strg+N", 0)
	p.add_item("Öffnen …               Strg+O", 1)
	p.add_item("Speichern              Strg+S", 2)
	p.add_item("Speichern unter …  Strg+Shift+S", 3)
	p.add_separator()
	p.add_item("Beispiel öffnen (Verhör)", 4)
	p.add_separator()
	p.add_item("Beenden                 Strg+Q", 5)
	p.id_pressed.connect(_on_file_menu)
	bar.add_child(file_menu)

	var edit_menu := MenuButton.new()
	edit_menu.text = "Bearbeiten"
	edit_menu.flat = false
	var e := edit_menu.get_popup()
	e.add_item("Rückgängig                 Strg+Z", 0)
	e.add_item("Wiederholen               Strg+Y", 1)
	e.add_separator()
	e.add_item("Alles auswählen          Strg+A", 2)
	e.add_item("Duplizieren                 Strg+D", 3)
	e.add_item("Kommentar-Rahmen        K", 4)
	e.add_item("Löschen                        Entf", 5)
	e.add_separator()
	e.add_item("Alles zeigen                   F", 6)
	e.id_pressed.connect(_on_edit_menu)
	bar.add_child(edit_menu)

	bar.add_child(VSeparator.new())
	undo_btn = _tool_button("↶", "Rückgängig (Strg+Z)", undo)
	bar.add_child(undo_btn)
	redo_btn = _tool_button("↷", "Wiederholen (Strg+Y)", redo)
	bar.add_child(redo_btn)
	bar.add_child(VSeparator.new())
	bar.add_child(_tool_button("＋ Node", "Node hinzufügen (Leertaste oder Rechtsklick auf die Fläche)", func():
		_open_add_menu(canvas.global_position + Vector2(canvas.size.x * 0.5 - 150, 40), canvas.view_center_in_graph(), "", -1)))
	bar.add_child(_tool_button("▭ Kommentar", "Kommentar-Rahmen um die Auswahl (K)", func(): canvas.add_frame(canvas.view_center_in_graph())))
	bar.add_child(_tool_button("⤢ Alles zeigen", "Alle Nodes in den Blick (F)", frame_all))
	bar.add_child(VSeparator.new())
	var play := _tool_button("▶ Testlauf", "Geschichte im Editor durchspielen (F5)", func(): _start_test(""))
	play.add_theme_color_override("font_color", Color("#7be0a5"))
	bar.add_child(play)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	file_label = Label.new()
	file_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	bar.add_child(file_label)
	return panel


# --- Dateien -----------------------------------------------------------------

func _on_file_menu(id: int) -> void:
	match id:
		0: _confirm_discard(_new_graph)
		1: _confirm_discard(func(): _show_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, _open_file))
		2: save()
		3: _show_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, _save_to)
		4: _confirm_discard(func(): _open_file(EXAMPLE_PATH))
		5: _confirm_discard(func(): get_tree().quit())


func _on_edit_menu(id: int) -> void:
	match id:
		0: undo()
		1: redo()
		2: canvas.select_all()
		3: canvas.duplicate_selection()
		4: canvas.add_frame(canvas.view_center_in_graph())
		5: canvas.delete_elements(canvas._selected.map(func(x): return x.name))
		6: frame_all()


func _new_graph() -> void:
	test_panel.stop_run()
	var g := StoryGraphData.new()
	g.nodes["n1"] = {"id": "n1", "type": "start", "position": Vector2(80, 200), "data": {}}
	g.nodes["n2"] = {"id": "n2", "type": "dialogue", "position": Vector2(400, 180),
		"data": StoryNodeTypes.normalize_data("dialogue", {"speaker": "Erzähler", "text": "Hier beginnt deine Geschichte."})}
	g.connections.append({"from": "n1", "from_port": 0, "to": "n2"})
	_load_graph(g)
	current_path = ""
	_after_file_change()


func _open_file(path: String) -> void:
	var g := StoryGraphData.load_file(path)
	if g == null:
		_set_status("⚠ Datei konnte nicht geöffnet werden: " + path)
		return
	test_panel.stop_run()
	_load_graph(g)
	current_path = path
	_after_file_change()
	_remember(path)
	_set_status("Geöffnet: " + path)
	_restore_view.call_deferred(g.meta.get("editor", {}))


func save() -> void:
	if current_path == "" or current_path.begins_with("res://") and OS.has_feature("template"):
		_show_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, _save_to)
	else:
		_save_to(current_path)


func _save_to(path: String) -> void:
	if not path.ends_with("." + StoryNodeTypes.FILE_EXTENSION):
		path += "." + StoryNodeTypes.FILE_EXTENSION
	var err := _current_graph().save_file(path)
	if err != OK:
		_set_status("⚠ Speichern fehlgeschlagen (%s): %s" % [error_string(err), path])
		return
	current_path = path
	dirty = false
	_remember(path)
	_update_title()
	_set_status("Gespeichert: " + path)


func _show_file_dialog(mode: FileDialog.FileMode, callback: Callable) -> void:
	file_dialog.file_mode = mode
	file_dialog.title = "Graph öffnen" if mode == FileDialog.FILE_MODE_OPEN_FILE else "Graph speichern"
	for c in file_dialog.file_selected.get_connections():
		file_dialog.file_selected.disconnect(c["callable"])
	file_dialog.file_selected.connect(callback, CONNECT_ONE_SHOT)
	if current_path != "" and not current_path.begins_with("res://"):
		file_dialog.current_dir = current_path.get_base_dir()
	file_dialog.popup_centered()


func _confirm_discard(action: Callable) -> void:
	if not dirty:
		action.call()
		return
	_confirm_action = action
	confirm_dialog.popup_centered()


func _remember(path: String) -> void:
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("files", "last", path)
	settings.save(SETTINGS_PATH)


func _after_file_change() -> void:
	dirty = false
	_undo.clear()
	_redo.clear()
	_last_coalesce_key = ""
	test_panel.base_path = current_path
	_update_title()
	_validate()


func _update_title() -> void:
	var name := current_path.get_file() if current_path != "" else "Unbenannt"
	file_label.text = name + (" ●" if dirty else "")
	get_window().title = "%s%s – Story Graph Editor" % [name, " *" if dirty else ""]
	undo_btn.disabled = _undo.is_empty()
	redo_btn.disabled = _redo.is_empty()


# --- Graph-Zustand -----------------------------------------------------------

func _current_graph() -> StoryGraphData:
	var g := canvas.to_graph_data()
	g.variables = variables_panel.variables.duplicate(true)
	g.meta = meta.duplicate(true)
	g.meta["editor"] = {"scroll": [canvas.scroll_offset.x, canvas.scroll_offset.y], "zoom": canvas.zoom}
	return g


func _load_graph(g: StoryGraphData) -> void:
	_restoring = true
	meta = g.meta.duplicate(true)
	canvas.load_graph(g)
	variables_panel.set_variables(g.variables)
	inspector.show_element(null)
	_restoring = false


func _snapshot() -> Dictionary:
	return _current_graph().to_dict()


func _push_undo(coalesce_key: String) -> void:
	if _restoring:
		return
	# Aufeinanderfolgende Änderungen am selben Feld (z. B. Tippen) als ein Schritt.
	if coalesce_key != "" and coalesce_key == _last_coalesce_key:
		return
	_last_coalesce_key = coalesce_key
	_undo.append(_snapshot())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(_snapshot())
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(_snapshot())
	_restore(_redo.pop_back())


func _restore(d: Dictionary) -> void:
	var scroll := canvas.scroll_offset
	var z := canvas.zoom
	_load_graph(StoryGraphData.from_dict(d))
	canvas.zoom = z
	canvas.scroll_offset = scroll
	_last_coalesce_key = ""
	_on_changed()


func _on_changed() -> void:
	if _restoring:
		return
	dirty = true
	_update_title()
	_validate_timer.start()


func _rename_variable(old_name: String, new_name: String) -> void:
	var regex := RegEx.new()
	regex.compile("\\b%s\\b" % old_name)
	for n in canvas.story_nodes():
		for field in n.data:
			var info := StoryNodeTypes.get_field_info(field)
			var kind: String = info.get("kind", "")
			if kind == "variable" and n.data[field] == old_name:
				n.data[field] = new_name
			elif kind in ["expression", "code"]:
				n.data[field] = regex.sub(str(n.data[field]), new_name, true)
			elif kind == "string_list" and info.get("expression", false):
				n.data[field] = n.data[field].map(func(x): return regex.sub(str(x), new_name, true))
		n.refresh()
	inspector.refresh()


# --- Hinzufügen-Menü ---------------------------------------------------------

func _open_add_menu(global_pos: Vector2, graph_pos: Vector2, from_node: String, from_port: int) -> void:
	_pending_add = {"graph_position": graph_pos, "from_node": from_node, "from_port": from_port}
	var win_pos := Vector2i(global_pos)
	var r := get_viewport_rect().size
	win_pos.x = clampi(win_pos.x, 0, int(r.x) - add_popup.size.x)
	win_pos.y = clampi(win_pos.y, 0, int(r.y) - add_popup.size.y)
	if not get_viewport().gui_embed_subwindows:
		win_pos += get_window().position
	add_popup.popup(Rect2i(win_pos, add_popup.size))
	add_palette.focus_search()


func _on_add_menu_chosen(type: String) -> void:
	add_popup.hide()
	if _pending_add.is_empty():
		return
	var pos: Vector2 = _pending_add["graph_position"]
	if _pending_add["from_node"] != "":
		pos -= Vector2(0, 20)
	canvas.add_story_node(type, pos, _pending_add["from_node"], _pending_add["from_port"])
	_pending_add = {}


# --- Validierung -------------------------------------------------------------

func _validate() -> void:
	_issues = StoryGraphValidator.validate(_current_graph())
	problems.clear()
	var errors := 0
	var warnings := 0
	for i in _issues:
		var is_error: bool = i["severity"] == "error"
		if is_error:
			errors += 1
		else:
			warnings += 1
		var idx := problems.add_item(("⛔  " if is_error else "⚠  ") + i["message"])
		problems.set_item_custom_fg_color(idx, Color("#ff8a80") if is_error else Color("#f0c674"))
		problems.set_item_metadata(idx, i["node_id"])
	if _issues.is_empty():
		var idx := problems.add_item("✓  Keine Probleme gefunden.")
		problems.set_item_custom_fg_color(idx, Color("#7be0a5"))
		problems.set_item_selectable(idx, false)
	problems_header.text = "PROBLEME  ·  %d Fehler, %d Warnungen" % [errors, warnings]
	canvas.show_issues(_issues)
	_set_status("%d Nodes · %d Verbindungen · %d Variablen · %d Fehler · %d Warnungen" % [
		canvas.story_nodes().size(), canvas.get_connection_list().size(), variables_panel.variables.size(), errors, warnings])


func _on_problem_activated(idx: int) -> void:
	var id = problems.get_item_metadata(idx)
	if id != null and id != "":
		canvas.select_and_focus(id)


# --- Testlauf ----------------------------------------------------------------

func _start_test(from_id: String) -> void:
	right_tabs.current_tab = test_panel.get_index()
	test_panel.start_run(from_id)


# --- Ansicht -----------------------------------------------------------------

func _restore_view(view: Dictionary) -> void:
	if view.has("zoom") and view.has("scroll"):
		canvas.zoom = float(view["zoom"])
		canvas.scroll_offset = Vector2(float(view["scroll"][0]), float(view["scroll"][1]))
	else:
		frame_all()


func frame_all() -> void:
	var nodes := canvas.story_nodes()
	if nodes.is_empty():
		return
	var rect := Rect2(nodes[0].position_offset, nodes[0].size)
	for n in nodes:
		rect = rect.merge(Rect2(n.position_offset, n.size))
	rect = rect.grow(60)
	var z := clampf(minf(canvas.size.x / rect.size.x, canvas.size.y / rect.size.y), canvas.zoom_min, 1.0)
	canvas.zoom = z
	canvas.scroll_offset = rect.get_center() * z - canvas.size * 0.5


# --- Tastenkürzel --------------------------------------------------------------

func _shortcut_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: InputEventKey = e
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is TextEdit or focus is SpinBox
	var handled := true
	if k.ctrl_pressed or k.meta_pressed:
		match k.keycode:
			KEY_S:
				if k.shift_pressed:
					_show_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, _save_to)
				else:
					save()
			KEY_O: _on_file_menu(1)
			KEY_N: _on_file_menu(0)
			KEY_Q: _on_file_menu(5)
			KEY_Z:
				if typing:
					handled = false
				elif k.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				if typing:
					handled = false
				else:
					redo()
			KEY_F:
				palette.search.grab_focus()
			KEY_A:
				if typing:
					handled = false
				else:
					canvas.select_all()
			_: handled = false
	else:
		match k.keycode:
			KEY_F5:
				if k.shift_pressed:
					_start_test(test_panel.selection_provider.call())
				else:
					_start_test("")
			KEY_ESCAPE:
				if test_panel.is_running():
					test_panel.stop_run()
				else:
					handled = false
			KEY_SPACE:
				if typing or not canvas.get_global_rect().has_point(get_global_mouse_position()):
					handled = false
				else:
					var local := canvas.get_local_mouse_position()
					_open_add_menu(canvas.global_position + local, canvas.screen_to_graph(local), "", -1)
			KEY_K:
				if typing:
					handled = false
				else:
					canvas.add_frame(canvas.view_center_in_graph())
			KEY_F:
				if typing:
					handled = false
				else:
					frame_all()
			_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


# --- Theme ---------------------------------------------------------------------

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var accent := Color("#5b8def")
	var input := StyleBoxFlat.new()
	input.bg_color = Color("#15181c")
	input.border_color = Color("#3a404a")
	input.set_border_width_all(1)
	input.set_corner_radius_all(5)
	input.set_content_margin_all(6)
	var input_focus := input.duplicate()
	input_focus.border_color = accent
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, input)
		t.set_stylebox("focus", type, input_focus)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("#323844")
	btn.set_corner_radius_all(5)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	btn.content_margin_top = 5
	btn.content_margin_bottom = 5
	var btn_hover := btn.duplicate()
	btn_hover.bg_color = Color("#3d4553")
	var btn_pressed := btn.duplicate()
	btn_pressed.bg_color = accent.darkened(0.3)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, btn)
		t.set_stylebox("hover", type, btn_hover)
		t.set_stylebox("pressed", type, btn_pressed)
	var tab_panel := StyleBoxFlat.new()
	tab_panel.bg_color = Color("#20242a")
	t.set_stylebox("panel", "TabContainer", tab_panel)
	var graph_bg := StyleBoxFlat.new()
	graph_bg.bg_color = Color("#1b1e23")
	t.set_stylebox("panel", "GraphEdit", graph_bg)
	t.set_color("grid_major", "GraphEdit", Color(1, 1, 1, 0.07))
	t.set_color("grid_minor", "GraphEdit", Color(1, 1, 1, 0.03))
	t.set_color("selection_fill", "GraphEdit", Color(accent, 0.15))
	t.set_color("selection_stroke", "GraphEdit", Color(accent, 0.8))
	return t


func _panel_style(color: Color, margin := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_content_margin_all(margin)
	return s


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	return l


func _tool_button(text: String, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func _set_status(text: String) -> void:
	status_label.text = text
