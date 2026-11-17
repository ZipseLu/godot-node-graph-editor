## Gemeinsame Node-Definitionen für Editor und Laufzeit.
## Jede Definition beschreibt Kategorie, Ein-/Ausgänge und editierbare Felder.
## Editor (Inspector, Palette) und Laufzeit (StoryGraphRunner) lesen beide nur diese Datei,
## damit sie nie auseinanderlaufen.
class_name StoryNodeTypes
extends RefCounted

const FORMAT_NAME := "story_graph"
const FORMAT_VERSION := 1
const FILE_EXTENSION := "storygraph"

const CATEGORIES := {
	"flow":   {"title": "Ablauf",    "color": Color("#5b8def")},
	"story":  {"title": "Story",     "color": Color("#e0a33a")},
	"logic":  {"title": "Logik",     "color": Color("#9b6bdf")},
	"values": {"title": "Werte",     "color": Color("#3fb68b")},
	"time":   {"title": "Zeit",      "color": Color("#e06a5a")},
	"tasks":  {"title": "Tasks",     "color": Color("#c9b43c")},
	"scene":  {"title": "Szene",     "color": Color("#d0679b")},
	"script": {"title": "Skript",    "color": Color("#8a96a3")},
}

## Feld-Arten, die der Inspector kennt:
## string, multiline, expression, code, float, int, bool, enum, variable,
## label_ref, string_list, int_list, file
const FIELDS := {
	"speaker":     {"label": "Sprecher", "kind": "string", "placeholder": "z. B. Kara"},
	"text":        {"label": "Text", "kind": "multiline", "placeholder": "Was gesagt wird …"},
	"prompt":      {"label": "Frage / Situation", "kind": "string", "placeholder": "optional"},
	"options":     {"label": "Optionen", "kind": "string_list", "item_default": "Neue Option"},
	"time_limit":  {"label": "Zeitlimit in Sekunden (0 = keins)", "kind": "float", "min": 0.0, "max": 600.0, "step": 0.5},
	"condition":   {"label": "Bedingung", "kind": "expression", "placeholder": "z. B. vertrauen >= 3 and not alarm"},
	"conditions":  {"label": "Bedingungen", "kind": "string_list", "item_default": "true", "expression": true},
	"mode":        {"label": "Verknüpfung", "kind": "enum", "options": [["all", "UND (alle müssen stimmen)"], ["any", "ODER (eine reicht)"]]},
	"variable":    {"label": "Variable", "kind": "variable"},
	"compare_op":  {"label": "Vergleich", "kind": "enum", "options": [["==", "ist gleich"], ["!=", "ist ungleich"], [">", "größer als"], [">=", "größer oder gleich"], ["<", "kleiner als"], ["<=", "kleiner oder gleich"]]},
	"op":          {"label": "Aktion", "kind": "enum", "options": [["=", "setzen auf"], ["+=", "erhöhen um"], ["-=", "verringern um"], ["*=", "multiplizieren mit"], ["/=", "teilen durch"], ["toggle", "umschalten (wahr/falsch)"]]},
	"value":       {"label": "Wert", "kind": "expression", "placeholder": "z. B. 1, true, \"Text\" oder vertrauen + 1"},
	"cases":       {"label": "Fälle", "kind": "string_list", "item_default": "wert"},
	"weights":     {"label": "Gewichtungen", "kind": "int_list", "item_default": 1},
	"seconds":     {"label": "Sekunden", "kind": "float", "min": 0.0, "max": 3600.0, "step": 0.1},
	"until":       {"label": "Geschafft, sobald", "kind": "expression", "placeholder": "z. B. tuer_offen"},
	"name":        {"label": "Name", "kind": "string"},
	"target":      {"label": "Ziel", "kind": "string"},
	"label_target":{"label": "Ziel-Sprungmarke", "kind": "label_ref"},
	"path":        {"label": "Graph-Datei", "kind": "file", "placeholder": "res://story/kapitel_2.storygraph", "filters": ["*.storygraph ; Story Graph"]},
	"ending_id":   {"label": "Enden-ID", "kind": "string", "placeholder": "z. B. flucht_gelungen"},
	"task_id":     {"label": "Task-ID", "kind": "string", "placeholder": "z. B. finde_schluessel"},
	"task_ids":    {"label": "Task-IDs", "kind": "string_list", "item_default": "task"},
	"description": {"label": "Beschreibung", "kind": "string", "placeholder": "Wird dem Spieler angezeigt"},
	"success":     {"label": "Erfolgreich", "kind": "bool"},
	"code":        {"label": "Ausdruck", "kind": "code", "placeholder": "z. B. ctx.spiele_sound(\"tuer\")"},
	"node_path":   {"label": "Ziel-Node (relativ zum Kontext)", "kind": "string", "placeholder": "z. B. Player oder ."},
	"method":      {"label": "Methode", "kind": "string", "placeholder": "z. B. play_animation"},
	"args":        {"label": "Argumente (Ausdrücke)", "kind": "string_list", "item_default": "\"\"", "expression": true},
	"signal_name": {"label": "Signalname", "kind": "string", "placeholder": "z. B. kamera_wechsel"},
	"payload":     {"label": "Daten (Ausdruck)", "kind": "expression", "placeholder": "z. B. {\"kamera\": 2}"},
	"steps":       {"label": "Anzahl Schritte", "kind": "int", "min": 2, "max": 16, "step": 1},
	"actor":       {"label": "Objekt (Story-ID)", "kind": "actor", "placeholder": "z. B. tuer_kueche"},
	"to_actor":    {"label": "Ziel-Objekt (z. B. ein Marker)", "kind": "actor", "placeholder": "z. B. punkt_fenster"},
	"animation":   {"label": "Animation", "kind": "string", "placeholder": "z. B. oeffnen"},
	"wait_done":   {"label": "Warten, bis fertig", "kind": "bool"},
	"visible":     {"label": "Sichtbar", "kind": "bool"},
	"property":    {"label": "Eigenschaft", "kind": "string", "placeholder": "z. B. modulate, light_energy, position:x"},
	"duration":    {"label": "Dauer in Sekunden", "kind": "float", "min": 0.0, "max": 600.0, "step": 0.1},
	"sound":       {"label": "Sound-Datei", "kind": "file", "placeholder": "res://sounds/tuer.ogg", "filters": ["*.ogg, *.wav, *.mp3 ; Audio"]},
	"volume_db":   {"label": "Lautstärke (dB)", "kind": "float", "min": -60.0, "max": 24.0, "step": 1.0},
	"scene_path":  {"label": "Szene", "kind": "file", "placeholder": "res://levels/kapitel_2.tscn", "filters": ["*.tscn, *.scn ; Szene"]},
	"event":       {"label": "Ereignis", "kind": "event", "placeholder": "z. B. kueche_betreten"},
	"timeout":     {"label": "Zeitlimit in Sekunden (0 = keins)", "kind": "float", "min": 0.0, "max": 3600.0, "step": 0.5},
	"note":        {"label": "Notiz", "kind": "multiline", "placeholder": "Notiz für dein Team (wird nicht ausgeführt)"},
}

