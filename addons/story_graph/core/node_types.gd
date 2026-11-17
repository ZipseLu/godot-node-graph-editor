## Gemeinsame Node-Definitionen für Editor und Laufzeit.
## Jede Definition beschreibt Kategorie, Ein-/Ausgänge und editierbare Felder.
class_name StoryNodeTypes
extends RefCounted

const CATEGORY_COLORS := {
	"flow": Color("#5b8def"),
	"story": Color("#e0a33a"),
	"logic": Color("#9b6bdf"),
	"values": Color("#3fb68b"),
	"time": Color("#e06a5a"),
	"tasks": Color("#d4c24a"),
	"script": Color("#7f8c99"),
}

## outputs: Liste benannter Ablauf-Ausgänge. "*" = dynamisch (z. B. Entscheidungsoptionen).
const TYPES := {
	"start":        {"title": "Start",              "category": "flow",   "inputs": 0, "outputs": ["weiter"], "fields": {}},
	"end":          {"title": "Ende",               "category": "flow",   "inputs": 1, "outputs": [], "fields": {"ending_id": ""}},
	"label":        {"title": "Sprungmarke",        "category": "flow",   "inputs": 1, "outputs": ["weiter"], "fields": {"name": ""}},
	"jump":         {"title": "Springe zu",         "category": "flow",   "inputs": 1, "outputs": [], "fields": {"target": ""}},
	"subgraph":     {"title": "Subgraph",           "category": "flow",   "inputs": 1, "outputs": ["weiter"], "fields": {"path": ""}},
	"dialogue":     {"title": "Dialog",             "category": "story",  "inputs": 1, "outputs": ["weiter"], "fields": {"speaker": "", "text": ""}},
	"choice":       {"title": "Entscheidung",       "category": "story",  "inputs": 1, "outputs": ["*"], "fields": {"prompt": "", "options": ["Option A", "Option B"], "time_limit": 0.0, "timeout_option": -1}},
	"branch":       {"title": "Bedingung",          "category": "logic",  "inputs": 1, "outputs": ["wahr", "falsch"], "fields": {"condition": ""}},
	"switch":       {"title": "Switch",             "category": "logic",  "inputs": 1, "outputs": ["*"], "fields": {"variable": "", "cases": ["a", "b"]}},
	"set_var":      {"title": "Variable setzen",    "category": "values", "inputs": 1, "outputs": ["weiter"], "fields": {"variable": "", "op": "=", "value": ""}},
	"random":       {"title": "Zufall",             "category": "values", "inputs": 1, "outputs": ["*"], "fields": {"weights": [1, 1]}},
	"wait":         {"title": "Warten",             "category": "time",   "inputs": 1, "outputs": ["weiter"], "fields": {"seconds": 1.0}},
	"countdown":    {"title": "Countdown",          "category": "time",   "inputs": 1, "outputs": ["geschafft", "abgelaufen"], "fields": {"seconds": 10.0, "until": ""}},
	"task_start":   {"title": "Task starten",       "category": "tasks",  "inputs": 1, "outputs": ["weiter"], "fields": {"task_id": "", "description": ""}},
	"task_complete":{"title": "Task abschließen",   "category": "tasks",  "inputs": 1, "outputs": ["weiter"], "fields": {"task_id": "", "success": true}},
	"task_wait":    {"title": "Auf Tasks warten",   "category": "tasks",  "inputs": 1, "outputs": ["weiter"], "fields": {"task_ids": [], "mode": "all"}},
	"expression":   {"title": "Ausdruck ausführen", "category": "script", "inputs": 1, "outputs": ["weiter"], "fields": {"code": ""}},
	"call_method":  {"title": "Methode aufrufen",   "category": "script", "inputs": 1, "outputs": ["weiter"], "fields": {"target": "", "method": "", "args": []}},
	"emit_signal":  {"title": "Signal senden",      "category": "script", "inputs": 1, "outputs": ["weiter"], "fields": {"name": "", "payload": {}}},
}

static func get_def(type: String) -> Dictionary:
	return TYPES.get(type, {})
