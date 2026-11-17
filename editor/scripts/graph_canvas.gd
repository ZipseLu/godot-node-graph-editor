## Die Arbeitsfläche: Nodes, Verbindungen, Kommentar-Rahmen, Kopieren/Einfügen.
## Vor jeder Änderung wird about_to_change gesendet (für Rückgängig), danach changed.
class_name GraphCanvas
extends GraphEdit

signal about_to_change(coalesce_key: String)
signal changed()
signal selection_changed(element: GraphElement)
## Kontextmenü zum Hinzufügen öffnen. from_node/from_port gesetzt, wenn aus einem Ausgang gezogen wurde.
signal add_menu_requested(global_position: Vector2, graph_position: Vector2, from_node: String, from_port: int)

const FRAME_PREFIX := "frame_"

static var _clipboard: Dictionary = {}

var _next_id := 1
var _selected: Array[GraphElement] = []
var _active_node: StoryEditorNode


func _ready() -> void:
	right_disconnects = true
	minimap_enabled = true
	minimap_size = Vector2(220, 150)
	show_zoom_label = true
	snapping_enabled = true
	snapping_distance = 20
	connection_lines_thickness = 3.0
	connection_lines_curvature = 0.5
	zoom_min = 0.2
	zoom_max = 2.5

	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	connection_to_empty.connect(_on_connection_to_empty)
	popup_request.connect(_on_popup_request)
	delete_nodes_request.connect(_on_delete_nodes_request)
	copy_nodes_request.connect(copy_selection)
	cut_nodes_request.connect(cut_selection)
	paste_nodes_request.connect(paste_clipboard)
	duplicate_nodes_request.connect(duplicate_selection)
	begin_node_move.connect(func(): about_to_change.emit(""))
	end_node_move.connect(func(): changed.emit())
	node_selected.connect(_on_node_selected)
	node_deselected.connect(_on_node_deselected)
	graph_elements_linked_to_frame_request.connect(_on_link_to_frame)


# --- Aufbau ----------------------------------------------------------------

func clear_graph() -> void:
	clear_connections()
	for child in get_children():
		if child is GraphElement:
			remove_child(child)
			child.queue_free()
	_selected.clear()
	_active_node = null
	_next_id = 1
	selection_changed.emit(null)


func load_graph(g: StoryGraphData) -> void:
	clear_graph()
	for id in g.nodes:
		var n: Dictionary = g.nodes[id]
		_create_node(id, n["type"], n["position"], n["data"])
	for c in g.connections:
		if has_node(NodePath(c["from"])) and has_node(NodePath(c["to"])):
			connect_node(c["from"], c["from_port"], c["to"], 0)
	for c in g.comments:
		var frame := _create_frame(str(c.get("id", "")), str(c.get("title", "")),
			_vec(c.get("position", [0, 0])), _vec(c.get("size", [400, 300])), Color(str(c.get("color", "#3a4a6a"))))
		for node_id in c.get("nodes", []):
			if has_node(NodePath(node_id)):
				attach_graph_element_to_frame(StringName(node_id), frame.name)


## Erzeugt StoryGraphData aus dem aktuellen Zustand (ohne Variablen).
func to_graph_data() -> StoryGraphData:
	var g := StoryGraphData.new()
	for n in story_nodes():
		g.nodes[n.node_id] = {"id": n.node_id, "type": n.node_type, "position": n.position_offset, "data": n.data.duplicate(true)}
	for c in get_connection_list():
		g.connections.append({"from": str(c["from_node"]), "from_port": int(c["from_port"]), "to": str(c["to_node"])})
	for f in frames():
		var attached := []
		for e in get_attached_nodes_of_frame(f.name):
			attached.append(str(e))
		g.comments.append({
			"id": str(f.name).trim_prefix(FRAME_PREFIX),
			"title": f.title,
			"position": [f.position_offset.x, f.position_offset.y],
			"size": [f.size.x, f.size.y],
			"color": f.get_meta("color", Color("#3a4a6a")).to_html(false),
			"nodes": attached,
		})
	g._rebuild_index()
	return g


