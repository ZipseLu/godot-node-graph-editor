## Führt einen .storygraph im Spiel aus.
##
## Verwendung:
##   1. StoryGraphRunner als Node in deine Szene hängen, graph_path setzen.
##   2. Signale verbinden (dialogue_requested, choice_requested, …).
##   3. start() aufrufen. Dein UI ruft advance() nach einem Dialog und choose(index) nach einer Entscheidung.
@icon("res://addons/story_graph/runtime/icon.svg")
class_name StoryGraphRunner
extends Node

## Eine Dialogzeile soll angezeigt werden. Danach advance() aufrufen.
signal dialogue_requested(speaker: String, text: String, node_id: String)
## Eine Entscheidung soll angezeigt werden. Danach choose(index) aufrufen.
## time_limit ist 0, wenn es kein Zeitlimit gibt.
signal choice_requested(prompt: String, options: Array, time_limit: float, node_id: String)
## Die Zeit für eine Entscheidung ist abgelaufen (UI sollte die Auswahl schließen).
signal choice_timed_out(node_id: String)
signal variable_changed(variable_name: String, value: Variant, old_value: Variant)
signal task_started(task_id: String, description: String)
signal task_finished(task_id: String, success: bool)
signal countdown_started(seconds: float, node_id: String)
signal countdown_finished(success: bool, node_id: String)
## Vom Node "Signal senden".
signal custom_signal(signal_name: String, payload: Variant)
signal node_entered(node_id: String, node_type: String)
signal started()
signal finished(ending_id: String)
signal error_occurred(message: String, node_id: String)

signal _advanced()
signal _chosen(index: int)
signal _tasks_changed()

## Der Graph, der bei start() ausgeführt wird.
@export_file("*.storygraph") var graph_path: String = ""
## Node, auf den sich "Methode aufrufen" und 'ctx' in Ausdrücken beziehen. Standard: Eltern-Node.
@export var context: Node
@export var autostart := false
## Schutz gegen Endlosschleifen ohne Wartepunkt.
@export var max_steps_without_wait := 10000

var graph: StoryGraphData
var variables: Dictionary = {}
## task_id -> {"description": String, "status": "active"|"done"|"failed"}
var tasks: Dictionary = {}
## Besuchte Nodes in Reihenfolge, z. B. für eine Flowchart-Übersicht.
var history: Array[String] = []
var visit_counts: Dictionary = {}
var current_node_id := ""
var running := false

var _run_id := 0
var _sync_steps := 0
var _graph_cache: Dictionary = {}
var _waiting_for := ""  # "advance" | "choice" | ""


func _ready() -> void:
	if context == null:
		context = get_parent()
	if autostart:
		start.call_deferred()


# --- Öffentliche API -------------------------------------------------------

func load_graph(path: String) -> bool:
	var g := StoryGraphData.load_file(path)
	if g == null:
		return false
	graph_path = path
	set_graph(g)
	return true


func set_graph(g: StoryGraphData) -> void:
	graph = g
	_graph_cache.clear()
	reset_variables()


## Setzt alle Variablen auf ihre Standardwerte (Tasks und Verlauf bleiben).
func reset_variables() -> void:
	variables.clear()
	if graph == null:
		return
	for name in graph.variables:
		variables[name] = graph.variables[name]["default"]


## Startet den Graph am Start-Node oder an einem beliebigen Node (z. B. nach dem Laden eines Spielstands).
func start(from_node_id: String = "") -> void:
	if graph == null and graph_path != "":
		if not load_graph(graph_path):
			return
	if graph == null:
		_error("Kein Graph geladen.", "")
		return
	var entry := from_node_id if from_node_id != "" else graph.find_start()
	if entry == "" or not graph.nodes.has(entry):
		_error("Start-Node nicht gefunden.", entry)
		return
	_run_id += 1
	running = true
	started.emit()
	var run := _run_id
	var result: Dictionary = await _run_graph(graph, entry, run)
	if run != _run_id:
		return
	running = false
	_waiting_for = ""
	finished.emit(result.get("ending", ""))


## Bricht die Ausführung ab.
func stop() -> void:
	_run_id += 1
	running = false
	_waiting_for = ""


## Nach einem Dialog weitermachen.
func advance() -> void:
	if _waiting_for == "advance":
		_waiting_for = ""
		_advanced.emit()


## Eine Option der aktuellen Entscheidung wählen (0-basiert).
func choose(index: int) -> void:
	if _waiting_for == "choice":
		_waiting_for = ""
		_chosen.emit(index)


func is_waiting_for_advance() -> bool:
	return _waiting_for == "advance"


