extends MinigameBase

const TIERS := {
	"poor": {"rank": 0, "speed": 200.0, "weight": 50, "energy": [0, 0], "happy": [0, 1]},
	"okay": {"rank": 1, "speed": 290.0, "weight": 28, "energy": [0, 1], "happy": [1, 2]},
	"rich": {"rank": 2, "speed": 400.0, "weight": 15, "energy": [1, 2], "happy": [2, 2]},
	"rare": {"rank": 3, "speed": 560.0, "weight": 7, "energy": [2, 2], "happy": [3, 3]},
}

@export var frame1: Texture2D
@export var frame2: Texture2D
@export var frain1: Texture2D
@export var frain2: Texture2D
@export var poor_textures: Array[Texture2D]
@export var okay_textures: Array[Texture2D]
@export var rich_textures: Array[Texture2D]
@export var rare_textures: Array[Texture2D]
@export var jeep_scale := 0.5
@export var zone_width := 300.0
@export var time_limit := 120.0

@onready var spawn_point: Marker2D = $Road/SpawnPoint
@onready var background: TextureRect = $Background
@onready var road: Control = $Road
@onready var para_btn: Button = $ParaPoButton
@onready var timer_label: Label = $TimerLabel
@onready var spawn_timer: Timer = $SpawnTimer
@onready var popup: Panel = $Popup
@onready var stats_label: Label = $Popup/StatsLabel
@onready var confirm_btn: Button = $Popup/ConfirmButton
@onready var pass_btn: Button = $Popup/PassButton

var jeeps: Array[TextureRect] = []
var selected: TextureRect = null
var selecting := false
var chances := 2
var time_left := 0.0
var idle_frames: Array[Texture2D] = []
var idle_index := 0
var idle_timer: Timer

func _ready() -> void:
	time_left = time_limit
	var rainy := frain1 != null and randf() < 0.25
	if rainy:
		idle_frames = [frain1, frain2]
	else:
		idle_frames = [frame1, frame2]
	background.texture = idle_frames[0]
	idle_timer = Timer.new()
	idle_timer.wait_time = 0.5
	idle_timer.timeout.connect(_swap_idle)
	add_child(idle_timer)
	idle_timer.start()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_spawn_jeep)
	para_btn.pressed.connect(_on_para_po)
	confirm_btn.pressed.connect(_on_confirm)
	pass_btn.pressed.connect(_on_pass)
	para_btn.hide()
	popup.hide()
	_spawn_jeep()

func _swap_idle() -> void:
	idle_index = 1 - idle_index
	background.texture = idle_frames[idle_index]

func _process(delta: float) -> void:
	if selecting:
		return
	time_left -= delta
	timer_label.text = "%d:%02d" % [floori(time_left / 60.0), int(time_left) % 60]
	if time_left <= 0.0:
		_auto_pick()
		return
	var any_in_zone := false
	for j in jeeps.duplicate():
		j.position.x += j.get_meta("speed") * delta
		if j.position.x > road.size.x:
			jeeps.erase(j)
			j.queue_free()
		elif not j.get_meta("passed") and _in_zone(j):
			any_in_zone = true
	para_btn.visible = any_in_zone

func _in_zone(j: TextureRect) -> bool:
	var cx := j.position.x + j.size.x / 2.0
	return absf(cx - road.size.x / 2.0) <= zone_width / 2.0

func _pick_tier() -> String:
	var total := 0
	for t in TIERS:
		total += TIERS[t]["weight"]
	var roll := randi() % total
	for t in TIERS:
		roll -= TIERS[t]["weight"]
		if roll < 0:
			return t
	return "poor"

func _textures_for(tier: String) -> Array[Texture2D]:
	match tier:
		"poor": return poor_textures
		"okay": return okay_textures
		"rich": return rich_textures
		_: return rare_textures

func _spawn_jeep() -> void:
	spawn_timer.start(randf_range(4.0, 6.0))
	var tier := _pick_tier()
	var texs := _textures_for(tier)
	if texs.is_empty():
		return
	var data: Dictionary = TIERS[tier]
	var j := TextureRect.new()
	j.texture = texs.pick_random()
	j.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	j.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	j.stretch_mode = TextureRect.STRETCH_SCALE
	j.size = j.texture.get_size() * jeep_scale
	j.position = Vector2(spawn_point.position.x - j.size.x, spawn_point.position.y - j.size.y)
	j.set_meta("tier", tier)
	j.set_meta("rank", data["rank"])
	j.set_meta("speed", data["speed"])
	j.set_meta("energy", randi_range(data["energy"][0], data["energy"][1]))
	j.set_meta("happy", randi_range(data["happy"][0], data["happy"][1]))
	j.set_meta("passed", false)
	road.add_child(j)
	jeeps.append(j)

func _on_para_po() -> void:
	var best: TextureRect = null
	for j in jeeps:
		if j.get_meta("passed") or not _in_zone(j):
			continue
		if best == null or j.get_meta("rank") < best.get_meta("rank"):
			best = j
	if best == null:
		return
	selected = best
	selecting = true
	spawn_timer.paused = true
	idle_timer.paused = true
	para_btn.hide()
	for j in jeeps:
		j.modulate = Color.WHITE if j == best else Color(0.4, 0.4, 0.4)
	stats_label.text = "%s jeep\nEnergy +%d\nHappiness +%d" % [
		str(best.get_meta("tier")).capitalize(),
		best.get_meta("energy"), best.get_meta("happy")]
	pass_btn.visible = chances > 1
	popup.show()

func _on_pass() -> void:
	selected.set_meta("passed", true)
	chances -= 1
	for j in jeeps:
		j.modulate = Color.WHITE
	popup.hide()
	selected = null
	selecting = false
	spawn_timer.paused = false
	idle_timer.paused = false

func _on_confirm() -> void:
	_finish(selected.get_meta("tier"), selected.get_meta("energy"), selected.get_meta("happy"), false)

func _auto_pick() -> void:
	var d: Dictionary = TIERS["poor"]
	_finish("poor", randi_range(d["energy"][0], d["energy"][1]),
		randi_range(d["happy"][0], d["happy"][1]), true)

func _finish(tier: String, energy: int, happy: int, auto: bool) -> void:
	selecting = true
	set_process(false)
	spawn_timer.stop()
	idle_timer.stop()
	finished.emit({"success": true, "tier": tier, "energy": energy, "happiness": happy, "auto": auto})