func story_nodes() -> Array[StoryEditorNode]:
	var result: Array[StoryEditorNode] = []
	for child in get_children():
		if child is StoryEditorNode and not child.is_queued_for_deletion():
			result.append(child)
	return result


func frames() -> Array[GraphFrame]:
	var result: Array[GraphFrame] = []
	for child in get_children():
		if child is GraphFrame and not child.is_queued_for_deletion():
			result.append(child)
	return result


func get_story_node(id: String) -> StoryEditorNode:
	var n := get_node_or_null(NodePath(id))
	return n as StoryEditorNode


# --- Bearbeiten ------------------------------------------------------------

## Fügt einen Node hinzu (mit Rückgängig-Eintrag) und gibt ihn zurück.
func add_story_node(type: String, graph_pos: Vector2, auto_connect_from := "", from_port := -1) -> StoryEditorNode:
	about_to_change.emit("")
	var node := _create_node(_new_id(), type, graph_pos, {})
	if auto_connect_from != "" and StoryNodeTypes.get_def(type).get("has_input", true):
		_disconnect_output(auto_connect_from, from_port)
		connect_node(auto_connect_from, from_port, node.name, 0)
	set_selected(node)
	changed.emit()
	return node


func add_frame(graph_pos: Vector2) -> GraphFrame:
	about_to_change.emit("")
	var frame := _create_frame("", "Kommentar", graph_pos, Vector2(480, 320), Color("#3a4a6a"))
	# Bereits ausgewählte Nodes gleich einrahmen.
	var nodes := _selected.filter(func(e): return e is StoryEditorNode)
	if not nodes.is_empty():
		var rect := Rect2(nodes[0].position_offset, nodes[0].size)
		for n in nodes:
			rect = rect.merge(Rect2(n.position_offset, n.size))
		frame.position_offset = rect.position - Vector2(30, 60)
		frame.size = rect.size + Vector2(60, 90)
		for n in nodes:
			attach_graph_element_to_frame(n.name, frame.name)
	set_selected(frame)
	changed.emit()
	return frame


## Nach Änderung der Daten im Inspector: Node neu aufbauen, überzählige Verbindungen entfernen.
func refresh_node(node: StoryEditorNode) -> void:
	node.refresh()
	var count := node.output_count()
	for c in get_connection_list():
		if str(c["from_node"]) == node.node_id and int(c["from_port"]) >= count:
			disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])


## Baut einen Node neu auf und verschiebt dabei seine Ausgangs-Verbindungen.
## port_map: Callable(alter_port) -> neuer_port oder -1 (Verbindung entfernen).
func rebuild_node_with_port_map(node: StoryEditorNode, port_map: Callable) -> void:
	var outgoing := []
	for c in get_connection_list():
		if str(c["from_node"]) == node.node_id:
			outgoing.append(c)
			disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])
	node.refresh()
	var count := node.output_count()
	for c in outgoing:
		var p: int = port_map.call(int(c["from_port"]))
		if p >= 0 and p < count:
			_disconnect_output(node.name, p)
			connect_node(node.name, p, c["to_node"], c["to_port"])


func delete_elements(names: Array) -> void:
	if names.is_empty():
		return
	about_to_change.emit("")
	for n in names:
		var element := get_node_or_null(NodePath(str(n)))
		if element == null:
			continue
		for c in get_connection_list():
			if str(c["from_node"]) == str(n) or str(c["to_node"]) == str(n):
				disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])
		if element is GraphFrame:
			for attached in get_attached_nodes_of_frame(element.name):
				detach_graph_element_from_frame(attached)
		elif element is GraphElement:
			var frame := get_element_frame(element.name)
			if frame != null:
				detach_graph_element_from_frame(element.name)
		_selected.erase(element)
		remove_child(element)
		element.queue_free()
	selection_changed.emit(_selected.back() if not _selected.is_empty() else null)
	changed.emit()