func is_waiting_for_choice() -> bool:
	return _waiting_for == "choice"


func get_var(variable_name: String, default: Variant = null) -> Variant:
	return variables.get(variable_name, default)


func set_var(variable_name: String, value: Variant) -> void:
	if graph != null and graph.variables.has(variable_name):
		value = StoryGraphData.coerce(graph.variables[variable_name]["type"], value)
	var old = variables.get(variable_name)
	variables[variable_name] = value
	if old != value:
		variable_changed.emit(variable_name, value, old)


## Vom Spiel aus eine Aufgabe abschließen.
func complete_task(task_id: String, success := true) -> void:
	var t: Dictionary = tasks.get(task_id, {"description": ""})
	t["status"] = "done" if success else "failed"
	tasks[task_id] = t
	task_finished.emit(task_id, success)
	_tasks_changed.emit()


func is_task_active(task_id: String) -> bool:
	return tasks.get(task_id, {}).get("status", "") == "active"


func was_visited(node_id: String) -> bool:
	return visit_counts.has(node_id)


## Zustand für Spielstände. current_node kann an start() übergeben werden.
func get_state() -> Dictionary:
	return {
		"graph_path": graph_path,
		"variables": variables.duplicate(true),
		"tasks": tasks.duplicate(true),
		"history": history.duplicate(),
		"visit_counts": visit_counts.duplicate(),
		"current_node": current_node_id,
	}


func set_state(state: Dictionary) -> void:
	if state.get("graph_path", "") != "" and state["graph_path"] != graph_path:
		load_graph(state["graph_path"])
	variables = state.get("variables", {}).duplicate(true)
	tasks = state.get("tasks", {}).duplicate(true)
	history.assign(state.get("history", []))
	visit_counts = state.get("visit_counts", {}).duplicate()
	current_node_id = state.get("current_node", "")


## Wertet einen Ausdruck mit den Story-Variablen aus. 'ctx' = Kontext-Node, 'runner' = dieser Runner.
func evaluate(text: String, default: Variant = null, node_id := "") -> Variant:
	if text.strip_edges() == "":
		return default
	var names := PackedStringArray(variables.keys())
	var values: Array = variables.values()
	names.append_array(["ctx", "runner"])
	values.append_array([context, self])
	var expr := Expression.new()
	if expr.parse(text, names) != OK:
		_error("Ausdruck '%s' ist ungültig: %s" % [text, expr.get_error_text()], node_id)
		return default
	var result = expr.execute(values, self, false)
	if expr.has_execute_failed():
		_error("Ausdruck '%s' konnte nicht ausgeführt werden: %s" % [text, expr.get_error_text()], node_id)
		return default
	return result


# --- Ausführung ------------------------------------------------------------

## Führt einen Graph ab entry aus. Ergebnis: {"ending": String} oder {"stopped": true}.
func _run_graph(g: StoryGraphData, entry: String, run: int) -> Dictionary:
	var result: Dictionary = await _run_flow(g, entry, run)
	return result


## Folgt dem Ablauf, bis ein Ende erreicht oder ein Ausgang unverbunden ist.
## Ergebnis: {"ending": id} bei Ende-Node, {} bei offenem Ausgang, {"stopped": true} bei Abbruch.
func _run_flow(g: StoryGraphData, entry: String, run: int) -> Dictionary:
	var node_id := entry
	while node_id != "":
		if run != _run_id:
			return {"stopped": true}
		if not g.nodes.has(node_id):
			_error("Node '%s' existiert nicht." % node_id, node_id)
			return {"stopped": true}
		_sync_steps += 1
		if _sync_steps > max_steps_without_wait:
			_error("Endlosschleife erkannt: %d Schritte ohne Wartepunkt." % max_steps_without_wait, node_id)
			stop()
			return {"stopped": true}
		var node: Dictionary = g.nodes[node_id]
		current_node_id = node_id
		history.append(node_id)
		visit_counts[node_id] = int(visit_counts.get(node_id, 0)) + 1
		node_entered.emit(node_id, node["type"])

		var outcome: Dictionary = await _execute(g, node_id, node, run)
		if run != _run_id:
			return {"stopped": true}
		if outcome.has("ending") or outcome.has("stopped"):
			return outcome
		if outcome.has("goto"):
			node_id = outcome["goto"]
			continue
		node_id = g.next_node(node_id, int(outcome.get("port", 0)))
	return {}


