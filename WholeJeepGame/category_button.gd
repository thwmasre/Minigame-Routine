class_name CategoryButton
extends TextureButton

signal chosen(button: CategoryButton)

@export var category_id := "park"
@export var enabled := true                 # untick to turn this category off
@export var options: Control                # drag the node holding this category's 3 buttons

func _ready() -> void:
	disabled = not enabled
	pressed.connect(func(): chosen.emit(self))
	
