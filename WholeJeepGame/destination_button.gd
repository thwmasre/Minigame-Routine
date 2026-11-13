class_name DestinationButton
extends TextureButton

signal chosen(button: DestinationButton)

@export var destination_id := "school"
@export var enabled := true
@export_range(0, 2) var how_far := 1
@export_file("*.tscn") var scene_path := ""
@export_enum("use_picker", "day", "dawn", "night") var time_of_day := "use_picker"
@export var ride_scene: PackedScene   # leave empty = use the picker's Ride Scene
@export var free_return := false

func _ready() -> void:
	disabled = not enabled
	pressed.connect(func(): chosen.emit(self))
