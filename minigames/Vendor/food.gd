extends Sprite2D
class_name Food
# One piece of food (kikiam, fishball or squidball).

var kind := ""             # "kikiam", "fishball" or "squidball"
var state := 0             # 0 = raw, 1 = cooked, 2 = burnt
var textures: Array = []   # [raw, cooked, burnt]
var cook_time := 5.0       # seconds until cooked
var burn_time := 5.0       # extra seconds until burnt
var timer := 0.0
var base_scale := Vector2.ONE


# The strainer calls this every frame while it is in the fryer
func cook(delta: float) -> void:
	if state == 2:
		return
	timer += delta
	if state == 0 and timer >= cook_time:
		set_state(1)
	elif state == 1 and timer >= cook_time + burn_time:
		set_state(2)


# Change state and swap the picture
func set_state(new_state: int) -> void:
	state = new_state
	texture = textures[state]