## Führt einen Node aus. Ergebnis: {"port": n}, {"goto": id}, {"ending": id} oder {"stopped": true}.
func _execute(g: StoryGraphData, id: String, node: Dictionary, run: int) -> Dictionary:
	var d: Dictionary = node["data"]
	match node["type"]:
		"start", "label":
			return {"port": 0}

		"end":
			return {"ending": str(d.get("ending_id", ""))}

		"jump":
			var target := g.find_label(str(d.get("label_target", "")))
			if target == "":
				_error("Sprungmarke '%s' nicht gefunden." % d.get("label_target", ""), id)
				return {"stopped": true}
			return {"goto": target}

		"once":
			return {"port": 0 if visit_counts.get(id, 0) <= 1 else 1}

		"sequence":
			for i in int(d.get("steps", 2)):
				var next := g.next_node(id, i)
				if next == "":
					continue
				var r: Dictionary = await _run_flow(g, next, run)
				if r.has("ending") or r.has("stopped"):
					return r
			return {"port": -1}

		"subgraph":
			var sub := _load_subgraph(str(d.get("path", "")), id)
			if sub == null:
				return {"stopped": true}
			for name in sub.variables:
				if not variables.has(name):
					variables[name] = sub.variables[name]["default"]
			var start_id := sub.find_start()
			if start_id == "":
				_error("Subgraph hat keinen Start-Node.", id)
				return {"stopped": true}
			var r: Dictionary = await _run_flow(sub, start_id, run)
			if r.has("stopped"):
				return r
			return {"port": 0}

		"dialogue":
			_sync_steps = 0
			_waiting_for = "advance"
			dialogue_requested.emit(str(d.get("speaker", "")), str(d.get("text", "")), id)
			if _waiting_for == "advance":
				await _advanced
			_waiting_for = ""
			return {"port": 0}

		"choice":
			_sync_steps = 0
			var options: Array = d.get("options", [])
			var limit := float(d.get("time_limit", 0.0))
			var timeout_port := options.size()
			_waiting_for = "choice"
			var choice_state := {"index": -2}
			var on_chosen := func(i: int): choice_state["index"] = i
			_chosen.connect(on_chosen, CONNECT_ONE_SHOT)
			choice_requested.emit(str(d.get("prompt", "")), options.duplicate(), limit, id)
			if limit > 0.0:
				var timer := get_tree().create_timer(limit, false)
				timer.timeout.connect(func():
					if choice_state["index"] == -2 and _waiting_for == "choice" and run == _run_id:
						_waiting_for = ""
						_chosen.emit(timeout_port))
			if choice_state["index"] == -2:
				await _chosen
			_waiting_for = ""
			var index: int = choice_state["index"]
			if index == timeout_port and limit > 0.0:
				choice_timed_out.emit(id)
			return {"port": clampi(index, 0, timeout_port if limit > 0.0 else maxi(0, options.size() - 1))}

		"branch":
			return {"port": 0 if _truthy(evaluate(str(d.get("condition", "")), false, id)) else 1}

		"compare":
			var a = variables.get(str(d.get("variable", "")))
			var b = evaluate(str(d.get("value", "")), null, id)
			return {"port": 0 if _compare(a, str(d.get("compare_op", "==")), b) else 1}

		"all_any":
			var all := str(d.get("mode", "all")) == "all"
			var conditions: Array = d.get("conditions", [])
			var result := all
			for c in conditions:
				var v := _truthy(evaluate(str(c), false, id))
				if all and not v:
					result = false
					break
				if not all and v:
					result = true
					break
			return {"port": 0 if result else 1}

		"switch":
			var value = variables.get(str(d.get("variable", "")))
			var cases: Array = d.get("cases", [])
			for i in cases.size():
				if str(value) == str(cases[i]):
					return {"port": i}
			return {"port": cases.size()}

		"set_var":
			var name := str(d.get("variable", ""))
			if not variables.has(name):
				_error("Variable '%s' existiert nicht." % name, id)
				return {"port": 0}
			var old = variables[name]
			var op := str(d.get("op", "="))
			var new_value = old
			if op == "toggle":
				new_value = not _truthy(old)
			else:
				var v = evaluate(str(d.get("value", "")), null, id)
				match op:
					"=": new_value = v
					"+=": new_value = _arith(old, v, "+")
					"-=": new_value = _arith(old, v, "-")
					"*=": new_value = _arith(old, v, "*")
					"/=": new_value = _arith(old, v, "/")
			set_var(name, new_value)
			return {"port": 0}

		"random":
			var weights: Array = d.get("weights", [])
			var total := 0.0
			for w in weights:
				total += maxf(0.0, float(w))
			if total <= 0.0:
				return {"port": 0}
			var roll := randf() * total
			for i in weights.size():
				roll -= maxf(0.0, float(weights[i]))
				if roll < 0.0:
					return {"port": i}
			return {"port": weights.size() - 1}

		"wait":
			_sync_steps = 0
			await get_tree().create_timer(float(d.get("seconds", 0.0)), false).timeout
			return {"port": 0}

		"countdown":
			_sync_steps = 0
			var seconds := float(d.get("seconds", 0.0))
			var until := str(d.get("until", ""))
			countdown_started.emit(seconds, id)
			var elapsed := 0.0
			var success := false
			while elapsed < seconds:
				if until != "" and _truthy(evaluate(until, false, id)):
					success = true
					break
				await get_tree().process_frame
				if run != _run_id:
					return {"stopped": true}
				if not get_tree().paused:
					elapsed += get_process_delta_time()
			if not success and until != "" and _truthy(evaluate(until, false, id)):
				success = true
			countdown_finished.emit(success, id)
			return {"port": 0 if success else 1}

		"task_start":
			var tid := str(d.get("task_id", ""))
			tasks[tid] = {"description": str(d.get("description", "")), "status": "active"}
			task_started.emit(tid, tasks[tid]["description"])
			_tasks_changed.emit()
			return {"port": 0}

		"task_complete":
			complete_task(str(d.get("task_id", "")), bool(d.get("success", true)))
			return {"port": 0}

		"task_wait":
			_sync_steps = 0
			var ids: Array = d.get("task_ids", [])
			var need_all := str(d.get("mode", "all")) == "all"
			while not _tasks_satisfied(ids, need_all):
				await _tasks_changed
				if run != _run_id:
					return {"stopped": true}
			return {"port": 0}

		"expression":
			var r = evaluate(str(d.get("code", "")), null, id)
			if r is Signal:
				_sync_steps = 0
				await r
			return {"port": 0}

		"call_method":
			var target: Node = context
			var path := str(d.get("node_path", "."))
			if context != null and path != "" and path != ".":
				target = context.get_node_or_null(path)
			var method := str(d.get("method", ""))
			if target == null or not target.has_method(method):
				_error("Methode '%s' an '%s' nicht gefunden." % [method, path], id)
				return {"port": 0}
			var args := []
			for a in d.get("args", []):
				args.append(evaluate(str(a), null, id))
			var r = target.callv(method, args)
			if r is Signal:
				_sync_steps = 0
				await r
			return {"port": 0}

		"emit_signal":
			var payload = evaluate(str(d.get("payload", "")), null, id)
			custom_signal.emit(str(d.get("signal_name", "")), payload)
			return {"port": 0}

	_error("Unbekannter Node-Typ '%s'." % node["type"], id)
	return {"stopped": true}


