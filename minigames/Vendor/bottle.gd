extends Node2D
class_name Bottle
# Empty bottle. fill() shows the bottle_coconut picture on top.

var filled := false


func _ready() -> void:
	$Filled.visible = false


func fill() -> void:
	filled = true
	$Filled.visible = true
