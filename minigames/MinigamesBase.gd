class_name MinigameBase
extends Control
 
signal finished(success: bool, score: int)
 
func setup(context: Dictionary = {}) -> void:
	pass
 
func _succeed(score: int = 0) -> void:
	finished.emit(true, score)
 
func _fail(score: int = 0) -> void:
	finished.emit(false, score)
