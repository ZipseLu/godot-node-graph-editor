## Findet das Godot-Spielprojekt zu einer Graph-Datei und liest daraus die Story-IDs
## (StoryActor) und Ereignisse (StoryTrigger), damit der Inspector sie zur Auswahl anbietet.
class_name GameProjectScanner
extends RefCounted

const MAX_FILES := 4000

var root := ""  # absoluter Pfad des Spielprojekts, "" wenn keins gefunden
## id -> Array[String] Szenen (res://…)
var actors: Dictionary = {}
var events: Dictionary = {}


## Sucht von der Graph-Datei aufwärts nach project.godot.
static func find_root(graph_path: String) -> String:
	if graph_path == "":
		return ""
	var dir := ProjectSettings.globalize_path(graph_path).get_base_dir()
	for i in 32:
		if FileAccess.file_exists(dir.path_join("project.godot")):
			return dir
		var parent := dir.get_base_dir()
		if parent == dir or parent == "":
			break
		dir = parent
	return ""


func scan(graph_path: String) -> void:
	root = find_root(graph_path)
	actors.clear()
	events.clear()
	if root == "":
		return
	var files: Array[String] = []
	_collect(root, files)
	var id_re := RegEx.create_from_string("(?m)^story_id = \"([^\"]+)\"")
	var ev_re := RegEx.create_from_string("(?m)^event_name = \"([^\"]+)\"")
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		if not ("story_id" in text or "event_name" in text):
			continue
		var res := to_res_path(f)
		for m in id_re.search_all(text):
			_add(actors, m.get_string(1), res)
		for m in ev_re.search_all(text):
			_add(events, m.get_string(1), res)


## Absoluten Pfad in res:// umwandeln, wenn er im Spielprojekt liegt.
func to_res_path(path: String) -> String:
	var abs := ProjectSettings.globalize_path(path)
	if root != "" and abs.begins_with(root + "/"):
		return "res://" + abs.substr(root.length() + 1)
	return path


func _add(target: Dictionary, key: String, scene: String) -> void:
	if not target.has(key):
		target[key] = []
	if not scene in target[key]:
		target[key].append(scene)


func _collect(dir: String, out: Array[String]) -> void:
	if out.size() >= MAX_FILES:
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = false
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		_collect(dir.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".tscn"):
			out.append(dir.path_join(f))