## outputs: feste Ausgangsnamen. Dynamische Ausgänge berechnet get_outputs().
## summary: Feld, das als Vorschau im Node angezeigt wird.
const TYPES := {
	"start":        {"title": "Start", "category": "flow", "has_input": false, "outputs": ["weiter"],
		"fields": {}, "help": "Hier beginnt der Graph. Jeder Graph braucht genau einen Start."},
	"end":          {"title": "Ende", "category": "flow", "has_input": true, "outputs": [],
		"fields": {"ending_id": ""}, "summary": "ending_id",
		"help": "Beendet den Graph. Die Enden-ID sagt deinem Spiel, welches Ende erreicht wurde. In einem Subgraph geht es danach im übergeordneten Graph weiter."},
	"sequence":     {"title": "Sequenz", "category": "flow", "has_input": true, "outputs": [],
		"fields": {"steps": 2},
		"help": "Führt die Ausgänge nacheinander aus. Ein Zweig endet, sobald ein Ausgang nicht verbunden ist; dann folgt der nächste Zweig."},
	"label":        {"title": "Sprungmarke", "category": "flow", "has_input": true, "outputs": ["weiter"],
		"fields": {"name": "marke"}, "summary": "name",
		"help": "Ein benannter Punkt, zu dem 'Springe zu' springen kann. Hält große Graphen übersichtlich."},
	"jump":         {"title": "Springe zu", "category": "flow", "has_input": true, "outputs": [],
		"fields": {"label_target": ""}, "summary": "label_target",
		"help": "Springt zur Sprungmarke mit diesem Namen."},
	"subgraph":     {"title": "Subgraph", "category": "flow", "has_input": true, "outputs": ["weiter"],
		"fields": {"path": ""}, "summary": "path",
		"help": "Führt einen anderen Graph aus (z. B. eine Szene) und macht danach hier weiter. Variablen werden geteilt."},
	"once":         {"title": "Einmalig", "category": "flow", "has_input": true, "outputs": ["erstes Mal", "danach"],
		"fields": {},
		"help": "Beim ersten Durchlauf geht es oben weiter, bei jedem weiteren Mal unten."},
	"dialogue":     {"title": "Dialog", "category": "story", "has_input": true, "outputs": ["weiter"],
		"fields": {"speaker": "", "text": ""}, "summary": "text",
		"help": "Zeigt eine Dialogzeile. Dein Spiel ruft advance() auf, wenn es weitergehen soll."},
	"choice":       {"title": "Entscheidung", "category": "story", "has_input": true, "outputs": [],
		"fields": {"prompt": "", "options": ["Option A", "Option B"], "time_limit": 0.0}, "summary": "prompt",
		"help": "Der Spieler wählt eine Option. Mit Zeitlimit entsteht ein zusätzlicher Ausgang 'Zeit abgelaufen'."},
	"branch":       {"title": "Bedingung", "category": "logic", "has_input": true, "outputs": ["wahr", "falsch"],
		"fields": {"condition": ""}, "summary": "condition",
		"help": "Prüft einen Ausdruck. Erlaubt: Variablennamen, Zahlen, and, or, not, ==, !=, <, >, +, - …"},
	"compare":      {"title": "Vergleich", "category": "logic", "has_input": true, "outputs": ["wahr", "falsch"],
		"fields": {"variable": "", "compare_op": "==", "value": ""},
		"help": "Vergleicht eine Variable mit einem Wert, ganz ohne Code."},
	"all_any":      {"title": "Mehrere Bedingungen", "category": "logic", "has_input": true, "outputs": ["wahr", "falsch"],
		"fields": {"mode": "all", "conditions": ["true"]},
		"help": "UND: alle Bedingungen müssen stimmen. ODER: eine reicht. Für NICHT schreibe 'not' vor eine Bedingung."},
	"switch":       {"title": "Switch", "category": "logic", "has_input": true, "outputs": [],
		"fields": {"variable": "", "cases": ["a", "b"]},
		"help": "Verzweigt je nach Wert einer Variable. Passt kein Fall, geht es bei 'sonst' weiter."},
	"set_var":      {"title": "Variable ändern", "category": "values", "has_input": true, "outputs": ["weiter"],
		"fields": {"variable": "", "op": "=", "value": ""},
		"help": "Setzt, erhöht, verringert oder schaltet eine Variable um."},
	"random":       {"title": "Zufall", "category": "values", "has_input": true, "outputs": [],
		"fields": {"weights": [1, 1]},
		"help": "Wählt zufällig einen Ausgang. Höhere Gewichtung = wahrscheinlicher."},
	"wait":         {"title": "Warten", "category": "time", "has_input": true, "outputs": ["weiter"],
		"fields": {"seconds": 1.0}, "summary": "seconds",
		"help": "Wartet die angegebene Zeit. Pausiert das Spiel, pausiert auch der Timer."},
	"countdown":    {"title": "Countdown", "category": "time", "has_input": true, "outputs": ["geschafft", "abgelaufen"],
		"fields": {"seconds": 10.0, "until": ""}, "summary": "until",
		"help": "Läuft ab, bis die Bedingung erfüllt ist ('geschafft') oder die Zeit vorbei ist ('abgelaufen'). Ideal für Druck-Situationen."},
	"task_start":   {"title": "Task starten", "category": "tasks", "has_input": true, "outputs": ["weiter"],
		"fields": {"task_id": "", "description": ""}, "summary": "description",
		"help": "Startet eine Aufgabe/ein Ziel. Dein Spiel kann sie mit complete_task() abschließen."},
	"task_complete":{"title": "Task abschließen", "category": "tasks", "has_input": true, "outputs": ["weiter"],
		"fields": {"task_id": "", "success": true}, "summary": "task_id",
		"help": "Schließt eine Aufgabe als erfolgreich oder gescheitert ab."},
	"task_wait":    {"title": "Auf Tasks warten", "category": "tasks", "has_input": true, "outputs": ["weiter"],
		"fields": {"task_ids": ["task"], "mode": "all"},
		"help": "Wartet, bis alle (UND) oder eine (ODER) der Aufgaben abgeschlossen sind."},
	"wait_event":   {"title": "Auf Ereignis warten", "category": "scene", "has_input": true, "outputs": [],
		"fields": {"event": "", "timeout": 0.0}, "summary": "event",
		"help": "Wartet, bis das Spiel ein Ereignis meldet, z. B. ein StoryTrigger, wenn der Spieler eine Zone betritt. Mit Zeitlimit gibt es einen Ausgang 'Zeit abgelaufen'. Schon vorher eingetretene Ereignisse zählen nicht; dafür gibt es ereignis(\"name\") in Bedingungen."},
	"actor_animation": {"title": "Animation abspielen", "category": "scene", "has_input": true, "outputs": ["weiter"],
		"fields": {"actor": "", "animation": "", "wait_done": true},
		"help": "Spielt eine Animation am Objekt ab (AnimationPlayer im Objekt oder AnimatedSprite)."},
	"actor_visibility": {"title": "Zeigen / Verstecken", "category": "scene", "has_input": true, "outputs": ["weiter"],
		"fields": {"actor": "", "visible": true},
		"help": "Macht ein Objekt sichtbar oder unsichtbar."},
	"actor_property": {"title": "Eigenschaft setzen", "category": "scene", "has_input": true, "outputs": ["weiter"],
		"fields": {"actor": "", "property": "", "value": "", "duration": 0.0},
		"help": "Setzt eine Eigenschaft des Objekts, z. B. modulate = Color.RED oder light_energy = 0. Mit Dauer > 0 wird weich übergeblendet."},
	"actor_move":   {"title": "Objekt bewegen", "category": "scene", "has_input": true, "outputs": ["weiter"],
		"fields": {"actor": "", "to_actor": "", "duration": 1.0, "wait_done": true},
		"help": "Bewegt ein Objekt zur Position eines anderen Objekts (am besten ein Marker2D/Marker3D mit StoryActor)."},
	"actor_call":   {"title": "Objekt-Methode aufrufen", "category": "scene", "has_input": true, "outputs": ["weiter"],
		"fields": {"actor": "", "method": "", "args": []},
		"help": "Ruft eine Methode am Objekt auf, z. B. open() an einer Tür. Gibt sie ein Signal zurück, wird gewartet."},
	"play_sound":   {"title": "Sound abspielen", "category": "scene", "has_input": true, "outputs": ["weiter"],
		"fields": {"sound": "", "volume_db": 0.0, "wait_done": false}, "summary": "sound",
		"help": "Spielt eine Audiodatei ab."},
	"camera":       {"title": "Kamera wechseln", "category": "scene", "has_input": true, "outputs": ["weiter"],
		"fields": {"actor": ""}, "summary": "actor",
		"help": "Macht die Kamera (Camera2D/Camera3D mit StoryActor) zur aktiven Kamera."},
	"change_scene": {"title": "Szene wechseln", "category": "scene", "has_input": true, "outputs": [],
		"fields": {"scene_path": ""}, "summary": "scene_path",
		"help": "Lädt eine andere Szene. Der Graph endet hier; die neue Szene startet ihren eigenen Graph."},
	"expression":   {"title": "Ausdruck ausführen", "category": "script", "has_input": true, "outputs": ["weiter"],
		"fields": {"code": ""}, "summary": "code",
		"help": "Führt einen GDScript-Ausdruck aus. 'ctx' ist der Kontext-Node deines Spiels, 'runner' der StoryGraphRunner."},
	"call_method":  {"title": "Methode aufrufen", "category": "script", "has_input": true, "outputs": ["weiter"],
		"fields": {"node_path": ".", "method": "", "args": []}, "summary": "method",
		"help": "Ruft eine Methode an einem Node deines Spiels auf. Gibt sie ein Signal/await zurück, wird gewartet."},
	"emit_signal":  {"title": "Signal senden", "category": "script", "has_input": true, "outputs": ["weiter"],
		"fields": {"signal_name": "", "payload": ""}, "summary": "signal_name",
		"help": "Sendet das Signal custom_signal(name, daten) des Runners. Praktisch für Kamera, Sound, Animationen."},
}

