extends Node
 
signal minigame_finished(minigame_name: String, success: bool, score: int)
 
var minigame_layer: CanvasLayer
var current_minigame: MinigameBase = null
 
var minigame_scenes: Dictionary = {
	"exercise": preload("res://MiniG/minigames/exercise/Exercise.tscn"),
	"cleanroom": preload("res://MiniG/minigames/cleanroom/CleanRoom.tscn"),
	"Scrub": preload("res://MiniG/minigames/Scrub/ScrubGame.tscn"),
	"JeepRide": preload("res://MiniG/minigames/Jeep/JeepRide.tscn"),
	"JeepRide2": preload("res://MiniG/minigames/Jeep2home/JeepRide2.tscn")
}
 
func _ready() -> void:
	minigame_layer = CanvasLayer.new()
	minigame_layer.layer = 100
	add_child(minigame_layer)
 
func start_minigame(minigame_name: String, context: Dictionary = {}) -> void:
	if current_minigame != null:
		return
 
	if not minigame_scenes.has(minigame_name):
		push_error("No minigame found with the name: " + minigame_name)
		return
 
	var minigame_scene = minigame_scenes[minigame_name]
	current_minigame = minigame_scene.instantiate()
	minigame_layer.add_child(current_minigame)
 
	current_minigame.finished.connect(_on_minigame_finished.bind(minigame_name))
	current_minigame.setup(context)
	
 
func _on_minigame_finished(success: bool, score: int, minigame_name: String) -> void:
	minigame_finished.emit(minigame_name, success, score)
	current_minigame.queue_free()
	current_minigame = null