func _tasks_satisfied(ids: Array, need_all: bool) -> bool:
	if ids.is_empty():
		return true
	for tid in ids:
		var done: bool = tasks.get(str(tid), {}).get("status", "") in ["done", "failed"]
		if need_all and not done:
			return false
		if not need_all and done:
			return true
	return need_all


func _load_subgraph(path: String, node_id: String) -> StoryGraphData:
	if _graph_cache.has(path):
		return _graph_cache[path]
	var resolved := path
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path() and graph_path != "":
		resolved = graph_path.get_base_dir().path_join(path)
	var g := StoryGraphData.load_file(resolved)
	if g == null:
		_error("Subgraph '%s' konnte nicht geladen werden." % path, node_id)
		return null
	_graph_cache[path] = g
	return g


func _truthy(v: Variant) -> bool:
	if v == null:
		return false
	if typeof(v) == TYPE_STRING:
		return v != "" and v.to_lower() not in ["false", "falsch", "0"]
	return bool(v)


func _compare(a: Variant, op: String, b: Variant) -> bool:
	if _is_number(a) and _is_number(b):
		a = float(a)
		b = float(b)
	elif typeof(a) != typeof(b):
		a = str(a)
		b = str(b)
	match op:
		"==": return a == b
		"!=": return a != b
		">": return a > b
		">=": return a >= b
		"<": return a < b
		"<=": return a <= b
	return false


func _arith(a: Variant, b: Variant, op: String) -> Variant:
	if typeof(a) == TYPE_STRING and op == "+":
		return a + str(b)
	if not _is_number(a) or not _is_number(b):
		return a
	match op:
		"+": return a + b
		"-": return a - b
		"*": return a * b
		"/": return a if float(b) == 0.0 else (a / b if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT else float(a) / float(b))
	return a


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func _error(message: String, node_id: String) -> void:
	push_warning("StoryGraph: " + message + (" (Node %s)" % node_id if node_id != "" else ""))
	error_occurred.emit(message, node_id)
