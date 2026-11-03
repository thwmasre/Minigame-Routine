extends MinigameBase

@export var card_images: Dictionary[String, Texture2D] = {}
@export var smash_delay := 0.5
@export var hover_scale := 1.1
@export var float_height := 6.0
@export var shake_strength := 12.0

var options: Array = ["street_food", "school", "adventure"]
var cards: Array = []
var base_pos: Array = []
var landed: Array = []
var locked := true
var time := 0.0
var screen_origin := Vector2.ZERO

func setup(context: Dictionary = {}) -> void:
	if context.has("cards"):
		options = context["cards"]

func _ready() -> void:
	screen_origin = position
	call_deferred("_begin")

func _begin() -> void:
	var all := [$Card1, $Card2, $Card3]
	var count := clampi(options.size(), 2, 3)
	var shift := 0.0
	if count == 2:
		shift = (all[1].position.x - all[0].position.x) / 2.0
	for n in all.size():
		var c: TextureButton = all[n]
		if n >= count:
			c.hide()
			continue
		var i := cards.size()
		cards.append(c)
		landed.append(false)
		base_pos.append(c.position + Vector2(shift, 0))
		c.position = base_pos[i]
		var id: String = options[i]
		if card_images.has(id):
			c.texture_normal = card_images[id]
		c.pivot_offset = c.size / 2.0
		c.modulate.a = 0.0
		c.mouse_entered.connect(_on_hover.bind(i, true))
		c.mouse_exited.connect(_on_hover.bind(i, false))
		c.pressed.connect(_on_pick.bind(i))
		_play_intro(i, i * smash_delay)

func _play_intro(i: int, delay: float) -> void:
	var c: TextureButton = cards[i]
	c.scale = Vector2(3, 3)
	c.rotation_degrees = -720.0 if i % 2 == 0 else 720.0
	await get_tree().create_timer(delay).timeout
	c.modulate.a = 1.0
	var t := create_tween().set_parallel(true)
	t.tween_property(c, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	t.tween_property(c, "rotation_degrees", 0.0, 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	await t.finished
	await _shake()
	landed[i] = true
	if not landed.has(false):
		locked = false

func _shake() -> void:
	var t := create_tween()
	for k in 6:
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_strength
		t.tween_property(self, "position", screen_origin + off, 0.04)
	t.tween_property(self, "position", screen_origin, 0.04)
	await t.finished

func _process(delta: float) -> void:
	time += delta
	for i in cards.size():
		if landed[i]:
			cards[i].position.y = base_pos[i].y + sin(time * 2.0 + i) * float_height

func _on_hover(i: int, entered: bool) -> void:
	if locked:
		return
	var s := hover_scale if entered else 1.0
	create_tween().tween_property(cards[i], "scale", Vector2(s, s), 0.12)

func _on_pick(i: int) -> void:
	if locked:
		return
	locked = true
	set_process(false)
	var chosen: TextureButton = cards[i]
	var center := get_viewport_rect().size / 2.0 - chosen.size / 2.0
	var t := create_tween().set_parallel(true)
	for k in cards.size():
		if k == i:
			continue
		var other: TextureButton = cards[k]
		t.tween_property(other, "position:y", other.position.y + 900.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(other, "rotation_degrees", 25.0 if k % 2 == 0 else -25.0, 0.5)
	t.tween_property(chosen, "position", center, 0.5).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(chosen, "scale", Vector2(1.6, 1.6), 0.5).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	await get_tree().create_timer(0.4).timeout
	finished.emit({"choice": options[i]})
