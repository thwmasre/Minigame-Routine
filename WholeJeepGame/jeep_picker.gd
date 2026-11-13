extends MinigameBase

signal destination_chosen(dest_id: String, how_far: int, scene_path: String)
signal arrived(dest_id: String, scene_path: String)

const BASE_ENERGY := -1
const BASE_HAPPY := -1

const TIERS := {
	"poor": {"rank": 0, "speed": 200.0, "weight": 50, "energy": 0, "happy": 0, "extra": 0},
	"okay": {"rank": 1, "speed": 290.0, "weight": 28, "energy": 0, "happy": 1, "extra": 0},
	"rich": {"rank": 2, "speed": 400.0, "weight": 15, "energy": 1, "happy": 1, "extra": 10},
	"rare": {"rank": 3, "speed": 560.0, "weight": 7, "energy": 1, "happy": 2, "extra": 20},
}

# Total fare from Brgy to each level. A trip costs the difference.
const LEVEL_FARE := [15, 25, 35]

@export_enum("Middle", "High") var location := 0
@export var backgrounds: Array[Texture2D]
@export var moves_left := true
@export var poor_textures: Array[Texture2D]
@export var okay_textures: Array[Texture2D]
@export var rich_textures: Array[Texture2D]
@export var rare_textures: Array[Texture2D]
@export var jeep_scale := 0.5
@export var zone_width := 300.0
@export var time_limit := 120.0
@export var hop_time := 0.7
@export var drop_time := 2.0
@export var max_passes := 1

@export_group("Destinations")
@export var ride_scene: PackedScene
@export_enum("day", "dawn", "night") var time_of_day := "day"
@export var change_scene_on_arrive := false
@export_enum("Brgy (0)", "Bayan (1)", "City (2)") var current_level := 0
@export_enum("Near", "Far", "Farthest") var distance := 0

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
@onready var destinations: Control = get_node_or_null("Destinations")
@onready var fare_popup: Panel = get_node_or_null("FarePopup")
@onready var fare_label: Label = get_node_or_null("FarePopup/FareLabel")
@onready var fare_confirm_btn: Button = get_node_or_null("FarePopup/ConfirmFareButton")
@onready var hold_btn: Button = get_node_or_null("FarePopup/HoldButton")

var jeeps: Array[TextureRect] = []
var markers: Array = []
var selected: TextureRect = null
var selecting := false
var auto_drop := false
var passes_left := 0
var time_left := 0.0
var hop_left := 0.0
var hover_tween: Tween
var jeep_result: Dictionary = {}
var pending_dest: TextureButton = null
var open_options: Control = null


func _ready() -> void:
	time_left = time_limit
	passes_left = max_passes
	if not backgrounds.is_empty():
		background.texture = backgrounds[clampi(location, 0, backgrounds.size() - 1)]
	var marker_root := get_node_or_null("ParaPoMarkers")
	if marker_root:
		markers = marker_root.get_children()
	spawn_timer.one_shot = true
	spawn_timer.timeout.connect(_spawn_jeep)
	para_btn.pressed.connect(_on_para_po)
	confirm_btn.pressed.connect(_on_confirm)
	pass_btn.pressed.connect(_on_pass)
	para_btn.hide()
	popup.hide()
	if destinations:
		destinations.hide()
		for b in _dest_buttons():
			b.chosen.connect(_on_destination_chosen)
		for c in _category_buttons():
			c.chosen.connect(_on_category_chosen)
			if c.options:
				c.options.hide()
				for ob in _option_buttons(c.options):
					ob.chosen.connect(_on_destination_chosen)
				var back: BaseButton = c.options.get_node_or_null("BackButton") as BaseButton
				if back:
					back.pressed.connect(_close_options)
	if fare_popup:
		fare_popup.hide()
		fare_confirm_btn.pressed.connect(_on_fare_confirm)
		hold_btn.pressed.connect(_on_fare_hold)
	for group_name in ["MuseumOptions", "FoodOptions"]:
		var group: Node = get_node_or_null(group_name)
		if group:
			group.hide()
	_spawn_jeep()


func _process(delta: float) -> void:
	if selecting:
		return
	time_left = maxf(time_left - delta, 0.0)
	timer_label.text = "%d:%02d" % [floori(time_left / 60.0), int(time_left) % 60]
	if time_left <= 0.0:
		_auto_pick()
		return
	var dir := -1.0 if moves_left else 1.0
	var any_in_zone := false
	for j in jeeps.duplicate():
		j.position.x += dir * j.get_meta("speed") * delta
		var gone: bool = j.position.x + j.size.x < 0 if moves_left else j.position.x > road.size.x
		if gone:
			jeeps.erase(j)
			j.queue_free()
		elif not j.get_meta("passed") and _in_zone(j):
			any_in_zone = true
	if any_in_zone:
		hop_left -= delta
		if hop_left <= 0.0:
			hop_left = hop_time
			_hop_button()
	else:
		hop_left = 0.0
	para_btn.visible = any_in_zone


