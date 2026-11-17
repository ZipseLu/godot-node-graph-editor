## Macht ein Spielobjekt für Story-Graphen ansprechbar.
##
## Als Kind an das Objekt hängen (z. B. an eine Tür, Lampe, Figur, Kamera, einen Marker)
## und eine eindeutige Story-ID vergeben. Im Graph wählst du das Objekt dann über diese ID,
## statt Node-Pfade zu tippen. Gesteuert wird immer der Eltern-Node.
@icon("res://addons/story_graph/scene/actor_icon.svg")
class_name StoryActor
extends Node

const GROUP := "story_actor"

## Eindeutiger Name, unter dem der Graph dieses Objekt findet, z. B. "tuer_kueche".
@export var story_id := ""
## Optional: anderes Ziel als der Eltern-Node.
@export var target_override: Node


func _enter_tree() -> void:
	add_to_group(GROUP)


## Das Objekt, das der Graph steuert.
func get_target() -> Node:
	if target_override != null:
		return target_override
	return get_parent()


## Sucht ein Objekt mit dieser Story-ID in der laufenden Szene.
static func find(tree: SceneTree, id: String) -> Node:
	for actor in tree.get_nodes_in_group(GROUP):
		if actor is StoryActor and actor.story_id == id:
			return actor.get_target()
	return null
