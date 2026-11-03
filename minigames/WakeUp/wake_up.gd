extends MinigameBase

@export var frame1: Texture2D
@export var frame2: Texture2D

@onready var bed: TextureButton = $Bed
@onready var wake_button: Button = $WakeButton
@onready var frame_timer: Timer = $FrameTimer

var showing_first := true

func _ready() -> void:
	bed.texture_normal = frame1
	frame_timer.timeout.connect(_swap_frame)
	bed.pressed.connect(_wake_up)
	wake_button.pressed.connect(_wake_up)

func _swap_frame() -> void:
	showing_first = !showing_first
	bed.texture_normal = frame1 if showing_first else frame2

func _wake_up() -> void:
	frame_timer.stop()
	finished.emit({"success": true})