func _hop_button() -> void:
	if markers.is_empty():
		return
	var m: Marker2D = markers.pick_random()
	para_btn.global_position = m.global_position - para_btn.size / 2.0


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
	j.flip_h = moves_left
	j.size = j.texture.get_size() * jeep_scale
	var y := spawn_point.position.y - j.size.y
	if moves_left:
		j.position = Vector2(road.size.x, y)
	else:
		j.position = Vector2(spawn_point.position.x - j.size.x, y)
	j.set_meta("tier", tier)
	j.set_meta("rank", data["rank"])
	j.set_meta("speed", data["speed"])
	j.set_meta("energy", BASE_ENERGY + data["energy"])
	j.set_meta("happy", BASE_HAPPY + data["happy"])
	j.set_meta("extra", data["extra"])
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
	para_btn.hide()
	for j in jeeps:
		j.modulate = Color.WHITE if j == best else Color(0.4, 0.4, 0.4)
	stats_label.text = "%s jeep\nEnergy %+d\nHappiness %+d\nExtra -₱%d" % [
		str(best.get_meta("tier")).capitalize(),
		best.get_meta("energy"), best.get_meta("happy"), best.get_meta("extra")]
	pass_btn.visible = passes_left > 0
	pass_btn.disabled = passes_left <= 0
	popup.show()


func _on_pass() -> void:
	if passes_left <= 0:
		return
	passes_left -= 1
	selected.set_meta("passed", true)
	for j in jeeps:
		j.modulate = Color.WHITE
	popup.hide()
	selected = null
	selecting = false
	spawn_timer.paused = false


func _on_confirm() -> void:
	jeep_result = {"success": true, "tier": selected.get_meta("tier", "poor"),
		"energy": selected.get_meta("energy", 0), "happiness": selected.get_meta("happy", 0),
		"extra": int(selected.get_meta("extra", 0)), "auto": auto_drop}
	_apply_fare(distance)
	_show_destinations()


func _apply_fare(to_level: int) -> void:
	var last: int = LEVEL_FARE.size() - 1
	var a: int = LEVEL_FARE[clampi(current_level, 0, last)]
	var b: int = LEVEL_FARE[clampi(to_level, 0, last)]
	var fare: int = LEVEL_FARE[0] if current_level == to_level else absi(b - a)
	jeep_result["fare"] = fare
	jeep_result["money"] = -(int(jeep_result.get("extra", 0)) + fare)


func _show_destinations() -> void:
	if hover_tween:
		hover_tween.kill()
	selecting = true
	set_process(false)
	spawn_timer.stop()
	popup.hide()
	para_btn.hide()
	timer_label.hide()
	road.hide()
	if selected and selected.get_parent() == self:
		selected.hide()

	var any := false
	for b in _dest_buttons():
		b.visible = b.enabled
		b.disabled = not b.enabled
		any = any or b.enabled
	for c in _category_buttons():
		c.visible = c.enabled
		c.disabled = not c.enabled
		any = any or c.enabled
	if destinations:
		destinations.show()
	if not any:
		_finish("", "")


# ---------------- DESTINATION / FARE ----------------

func _on_destination_chosen(btn: TextureButton) -> void:
	if pending_dest != null or jeep_result.is_empty():
		return
	var far_value = btn.get("how_far")
	if far_value == null:
		
		push_warning("%s has no destination_button.gd attached" % btn.name)
		return
	if btn.get("free_return") == true:
		jeep_result["fare"] = 0
		jeep_result["extra"] = 0
		jeep_result["money"] = 0
		destination_chosen.emit(btn.get("destination_id"), btn.get("how_far"), btn.get("scene_path"))
		_arrive(btn)
		return
	pending_dest = btn
	for b in _dest_buttons():
		b.disabled = true
	_apply_fare(int(far_value))

	if fare_popup == null:
		_on_fare_confirm()
		return

	fare_label.text = "%s\nFare ₱%d\nJeep extra ₱%d\nTotal ₱%d" % [
		str(btn.get("destination_id")).replace("_", " ").capitalize(),
		int(jeep_result.get("fare", 0)), int(jeep_result.get("extra", 0)),
		-int(jeep_result.get("money", 0))]
	fare_popup.show()


func _on_fare_hold() -> void:
	fare_popup.hide()
	pending_dest = null
	for b in _dest_buttons():
		b.disabled = not b.enabled