static func has_type(type: String) -> bool:
	return TYPES.has(type)

static func get_def(type: String) -> Dictionary:
	return TYPES.get(type, {})

static func get_field_info(field: String) -> Dictionary:
	return FIELDS.get(field, {"label": field.capitalize(), "kind": "string"})

static func category_color(category: String) -> Color:
	return CATEGORIES.get(category, {}).get("color", Color.GRAY)

## Neue, vollständige Felddaten für einen Node-Typ (tiefe Kopie der Vorgaben).
static func default_data(type: String) -> Dictionary:
	return get_def(type).get("fields", {}).duplicate(true)

## Ergänzt fehlende Felder (z. B. bei älteren Dateien) mit Vorgabewerten.
static func normalize_data(type: String, data: Dictionary) -> Dictionary:
	var result := default_data(type)
	for key in data:
		result[key] = data[key]
	return result

## Liefert die Namen der Ablauf-Ausgänge. Port-Index = Position in dieser Liste.
static func get_outputs(type: String, data: Dictionary) -> Array[String]:
	var outputs: Array[String] = []
	match type:
		"choice":
			for option in data.get("options", []):
				outputs.append(str(option))
			if float(data.get("time_limit", 0.0)) > 0.0:
				outputs.append("⏱ Zeit abgelaufen")
		"switch":
			for c in data.get("cases", []):
				outputs.append("= " + str(c))
			outputs.append("sonst")
		"random":
			var weights: Array = data.get("weights", [])
			var total := 0.0
			for w in weights:
				total += maxf(0.0, float(w))
			for i in weights.size():
				var pct := 0.0 if total <= 0.0 else maxf(0.0, float(weights[i])) / total * 100.0
				outputs.append("%d %%" % roundi(pct))
		"wait_event":
			outputs.append("eingetreten")
			if float(data.get("timeout", 0.0)) > 0.0:
				outputs.append("⏱ Zeit abgelaufen")
		"sequence":
			for i in int(data.get("steps", 2)):
				outputs.append("Schritt %d" % (i + 1))
		_:
			for o in get_def(type).get("outputs", []):
				outputs.append(o)
	return outputs

