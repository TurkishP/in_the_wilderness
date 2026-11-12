extends Node3D
## A spot in the world the player can use with E: water jars, a cage, the pillar of cloud.

var label := ""
var interact_radius := 3.0
var callback := Callable()
var enabled := true


func _ready() -> void:
	add_to_group("interactable")


func prompt_text() -> String:
	return label if enabled else ""


func interact() -> void:
	if enabled and callback.is_valid():
		callback.call(self)