func _on_fare_confirm() -> void:
	var btn := pending_dest
	pending_dest = null
	if btn == null:
		return
	if fare_popup:
		fare_popup.hide()
	destination_chosen.emit(btn.get("destination_id"), btn.get("how_far"), btn.get("scene_path"))

	var scene: PackedScene = btn.get("ride_scene")
	if scene == null:
		scene = ride_scene
	if scene == null:
		push_warning("No ride scene on the button or the root, skipping the animation.")
		_arrive(btn)
		return

	destinations.hide()
	if open_options:
		open_options.hide()
	var ride := scene.instantiate()
	add_child(ride)
	if ride is Control:
		ride.set_anchors_preset(Control.PRESET_FULL_RECT)
	move_child(ride, get_child_count() - 1)
	var tod: String = str(btn.get("time_of_day"))
	ride.setup({
		"from_far": current_level,
		"how_far": btn.get("how_far"),
		"time_of_day": time_of_day if tod == "use_picker" else tod,
	})
	await ride.ride_finished
	ride.queue_free()
	_arrive(btn)


func _arrive(btn: TextureButton) -> void:
	var id := str(btn.get("destination_id"))
	var path := str(btn.get("scene_path"))
	arrived.emit(id, path)
	if change_scene_on_arrive and path != "":
		get_tree().change_scene_to_file(path)
	else:
		_finish(id, path)


# ---------------- BUTTON LOOKUP ----------------

func _dest_buttons() -> Array:
	var out: Array = []
	if destinations:
		for c in destinations.get_children():
			if c is DestinationButton:
				out.append(c)
	return out


func _category_buttons() -> Array:
	var out: Array = []
	if destinations:
		for c in destinations.get_children():
			if c is CategoryButton:
				out.append(c)
	return out


func _option_buttons(group: Control) -> Array:
	var out: Array = []
	for c in group.get_children():
		if c is DestinationButton:
			out.append(c)
	return out


func _on_category_chosen(cat: CategoryButton) -> void:
	if cat.options == null:
		push_warning("Category %s has no Options node assigned." % cat.category_id)
		return
	if open_options and open_options != cat.options:
		open_options.hide()
	open_options = cat.options
	open_options.show()
	for b in _option_buttons(open_options):
		b.visible = b.enabled
		b.disabled = not b.enabled


func _close_options() -> void:
	if open_options:
		open_options.hide()
		open_options = null
	destinations.show()


# ---------------- AUTO PICK (time ran out) ----------------

func _auto_pick() -> void:
	selecting = true
	auto_drop = true
	spawn_timer.stop()
	para_btn.hide()
	for j in jeeps:
		j.hide()
	var d: Dictionary = TIERS["poor"]
	if poor_textures.is_empty():
		jeep_result = {"success": true, "tier": "poor", "energy": BASE_ENERGY + d["energy"],
			"happiness": BASE_HAPPY + d["happy"], "extra": int(d["extra"]), "auto": true}
		_apply_fare(distance)
		_show_destinations()
		return
	var j := TextureRect.new()
	j.texture = poor_textures.pick_random()
	j.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	j.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	j.stretch_mode = TextureRect.STRETCH_SCALE
	j.flip_h = moves_left
	j.size = j.texture.get_size() * jeep_scale
	j.set_meta("tier", "poor")
	j.set_meta("energy", BASE_ENERGY + d["energy"])
	j.set_meta("happy", BASE_HAPPY + d["happy"])
	j.set_meta("extra", d["extra"])
	var screen := get_viewport_rect().size
	var end_y := screen.y / 2.0 - j.size.y / 2.0
	j.position = Vector2(screen.x / 2.0 - j.size.x / 2.0, -j.size.y)
	add_child(j)
	move_child(j, popup.get_index())
	selected = j
	var t := create_tween()
	t.tween_property(j, "position:y", end_y, drop_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	hover_tween = create_tween().set_loops()
	hover_tween.tween_property(j, "position:y", end_y - 8.0, 0.7).set_trans(Tween.TRANS_SINE)
	hover_tween.tween_property(j, "position:y", end_y + 8.0, 0.7).set_trans(Tween.TRANS_SINE)
	stats_label.text = "Poor jeep\nEnergy %+d\nHappiness %+d\nExtra -₱%d" % [
		j.get_meta("energy"), j.get_meta("happy"), j.get_meta("extra")]
	pass_btn.hide()
	popup.show()


func _finish(dest_id: String, scene_path: String) -> void:
	set_process(false)
	spawn_timer.stop()
	var result := jeep_result.duplicate()
	result["destination"] = dest_id
	result["scene_path"] = scene_path
	finished.emit(result)	
