## Meldet der Story ein Spielereignis, ganz ohne Code.
##
## Als Kind an ein Objekt hängen, das ein Signal hat, und Ereignisnamen vergeben. Beispiele:
##   • unter einer Area2D/Area3D: Signal "body_entered", Gruppe "player" → "kueche_betreten"
##   • unter einem Button:         Signal "pressed"                      → "knopf_gedrueckt"
## Im Graph wartet der Node "Auf Ereignis warten" darauf; in Bedingungen geht ereignis("name").
@icon("res://addons/story_graph/scene/trigger_icon.svg")
class_name StoryTrigger
extends Node

const RUNNER_GROUP := "story_graph_runner"

## Name des Ereignisses, das an die Story gemeldet wird.
@export var event_name := ""
## Signal des Eltern-Nodes, das das Ereignis auslöst.
@export var source_signal := "body_entered"
## Nur auslösen, wenn das erste Signal-Argument (z. B. der Körper) in dieser Gruppe ist. Leer = immer.
## Hat das Signal kein Node-Argument (z. B. Button.pressed), wird die Gruppe ignoriert.
@export var required_group := "player"
## Nur beim ersten Mal auslösen.
@export var once := false
@export var enabled := true

var _fired := false


func _ready() -> void:
	var source := get_parent()
	if source == null or not source.has_signal(source_signal):
		push_warning("StoryTrigger '%s': Eltern-Node hat kein Signal '%s'." % [event_name, source_signal])
		return
	source.connect(source_signal, _on_signal)


## Ereignis von Hand auslösen (z. B. aus einer AnimationPlayer-Methodenspur).
func fire() -> void:
	if not enabled or (once and _fired):
		return
	_fired = true
	notify(get_tree(), event_name)


## Meldet ein Ereignis an alle laufenden Story-Graphen.
static func notify(tree: SceneTree, name: String, data: Variant = null) -> void:
	tree.call_group(RUNNER_GROUP, "notify_event", name, data)


func _on_signal(a = null, _b = null, _c = null, _d = null) -> void:
	if required_group != "" and a is Node and not (a as Node).is_in_group(required_group):
		return
	fire()
