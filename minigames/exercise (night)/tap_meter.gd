extends MinigameBase

@onready var bar: ProgressBar = $Bar
@onready var label: Label = $Label

var value: float = 0.0
var fill_speed: float = 40.0
var green_min: float = 60.0
var green_max: float = 85.0

func setup(context: Dictionary = {}) -> void:
	value = 0.0
	bar.value = 0
	label.text = "Tap SPACE to fill. Stop in the green!"

func _process(delta: float) -> void:
	value -= fill_speed * 0.3 * delta
	value = clamp(value, 0.0, 100.0)
	bar.value = value

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_select"):
		value += fill_speed * 0.15
		value = clamp(value, 0.0, 100.0)
		bar.value = value

func _on_confirm_pressed() -> void:
	if value >= green_min and value <= green_max:
		_succeed(int(value))
	else:
		_fail(int(value))


func _on_confirm_button_pressed() -> void:
	pass # Replace with function body.