## Typen einer Kategorie in Definitionsreihenfolge.
static func types_in_category(category: String) -> Array[String]:
	var result: Array[String] = []
	for type in TYPES:
		if TYPES[type]["category"] == category:
			result.append(type)
	return result

## Vorschautext eines Nodes für die Anzeige im Graph.
static func summary_text(type: String, data: Dictionary) -> String:
	match type:
		"dialogue":
			var speaker := str(data.get("speaker", ""))
			var text := str(data.get("text", ""))
			return (speaker + ": " if speaker != "" else "") + text
		"compare":
			return "%s %s %s" % [data.get("variable", "?"), data.get("compare_op", "=="), data.get("value", "")]
		"set_var":
			if data.get("op", "=") == "toggle":
				return "%s umschalten" % data.get("variable", "?")
			return "%s %s %s" % [data.get("variable", "?"), data.get("op", "="), data.get("value", "")]
		"all_any":
			var joiner := " UND " if data.get("mode", "all") == "all" else " ODER "
			return joiner.join(PackedStringArray(data.get("conditions", [])))
		"switch":
			return "nach " + str(data.get("variable", "?"))
		"wait":
			return "%s s" % str(data.get("seconds", 0))
		"countdown":
			var until := str(data.get("until", ""))
			return "%s s%s" % [str(data.get("seconds", 0)), (", bis " + until) if until != "" else ""]
		"task_wait":
			var joiner := " UND " if data.get("mode", "all") == "all" else " ODER "
			return joiner.join(PackedStringArray(data.get("task_ids", [])))
		"choice":
			var prompt := str(data.get("prompt", ""))
			var limit := float(data.get("time_limit", 0.0))
			return prompt + ("  ⏱ %s s" % str(limit) if limit > 0.0 else "")
		"call_method":
			return "%s.%s()" % [data.get("node_path", "."), data.get("method", "")]
		"wait_event":
			var t := float(data.get("timeout", 0.0))
			return str(data.get("event", "")) + ("  ⏱ %s s" % str(t) if t > 0.0 else "")
		"actor_animation":
			return "%s ▶ %s" % [data.get("actor", "?"), data.get("animation", "")]
		"actor_visibility":
			return "%s %s" % [data.get("actor", "?"), "zeigen" if data.get("visible", true) else "verstecken"]
		"actor_property":
			return "%s.%s = %s" % [data.get("actor", "?"), data.get("property", ""), data.get("value", "")]
		"actor_move":
			return "%s → %s (%s s)" % [data.get("actor", "?"), data.get("to_actor", "?"), str(data.get("duration", 0))]
		"actor_call":
			return "%s.%s()" % [data.get("actor", "?"), data.get("method", "")]
		"camera":
			return "→ " + str(data.get("actor", ""))
	var def := get_def(type)
	if def.has("summary"):
		return str(data.get(def["summary"], ""))
	return ""
