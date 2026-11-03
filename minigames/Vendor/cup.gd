extends Node2D
class_name Cup
# A cup that holds food and one sauce.

@export var max_foods := 4
@export var food_scale := 0.6     # food looks smaller inside the cup
# where each food sits, as a fraction of the cup width, from the middle of the cup picture
@export var slot_offsets: Array[Vector2] = [Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(-0.2, 0.2), Vector2(0.2, 0.2)]

var foods: Array = []
var sauce := "plain"             # "plain", "sweet" or "spicy"


func is_full() -> bool:
	return foods.size() >= max_foods


# The middle of the cup picture (Body may not sit on the center of the Cup node)
func picture_center() -> Vector2:
	var body: Sprite2D = $Body
	return body.transform * body.get_rect().get_center()


func cup_width() -> float:
	var body: Sprite2D = $Body
	return body.get_rect().size.x * body.scale.x


func add_food(food: Food) -> void:
	food.reparent(self)
	food.position = picture_center() + slot_offsets[foods.size()] * cup_width()
	food.scale = food.scale * food_scale
	food.z_index = 0
	foods.append(food)


# Puts a round sauce picture on top of the cup, sized to fit it
func remove_food(food: Food) -> void:
	foods.erase(food)
	
func add_sauce(kind: String, tex: Texture2D) -> void:
	if sauce != "plain":
		return
	sauce = kind
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2.ONE * (cup_width() * 0.9 / tex.get_width())
	s.position = picture_center()
	s.modulate.a = 0.9
	s.z_index = 1
	add_child(s)
