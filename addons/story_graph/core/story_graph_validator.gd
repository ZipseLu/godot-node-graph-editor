## Prüft einen Graph auf typische Fehler, bevor er im Spiel landet.
## Liefert eine Liste von {"severity": "error"|"warning", "node_id": String, "message": String}.
class_name StoryGraphValidator
extends RefCounted


static func validate(g: StoryGraphData) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var starts := 0
	var incoming := {}
	for c in g.connections:
		incoming[c["to"]] = true

	var var_names := PackedStringArray(g.variables.keys())
	var_names.append_array(["ctx", "runner"])
	var labels := g.label_names()
	var seen_labels := {}

	for id in g.nodes:
		var n: Dictionary = g.nodes[id]
		var type: String = n["type"]
		var data: Dictionary = n["data"]
		if not StoryNodeTypes.has_type(type):
			issues.append(_issue("error", id, "Unbekannter Node-Typ '%s'." % type))
			continue
		var def := StoryNodeTypes.get_def(type)
		if type == "start":
			starts += 1
		elif def.get("has_input", true) and not incoming.has(id):
			issues.append(_issue("warning", id, "'%s' wird nie erreicht (kein Eingang verbunden)." % def["title"]))

		var outputs := StoryNodeTypes.get_outputs(type, data)
		for port in outputs.size():
			if g.next_node(id, port) == "" and type != "sequence":
				issues.append(_issue("warning", id, "Ausgang '%s' von '%s' ist nicht verbunden; die Geschichte stoppt dort." % [outputs[port], def["title"]]))

		# Felder prüfen
		for field in data:
			var info := StoryNodeTypes.get_field_info(field)
			var kind: String = info.get("kind", "string")
			if kind == "variable":
				var v := str(data[field])
				if v == "":
					issues.append(_issue("error", id, "'%s': keine Variable gewählt." % def["title"]))
				elif not g.variables.has(v):
					issues.append(_issue("error", id, "'%s': Variable '%s' existiert nicht." % [def["title"], v]))
			elif kind == "expression":
				var required: bool = field in ["condition", "until"] and type in ["branch"]
				_check_expression(issues, id, def["title"], str(data[field]), var_names, required or (field == "value" and data.get("op", "") != "toggle" and type in ["set_var", "compare"]))
			elif kind == "string_list" and info.get("expression", false):
				for e in data[field]:
					_check_expression(issues, id, def["title"], str(e), var_names, true)
			elif kind == "code":
				_check_expression(issues, id, def["title"], str(data[field]), var_names, false)

		match type:
			"label":
				var lname := str(data.get("name", ""))
				if lname == "":
					issues.append(_issue("error", id, "Sprungmarke ohne Namen."))
				elif seen_labels.has(lname):
					issues.append(_issue("error", id, "Sprungmarke '%s' gibt es mehrfach." % lname))
				seen_labels[lname] = true
			"jump":
				var target := str(data.get("label_target", ""))
				if not target in labels:
					issues.append(_issue("error", id, "Sprungziel '%s' existiert nicht." % target))
			"choice":
				if data.get("options", []).is_empty():
					issues.append(_issue("error", id, "Entscheidung ohne Optionen."))
			"task_start", "task_complete":
				if str(data.get("task_id", "")) == "":
					issues.append(_issue("error", id, "Task-ID fehlt."))
			"subgraph":
				var p := str(data.get("path", ""))
				if p == "":
					issues.append(_issue("error", id, "Subgraph ohne Datei."))
			"call_method":
				if str(data.get("method", "")) == "":
					issues.append(_issue("error", id, "Methodenname fehlt."))
			"emit_signal":
				if str(data.get("signal_name", "")) == "":
					issues.append(_issue("error", id, "Signalname fehlt."))

	if starts == 0:
		issues.push_front(_issue("error", "", "Es gibt keinen Start-Node."))
	elif starts > 1:
		issues.push_front(_issue("error", "", "Es gibt %d Start-Nodes; erlaubt ist genau einer." % starts))
	for name in g.variables:
		if not StoryGraphData.is_valid_variable_name(name):
			issues.append(_issue("error", "", "Variablenname '%s' ist ungültig (nur Buchstaben, Ziffern, _; nicht mit Ziffer beginnen)." % name))
	return issues


static func _check_expression(issues: Array[Dictionary], id: String, title: String, text: String, var_names: PackedStringArray, required: bool) -> void:
	if text.strip_edges() == "":
		if required:
			issues.append(_issue("error", id, "'%s': Ausdruck ist leer." % title))
		return
	var expr := Expression.new()
	if expr.parse(text, var_names) != OK:
		issues.append(_issue("error", id, "'%s': Ausdruck '%s' ist ungültig: %s" % [title, text, expr.get_error_text()]))


static func _issue(severity: String, node_id: String, message: String) -> Dictionary:
	return {"severity": severity, "node_id": node_id, "message": message}
