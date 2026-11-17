## Datenmodell eines Story-Graphs und das .storygraph-Dateiformat (JSON).
##
## Format:
## {
##   "format": "story_graph", "version": 1,
##   "variables": {"vertrauen": {"type": "int", "default": 0}},
##   "nodes": [{"id": "n1", "type": "dialogue", "position": [x, y], "data": {...}}],
##   "connections": [{"from": "n1", "from_port": 0, "to": "n2"}],
##   "comments": [{"id": "c1", "title": "Akt 1", "position": [x, y], "size": [w, h], "color": "#334455"}]
## }
class_name StoryGraphData
extends RefCounted

const VARIABLE_TYPES := ["bool", "int", "float", "string"]

var variables: Dictionary = {}
var nodes: Dictionary = {}
var connections: Array = []
var comments: Array = []
var meta: Dictionary = {}

## Index für schnellen Zugriff: "id:port" -> Ziel-ID
var _out_index: Dictionary = {}


static func from_dict(d: Dictionary) -> StoryGraphData:
	var g := StoryGraphData.new()
	g.meta = d.get("meta", {})
	var vars: Dictionary = d.get("variables", {})
	for name in vars:
		var v: Dictionary = vars[name]
		var type := str(v.get("type", "string"))
		g.variables[name] = {"type": type, "default": coerce(type, v.get("default"))}
	for n in d.get("nodes", []):
		var type := str(n.get("type", ""))
		var pos: Array = n.get("position", [0, 0])
		g.nodes[str(n["id"])] = {
			"id": str(n["id"]),
			"type": type,
			"position": Vector2(float(pos[0]), float(pos[1])),
			"data": StoryNodeTypes.normalize_data(type, n.get("data", {})),
		}
	for c in d.get("connections", []):
		g.connections.append({"from": str(c["from"]), "from_port": int(c["from_port"]), "to": str(c["to"])})
	g.comments = d.get("comments", []).duplicate(true)
	g._rebuild_index()
	return g


static func load_file(path: String) -> StoryGraphData:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("StoryGraph: Datei konnte nicht gelesen werden: %s" % path)
		return null
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("format", "") != StoryNodeTypes.FORMAT_NAME:
		push_error("StoryGraph: Keine gültige .storygraph-Datei: %s" % path)
		return null
	return from_dict(parsed)


func to_dict() -> Dictionary:
	var node_list := []
	for id in nodes:
		var n: Dictionary = nodes[id]
		node_list.append({
			"id": id,
			"type": n["type"],
			"position": [snappedf(n["position"].x, 0.1), snappedf(n["position"].y, 0.1)],
			"data": n["data"],
		})
	return {
		"format": StoryNodeTypes.FORMAT_NAME,
		"version": StoryNodeTypes.FORMAT_VERSION,
		"meta": meta,
		"variables": variables,
		"nodes": node_list,
		"connections": connections,
		"comments": comments,
	}


func save_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t", false))
	f.close()
	return OK


func _rebuild_index() -> void:
	_out_index.clear()
	for c in connections:
		_out_index["%s:%d" % [c["from"], c["from_port"]]] = c["to"]


## Ziel-Node eines Ausgangs oder "" wenn nicht verbunden.
func next_node(id: String, port: int) -> String:
	return _out_index.get("%s:%d" % [id, port], "")


func find_start() -> String:
	for id in nodes:
		if nodes[id]["type"] == "start":
			return id
	return ""


func find_label(label_name: String) -> String:
	for id in nodes:
		var n: Dictionary = nodes[id]
		if n["type"] == "label" and str(n["data"].get("name", "")) == label_name:
			return id
	return ""


func label_names() -> Array[String]:
	var result: Array[String] = []
	for id in nodes:
		if nodes[id]["type"] == "label":
			result.append(str(nodes[id]["data"].get("name", "")))
	return result


## Wandelt einen Wert in den Variablentyp um.
static func coerce(type: String, value) -> Variant:
	match type:
		"bool":
			if typeof(value) == TYPE_STRING:
				return value.strip_edges().to_lower() in ["true", "wahr", "1", "ja", "yes"]
			return bool(value) if value != null else false
		"int":
			if typeof(value) == TYPE_STRING:
				return value.to_int()
			return int(value) if value != null else 0
		"float":
			if typeof(value) == TYPE_STRING:
				return value.to_float()
			return float(value) if value != null else 0.0
		_:
			return str(value) if value != null else ""


static func is_valid_variable_name(n: String) -> bool:
	return n.is_valid_identifier() and not n in ["ctx", "runner", "true", "false", "and", "or", "not", "null", "self"]
