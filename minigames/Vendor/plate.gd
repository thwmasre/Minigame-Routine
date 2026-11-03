extends Node2D
class_name Plate
# A plate for extra food. Foods sit in a grid over the plate picture.

@export var max_foods := 6
@export var columns := 3
@export var spread := 0.7       # how much of the plate picture the foods cover (0.7 = 70%)
@export var food_scale := 0.5   # food looks smaller on the plate

var slot_food: Array = []       # which food sits in each slot


func _ready() -> void:
	slot_food.resize(max_foods)      # one empty slot (null) per food


func is_full() -> bool:
	return not slot_food.has(null)


func add_food(food: Food) -> void:
	var i := slot_food.find(null)
	slot_food[i] = food
	food.reparent(self)
	food.scale = food.base_scale * food_scale
	food.z_index = 0
	food.position = slot_position(i)


func take_food(food: Food) -> void:
	var i := slot_food.find(food)
	if i != -1:
		slot_food[i] = null


func get_foods() -> Array:
	var result := []
	for f in slot_food:
		if f != null:
			result.append(f)
	return result


# Where slot number i is, in the plate's own space
func slot_position(i: int) -> Vector2:
	var body: Sprite2D = $Body
	var rect := body.get_rect()
	var rows := ceili(max_foods / float(columns))
	var col := i % columns
	var row := floori(i / float(columns))
	var x := (col + 0.5) / columns - 0.5
	var y := (row + 0.5) / rows - 0.5
	var local := rect.get_center() + Vector2(x * rect.size.x * spread, y * rect.size.y * spread)
	return body.transform * local