func select_all() -> void:
	for child in get_children():
		if child is GraphElement:
			child.selected = true


func copy_selection() -> void:
	var ids := {}
	var nodes := []
	for e in _selected:
		if e is StoryEditorNode:
			ids[e.node_id] = true
			nodes.append({"id": e.node_id, "type": e.node_type, "position": e.position_offset, "data": e.data.duplicate(true)})
	if nodes.is_empty():
		return
	var conns := []
	for c in get_connection_list():
		if ids.has(str(c["from_node"])) and ids.has(str(c["to_node"])):
			conns.append({"from": str(c["from_node"]), "from_port": int(c["from_port"]), "to": str(c["to_node"])})
	_clipboard = {"nodes": nodes, "connections": conns}
	# Auch in die System-Zwischenablage, damit man zwischen Editor-Fenstern kopieren kann.
	var serial := nodes.map(func(n): return {"id": n["id"], "type": n["type"], "position": [n["position"].x, n["position"].y], "data": n["data"]})
	DisplayServer.clipboard_set(JSON.stringify({"story_graph_clipboard": {"nodes": serial, "connections": conns}}))


func cut_selection() -> void:
	copy_selection()
	delete_elements(_selected.map(func(e): return e.name))


func paste_clipboard() -> void:
	var clip := _clipboard
	var sys = JSON.parse_string(DisplayServer.clipboard_get())
	if typeof(sys) == TYPE_DICTIONARY and sys.has("story_graph_clipboard"):
		clip = sys["story_graph_clipboard"]
	if clip.is_empty() or clip.get("nodes", []).is_empty():
		return
	_paste(clip, screen_to_graph(get_local_mouse_position()))


func duplicate_selection() -> void:
	copy_selection()
	if _clipboard.is_empty():
		return
	var first: Dictionary = _clipboard["nodes"][0]
	var top_left: Vector2 = first["position"]
	for n in _clipboard["nodes"]:
		top_left = top_left.min(n["position"])
	_paste(_clipboard, top_left + Vector2(40, 40))


func _paste(clip: Dictionary, at: Vector2) -> void:
	about_to_change.emit("")
	var top_left := Vector2(INF, INF)
	for n in clip["nodes"]:
		top_left = top_left.min(_vec(n["position"]))
	var mapping := {}
	for e in _selected.duplicate():
		e.selected = false
	for n in clip["nodes"]:
		var node := _create_node(_new_id(), str(n["type"]), _vec(n["position"]) - top_left + at, n["data"].duplicate(true))
		mapping[str(n["id"])] = node.node_id
		node.selected = true
	for c in clip["connections"]:
		if mapping.has(c["from"]) and mapping.has(c["to"]):
			connect_node(mapping[c["from"]], int(c["from_port"]), mapping[c["to"]], 0)
	changed.emit()


# --- Testlauf-Hervorhebung ---------------------------------------------------

func highlight_node(id: String, center := true) -> void:
	if _active_node != null and is_instance_valid(_active_node):
		_active_node.set_active(false)
	_active_node = get_story_node(id)
	if _active_node != null:
		_active_node.set_active(true)
		if center:
			focus_element(_active_node)


func clear_highlight() -> void:
	highlight_node("", false)


func focus_element(e: GraphElement) -> void:
	var target := (e.position_offset + e.size * 0.5) * zoom - size * 0.5
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scroll_offset", target, 0.25)


func select_and_focus(id: String) -> void:
	var e := get_node_or_null(NodePath(id)) as GraphElement
	if e == null:
		return
	set_selected(e)
	focus_element(e)


func show_issues(issues: Array) -> void:
	var levels := {}
	for i in issues:
		var id: String = i["node_id"]
		if id == "":
			continue
		if i["severity"] == "error" or not levels.has(id):
			levels[id] = i["severity"]
	for n in story_nodes():
		n.set_issue_level(levels.get(n.node_id, ""))


