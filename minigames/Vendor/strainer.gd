extends Node2D
class_name Strainer
# Holds up to 4 foods (one per Slot marker).

# where the strainer is right now
const HOME := 0       # resting
const LOADING := 1    # at the load spot, picking food
const COOKING := 2    # in the fryer
const CENTER := 3     # in the center, ready for the tongs

var state := HOME
var home_position := Vector2.ZERO
var slot_food: Array = [null, null, null, null]   # which food sits in each slot


func _ready() -> void:
	var body: Sprite2D = $Body
	home_position = to_global(body.transform * body.get_rect().get_center())


# Slide the strainer so the middle of its PICTURE lands on the target
func move_to(target: Vector2, new_state: int, zoom: float = 1.0) -> void:
	state = new_state
	if new_state == LOADING or new_state == CENTER:
		z_index = 20
	else:
		z_index = 0

	var body: Sprite2D = $Body
	var picture_center := body.transform * body.get_rect().get_center()
	var root_target := target - picture_center * zoom

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", root_target, 0.3)
	tw.tween_property(self, "scale", Vector2.ONE * zoom, 0.3)


func is_full() -> bool:
	return not slot_food.has(null)


func add_food(food: Food) -> void:
	var i := slot_food.find(null)
	slot_food[i] = food
	if food.get_parent() == null:
		add_child(food)
	else:
		food.reparent(self)
	food.position = get_node("Slot" + str(i + 1)).position


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


# Food only cooks while the strainer is in the fryer
func _process(delta: float) -> void:
	if state == COOKING:
		for f in get_foods():
			f.cook(delta)