# --- Koordinaten -------------------------------------------------------------

func screen_to_graph(local_pos: Vector2) -> Vector2:
	return (local_pos + scroll_offset) / zoom


func view_center_in_graph() -> Vector2:
	return screen_to_graph(size * 0.5) - Vector2(StoryEditorNode.WIDTH * 0.5, 40)


# --- Drag & Drop aus der Palette -------------------------------------------

func _can_drop_data(_at: Vector2, d: Variant) -> bool:
	return typeof(d) == TYPE_DICTIONARY and d.has("story_node_type")


func _drop_data(at: Vector2, d: Variant) -> void:
	add_story_node(d["story_node_type"], screen_to_graph(at) - Vector2(StoryEditorNode.WIDTH * 0.5, 20))


# --- Interne Helfer ----------------------------------------------------------

func _create_node(id: String, type: String, pos: Vector2, node_data: Dictionary) -> StoryEditorNode:
	var node := StoryEditorNode.new()
	node.setup(id, type, node_data)
	node.position_offset = pos
	add_child(node)
	_bump_id(id)
	return node


func _create_frame(id: String, frame_title: String, pos: Vector2, frame_size: Vector2, color: Color) -> GraphFrame:
	if id == "":
		id = _new_id()
	var frame := GraphFrame.new()
	frame.name = FRAME_PREFIX + id
	frame.title = frame_title
	frame.position_offset = pos
	frame.size = frame_size
	frame.autoshrink_enabled = false
	frame.tint_color_enabled = true
	frame.tint_color = Color(color, 0.35)
	frame.set_meta("color", color)
	frame.resizable = true
	add_child(frame)
	move_child(frame, 0)  # hinter die Nodes
	_bump_id(id)
	return frame


func set_frame_color(frame: GraphFrame, color: Color) -> void:
	frame.set_meta("color", color)
	frame.tint_color = Color(color, 0.35)


func _new_id() -> String:
	while has_node(NodePath("n%d" % _next_id)) or has_node(NodePath(FRAME_PREFIX + "n%d" % _next_id)):
		_next_id += 1
	var id := "n%d" % _next_id
	_next_id += 1
	return id


func _bump_id(id: String) -> void:
	if id.begins_with("n") and id.substr(1).is_valid_int():
		_next_id = maxi(_next_id, id.substr(1).to_int() + 1)


func _disconnect_output(from: StringName, port: int) -> void:
	for c in get_connection_list():
		if c["from_node"] == from and int(c["from_port"]) == port:
			disconnect_node(c["from_node"], c["from_port"], c["to_node"], c["to_port"])


func _on_connection_request(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	if from == to:
		return
	about_to_change.emit("")
	# Ein Ausgang führt immer genau zu einem Ziel.
	_disconnect_output(from, from_port)
	connect_node(from, from_port, to, to_port)
	changed.emit()


func _on_disconnection_request(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	about_to_change.emit("")
	disconnect_node(from, from_port, to, to_port)
	changed.emit()


func _on_connection_to_empty(from: StringName, from_port: int, release_position: Vector2) -> void:
	add_menu_requested.emit(global_position + release_position, screen_to_graph(release_position), str(from), from_port)


func _on_popup_request(at: Vector2) -> void:
	add_menu_requested.emit(global_position + at, screen_to_graph(at), "", -1)


func _on_delete_nodes_request(names: Array[StringName]) -> void:
	delete_elements(names)


func _on_node_selected(e: Node) -> void:
	if e is GraphElement and not _selected.has(e):
		_selected.append(e)
	selection_changed.emit(e)


func _on_node_deselected(e: Node) -> void:
	_selected.erase(e)
	selection_changed.emit(_selected.back() if not _selected.is_empty() else null)


func _on_link_to_frame(elements: Array, frame: StringName) -> void:
	about_to_change.emit("")
	for e in elements:
		attach_graph_element_to_frame(e, frame)
	changed.emit()


static func _vec(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	return Vector2(float(v[0]), float(v[1]))
