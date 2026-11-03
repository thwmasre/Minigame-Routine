extends Node2D

signal finished(earnings: int, served: int, mistakes: int)

# ---------- SETTINGS (edit in the Inspector) ----------
@export_enum("Poor", "Middle", "Rich") var town := 1
@export var buko_chance := 0.5          # chance a customer also wants buko
@export var burnt_chance := 0.1        # chance a customer wants burnt food
@export var cook_time_min := 3.0        # seconds until cooked (random between min and max)
@export var cook_time_max := 7.0
@export var burn_time_min := 4.0        # extra seconds until burnt
@export var burn_time_max := 8.0
@export var first_customer_delay := 3.0 # seconds before the first customer arrives
@export var center_zoom := 1.5          # how big a strainer gets in the center
@export var container_zoom := 1.5       # how big the open container gets
@export var tray_zoom := 2.0            # how big the tray gets when clicked
@export var hand_reach_time := 1.5      # seconds for the customer hand to reach down
@export var drag_distance := 10.0       # moving the mouse more than this while pressing = drag
@export var cup_spawn_delay := 1.0      # seconds until a new cup appears
@export var bottle_spawn_delay := 1.0   # seconds until another bottle can be taken
@export var pixel_perfect := true       # true = clicking a transparent pixel does nothing
@export var click_padding := 20.0       # extra clickable border for tools and food
@export var tool_grip_offset := Vector2(0, 30)   # handle sits this far below your fingertip
@export var tongs_food_offset := Vector2(0, 0)   # where food hangs on the tongs tip
@export var hand_textures: Array[Texture2D] = []    # hand1, hand2, hand3
@export var paper_textures: Array[Texture2D] = []   # order_sheet, order_sheet1, order_sheet2
@export var table_textures: Array[Texture2D] = []   # [Poor, Middle, Rich]

# Edit these per town: [Poor, Middle, Rich]
const TOWN_GOAL := [100, 300, 800]       # money you must earn to finish
const TOWN_WAIT := [Vector2(60, 90), Vector2(50, 80), Vector2(40, 70)]   # seconds between customers (min, max)
const TOWN_PRICES := [
	{"kikiam": 5, "fishball": 1, "squidball": 3, "buko": 10},
	{"kikiam": 10, "fishball": 3, "squidball": 6, "buko": 20},
	{"kikiam": 20, "fishball": 6, "squidball": 12, "buko": 35},
]

enum State { PLAY, LOADING, TRAY }
var state := State.PLAY

var prices: Dictionary
var goal := 0
var earnings := 0
var served := 0
var mistakes := 0
var pending_payment := 0
var last_serve_ok := false
var game_over := false
var message := ""                 # temporary text shown at the top

# customer at the door
var hand_order: Order = null
var paper_on_hand := false
var hand_busy := false

# what is in your hand right now
var held: Node2D = null
var hold_offset := Vector2.ZERO
var just_picked := false          # true if we picked something up on this mouse press
var press_point := Vector2.ZERO

var tongs_food: Food = null
var kutsaron_loaded := false

var loading_strainer: Strainer = null
var container_open := false

var spot_cup: Node2D = null       # the cup waiting on the table
var cup_template: Node2D = null   # clean copy used to make new cups
var cup_spot_position := Vector2.ZERO
var bottle_ready := true

var money_ready := false

var container_home_scale := Vector2.ONE
var container_home_pos := Vector2.ZERO
var tray_home_pos := Vector2.ZERO
var tray_home_scale := Vector2.ONE

@onready var strainers: Array = [$Strainer1, $Strainer2]
@onready var piles: Dictionary = {
	"kikiam": $RawContainer/KikiamPile,
	"fishball": $RawContainer/FishballPile,
	"squidball": $RawContainer/SquidballPile,
}


func _ready() -> void:
	prices = TOWN_PRICES[town]
	goal = TOWN_GOAL[town]
		# the table picture depends on the town
	if town < table_textures.size() and table_textures[town] != null:
		$Table.texture = table_textures[town]
	# remember start sizes and positions
	container_home_scale = $RawContainer.scale
	container_home_pos = $RawContainer.position
	tray_home_pos = $Tray.position
	tray_home_scale = $Tray.scale

	# the cup on the table: keep a clean copy to make new cups later
	cup_template = $CupStack.duplicate()
	cup_spot_position = $CupStack.global_position
	spot_cup = $CupStack
	$CupStack.add_to_group("cup")

	# hide things that start hidden
	$FoodTemplates.visible = false
	$RawContainer.visible = false
	$DoneButton.visible = false
	$MoneyBill.visible = false
	$MoneyBill.z_index = 90
	$Hand/OrderPaper.visible = false
	$Hand/OrderPaper.show_behind_parent = true    # paper is behind the customer's fingers
	$Hand.position = $HandOut.position
	$Hand.z_index = 97
	$Dim.visible = false
	$Dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Dim.z_index = 50
	$ConfirmPanel.visible = false
	$ConfirmPanel.z_index = 70
	$OrderLabel.text = ""
	$OrderLabel.z_index = 80
	$CocoContainer/Opened.visible = false
	$Fryer/Oiled.visible = false
	$SauceSweet/Topping.visible = false
	$SauceSpicy/Topping.visible = false
	$Kutsaron/Scooped.visible = false
	$Trash/Red.visible = false
	$PlayerHand.z_index = 100

	# your hand replaces the mouse arrow
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	$ConfirmPanel/ConfirmButton.pressed.connect(_on_serve)
	$ConfirmPanel/HoldButton.pressed.connect(_on_back)
	$DoneButton.pressed.connect(_on_done)

	update_score()
	wait_for_customer(first_customer_delay)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(cup_template):
		cup_template.free()


# ---------------------------------------------------------
# INPUT
# ---------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	var e := event as InputEventMouseButton
	if e == null or e.button_index != MOUSE_BUTTON_LEFT:
		return
	var mouse := get_global_mouse_position()
	if e.pressed:
		on_press(mouse)
	else:
		on_release(mouse)


func on_press(point: Vector2) -> void:
	just_picked = false
	press_point = point

	if game_over:
		return

	# tray is zoomed: only the Serve / Back buttons work
	if state == State.TRAY:
		return

	# container: click the lid to open, then click the food you want
	if state == State.LOADING:
		if not container_open and is_over($RawContainer/Lid, point):
			open_container()
		elif held != null:
			use_or_drop(point)              # using the tongs
		elif is_near($Tongs, point):
			hold($Tongs, point)             # pick up the tongs
		return

	if held != null:
		use_or_drop(point)     # click again = use or drop what you hold
	else:
		pick_up(point)


# Dragging: if you moved the mouse while pressing, drop when you let go
func on_release(point: Vector2) -> void:
	if game_over:
		return
	if held != null and just_picked and point.distance_to(press_point) > drag_distance:
		use_or_drop(point)
	just_picked = false


func _process(_delta: float) -> void:
	var mouse := get_global_mouse_position()
	$PlayerHand.global_position = mouse

	if held != null:
		held.global_position = mouse + hold_offset
		# tools: your hand holds the HANDLE, the tip sticks out the other end
		if held == $Tongs or held == $Kutsaron:
			held.global_position += (mouse + tool_grip_offset) - tool_handle(held)

	# food hangs on the tongs' tip
	if tongs_food != null:
		tongs_food.global_position = tool_tip($Tongs) + tongs_food_offset

	# coconut chiller opens when the kutsaron's tip is above it
	$CocoContainer/Opened.visible = held == $Kutsaron and is_over($CocoContainer, tool_tip($Kutsaron))
	$Kutsaron/Scooped.visible = kutsaron_loaded

	# trash turns red when something you hold is over it
	var over_trash := false
	if held != null and (held.is_in_group("cup") or held.is_in_group("bottle")):
		over_trash = is_over($Trash, mouse)
	if tongs_food != null:
		over_trash = is_near($Trash, tool_tip($Tongs))
	$Trash/Red.visible = over_trash

	# the order text shows only while you hold a paper
	if not game_over:
		if held != null and held.is_in_group("paper"):
			var o := held.get_meta("order") as Order
			$OrderLabel.text = o.to_text()
		else:
			$OrderLabel.text = message


# ---------------------------------------------------------
# HELPERS
# ---------------------------------------------------------
# The sprite we use for click checks: the node itself, or its child "Body"
func body_of(node: Node) -> Sprite2D:
	# use the child "Body" if it has a picture
	if node.has_node("Body"):
		var b: Sprite2D = node.get_node("Body")
		if b.texture != null:
			return b
	# otherwise the node itself
	if node is Sprite2D:
		return node
	return node.get_node("Body")


# Is this point (mouse) on top of this node's picture?
func is_over(node: Node, point: Vector2) -> bool:
	var sprite := body_of(node)
	if not sprite.is_visible_in_tree():
		return false
	var local_point := sprite.to_local(point)
	if not sprite.get_rect().has_point(local_point):
		return false
	if pixel_perfect and node != $Plate:
		return sprite.is_pixel_opaque(local_point)
	return true


# Like is_over, but with a bigger click area (easier for thin things like tongs)
func is_near(node: Node, point: Vector2) -> bool:
	var sprite := body_of(node)
	if not sprite.is_visible_in_tree():
		return false
	return sprite.get_rect().grow(click_padding).has_point(sprite.to_local(point))


# The tip of a tool: the Tip marker if it exists, otherwise the top-middle of its picture
func tool_tip(tool_node: Node2D) -> Vector2:
	if tool_node.has_node("Tip"):
		return tool_node.get_node("Tip").global_position
	var body := body_of(tool_node)
	var rect := body.get_rect()
	return body.to_global(Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y))


# The handle of a tool: the Handle marker if it exists, otherwise the bottom-middle of its picture
func tool_handle(tool_node: Node2D) -> Vector2:
	if tool_node.has_node("Handle"):
		return tool_node.get_node("Handle").global_position
	var body := body_of(tool_node)
	var rect := body.get_rect()
	return body.to_global(Vector2(rect.position.x + rect.size.x / 2.0, rect.end.y))


func update_score() -> void:
	$ScoreLabel.text = "Php %d / %d   Served %d" % [earnings, goal, served]


func show_message(text: String) -> void:
	message = text
	get_tree().create_timer(2.0).timeout.connect(_clear_message)


func _clear_message() -> void:
	if not game_over:
		message = ""


# z_index for things you hold (your hand is 100, the customer hand is 97)
func held_z() -> int:
	return 95


# ---------------------------------------------------------
# PICK UP / DROP
# ---------------------------------------------------------
# Nothing in hand: what did we click?

func pick_up(point: Vector2) -> void:
	
	# order paper in the customer's hand
	if paper_on_hand and is_over($Hand/OrderPaper, point):
		take_paper(point)
		return

	# money
	if money_ready and is_over($MoneyBill, point):
		take_money()
		return

	# things lying around (tools, cups, bottles, papers)
	var item = find_item(point)
	if item != null:
		hold(item, point)
		return
		# plate: empties the strainer that is in the center onto it
	if is_over($Plate, point):
		dump_strainer_on_plate()
		return
	# strainers
	for i in strainers.size():
		if is_over(strainers[i], point):
			click_strainer(i)
			return

	# tray
	if is_over($Tray, point):
		open_tray()


func find_item(point: Vector2):
	# 1. tools first, so they can always be picked up again
	for utensil in [$Tongs, $Kutsaron]:
		if is_near(utensil, point):
			return utensil

	# 2. loose cups, bottles and papers (the newest on top first)
	var items := []
	items.append_array(get_tree().get_nodes_in_group("cup"))
	items.append_array(get_tree().get_nodes_in_group("bottle"))
	items.append_array(get_tree().get_nodes_in_group("paper"))
	items.reverse()
	for it in items:
		if is_over(it, point):
			return it

	# 3. the bottle container gives a new bottle
	if is_over($BottleStack, point):
		return spawn_bottle()
	return null


# Make a copy of a node (used for bottles and cups)
func spawn_copy(source: Node2D, group_name: String) -> Node2D:
	var copy: Node2D = source.duplicate()
	copy.add_to_group(group_name)
	add_child(copy)
	copy.global_position = source.global_position
	return copy


# Take a bottle from the container (one at a time, with a short wait)
func spawn_bottle() -> Node2D:
	if not bottle_ready:
		return null
	bottle_ready = false
	get_tree().create_timer(bottle_spawn_delay).timeout.connect(_bottle_ready_again)
	return spawn_copy($BottleStack, "bottle")


func _bottle_ready_again() -> void:
	bottle_ready = true


# Put a new empty cup on the table
func spawn_spot_cup() -> void:
	spot_cup = cup_template.duplicate()
	spot_cup.add_to_group("cup")
	add_child(spot_cup)
	spot_cup.global_position = cup_spot_position


func hold(item: Node2D, point: Vector2) -> void:
	held = item
	hold_offset = item.global_position - point
	item.z_index = held_z()
	just_picked = true
	if item.get_parent() != self:
		item.reparent(self)             # taken out of the tray
	if item == spot_cup:
		spot_cup = null
		get_tree().create_timer(cup_spawn_delay).timeout.connect(spawn_spot_cup)


# Something is in hand and we clicked: use it or drop it
func use_or_drop(point: Vector2) -> void:
	if held == $Tongs:
		use_tongs(point)
	elif held == $Kutsaron:
		use_kutsaron(point)
	else:
		drop_item(point)


# Let go of what we hold (it stays where it is, on top of whatever is below)
func put_down() -> void:
	held.z_index = 0
	held.get_parent().move_child(held, -1)
	held = null


# Drop a cup, bottle or paper
func drop_item(point: Vector2) -> void:
	var item := held
	put_down()
	

	if item.is_in_group("cup"):
		var cup := item as Cup
		if is_over($SauceSweet, point):
			cup.add_sauce("sweet", $SauceSweet/Topping.texture)
		elif is_over($SauceSpicy, point):
			cup.add_sauce("spicy", $SauceSpicy/Topping.texture)
		# cup on the plate: the food goes onto the plate
		
	if item.is_in_group("cup") and is_over($Plate, point):
		empty_cup_onto_plate(item as Cup)
	# trash
	if (item.is_in_group("cup") or item.is_in_group("bottle")) and is_over($Trash, point):
		item.queue_free()
		return

	# tray
	if is_over($Tray, point):
		item.reparent($Tray)

# Click the plate with a strainer in the center: all its food goes onto the plate
func dump_strainer_on_plate() -> void:
	var st := strainer_in_center()
	if st == null:
		return
	for f in st.get_foods():
		if $Plate.is_full():
			show_message("The plate is full!")
			return
		st.take_food(f)
		$Plate.add_food(f)
	# the strainer is empty now: put it back
	st.move_to(st.home_position, Strainer.HOME)
	update_oil()


# Drop a cup on the plate: all its food goes onto the plate (not if it has sauce)
func empty_cup_onto_plate(cup: Cup) -> void:
	if cup.sauce != "plain":
		show_message("The cup has sauce, it can't go on the plate!")
		return
	# last food first, so the ones left stay in the first cup slots
	for i in range(cup.foods.size() - 1, -1, -1):
		if $Plate.is_full():
			show_message("The plate is full!")
			return
		var f: Food = cup.foods[i]
		cup.remove_food(f)
		$Plate.add_food(f)
# ---------------------------------------------------------
# TONGS
# ---------------------------------------------------------
func use_tongs(_click_point: Vector2) -> void:
	var point := tool_tip($Tongs)    # the tongs pick things up with their TIP
	var st := active_strainer()      # the strainer being loaded, or the one in the center

	if tongs_food == null:
		# a new raw food from the open container
		if state == State.LOADING and container_open and is_over($RawContainer/Body, point):
			grab_from_container(point)
			return
		# food in the strainer
		if st != null:
			var sf = closest_food(st.get_foods(), point)
			if sf != null:
				st.take_food(sf)
				grab_food(sf)
				return
		# food on the plate
		var pf = closest_food($Plate.get_foods(), point)
		if pf != null:
			$Plate.take_food(pf)
			grab_food(pf)
			return
		# food lying on the table
		var lf = closest_food(get_tree().get_nodes_in_group("loose_food"), point)
		if lf != null:
			lf.remove_from_group("loose_food")
			grab_food(lf)
			return
		# nothing to grab: tongs drop where they are
		put_down()
	else:
		# put the food in the strainer (the one loading or in the center)
		if st != null and is_near(st, point) and not st.is_full():
			st.add_food(tongs_food)
			tongs_food = null
			return
		# back in the container: only raw food
		if state == State.LOADING and container_open and is_over($RawContainer/Body, point):
			if tongs_food.state == 0:
				tongs_food.queue_free()
				tongs_food = null
			else:
				show_message("Only raw food goes back in the container!")
			return
		# drop the food in a cup
		for c in get_tree().get_nodes_in_group("cup"):
			var cup := c as Cup
			if is_over(cup, point) and not cup.is_full():
				cup.add_food(tongs_food)
				tongs_food = null
				return
		# put the food on the plate
		if is_over($Plate, point) and not $Plate.is_full():
			$Plate.add_food(tongs_food)
			tongs_food = null
			return
		# trash: a single food can be thrown away like this
		if is_near($Trash, point):
			tongs_food.queue_free()
			tongs_food = null
			return
		# empty spot: the food drops where it is
		drop_food()


func strainer_in_center() -> Strainer:
	for s in strainers:
		var st := s as Strainer
		if st.state == Strainer.CENTER:
			return st
	return null


# The tongs pick up a food piece
func grab_food(f: Food) -> void:
	if f.get_parent() == null:
		add_child(f)                 # brand new food from the container
	elif f.get_parent() != self:
		f.reparent(self)
	f.scale = f.base_scale
	f.z_index = held_z() + 1
	tongs_food = f


# The tongs let go of the food. It stays on the table and can be picked up again.
func drop_food() -> void:
	var f := tongs_food
	tongs_food = null
	f.z_index = 0
	f.add_to_group("loose_food")
	move_child(f, -1)


# ---------------------------------------------------------
# KUTSARON + BUKO
# ---------------------------------------------------------
func use_kutsaron(click_point: Vector2) -> void:
	var point := tool_tip($Kutsaron)    # the kutsaron works with its TIP

	# click with the tip above the chiller: scoop coconut
	if is_over($CocoContainer, point):
		kutsaron_loaded = true
		return

	# loaded: click a bottle to fill it and pick it up
	if kutsaron_loaded:
		var bottle: Bottle = null
		if is_over($BottleStack, point):
			bottle = spawn_bottle() as Bottle
		else:
			for b in get_tree().get_nodes_in_group("bottle"):
				if is_over(b, point) and not (b as Bottle).filled:
					bottle = b as Bottle
		if bottle != null:
			bottle.fill()
			kutsaron_loaded = false
			put_down()                      # kutsaron stays where it is
			hold(bottle, click_point)       # now we hold the bottle
			return

	# anything else: kutsaron drops where it is
	kutsaron_loaded = false
	put_down()


# ---------------------------------------------------------
# STRAINERS + FOOD CONTAINER
# ---------------------------------------------------------
func click_strainer(i: int) -> void:
	var st := strainers[i] as Strainer
	var other := strainers[1 - i] as Strainer

	# if the other strainer is busy, this one can't be clicked
	if other.state == Strainer.LOADING or other.state == Strainer.CENTER:
		return

	if st.state == Strainer.HOME:
		start_loading(st)
	elif st.state == Strainer.COOKING:
		st.move_to($CenterSpot.global_position, Strainer.CENTER, center_zoom)
	elif st.state == Strainer.CENTER:
		if st.get_foods().is_empty():
			st.move_to(st.home_position, Strainer.HOME)
		else:
			put_in_fryer(st)
	update_oil()


func start_loading(st: Strainer) -> void:
	state = State.LOADING
	loading_strainer = st
	container_open = false
	st.move_to($LoadSpot.global_position, Strainer.LOADING)

	# the closed container pops up
	$RawContainer.visible = true
	$RawContainer.z_index = 10
	$RawContainer/Lid.visible = true
	$RawContainer/Body.visible = false
	$RawContainer.position = container_home_pos
	$RawContainer.scale = Vector2(0.01, 0.01)
	create_tween().tween_property($RawContainer, "scale", container_home_scale, 0.25).set_trans(Tween.TRANS_BACK)
	$DoneButton.visible = true


# Click the lid: it opens and moves to the middle
func open_container() -> void:
	container_open = true
	$RawContainer/Lid.visible = false
	$RawContainer/Body.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property($RawContainer, "position", $ContainerSpot.position, 0.3)
	tw.tween_property($RawContainer, "scale", container_home_scale * container_zoom, 0.3)


func close_container() -> void:
	container_open = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property($RawContainer, "position", container_home_pos, 0.25)
	tw.tween_property($RawContainer, "scale", Vector2(0.01, 0.01), 0.25)
	tw.chain().tween_callback(_after_container_close)


func _after_container_close() -> void:
	if state != State.LOADING:
		$RawContainer.visible = false


# Find which food pile is closest to the click and put that food in the strainer
func pick_from_container(point: Vector2) -> void:
	if loading_strainer.is_full():
		return
	var best := ""
	var best_dist := 999999.0
	for kind in piles:
		var d: float = piles[kind].global_position.distance_to(point)
		if d < best_dist:
			best_dist = d
			best = kind
	loading_strainer.add_food(make_food(best))


func _on_done() -> void:
	if tongs_food != null:
		show_message("Drop the food first!")
		return
	$DoneButton.visible = false
	state = State.PLAY
	close_container()
	var st := loading_strainer
	loading_strainer = null
	if st.get_foods().is_empty():
		st.move_to(st.home_position, Strainer.HOME)
	else:
		put_in_fryer(st)
	update_oil()

# The strainer you can put food in or take food from right now
func active_strainer() -> Strainer:
	if state == State.LOADING:
		return loading_strainer
	return strainer_in_center()


# The food in a list that is closest to the point (null if none is near)
func closest_food(food_list: Array, point: Vector2):
	var best = null
	var best_dist := 999999.0
	for f in food_list:
		if is_near(f, point):
			var d: float = f.global_position.distance_to(point)
			if d < best_dist:
				best_dist = d
				best = f
	return best

# Pick a random picture from a list (empty slots are ignored)
func random_texture(list: Array[Texture2D]) -> Texture2D:
	var valid: Array[Texture2D] = []
	for t in list:
		if t != null:
			valid.append(t)
	if valid.is_empty():
		return null
	return valid.pick_random()

# Grab a new raw food from the container: the pile closest to the tongs tip
func grab_from_container(point: Vector2) -> void:
	var best := ""
	var best_dist := 999999.0
	for kind in piles:
		var d: float = piles[kind].global_position.distance_to(point)
		if d < best_dist:
			best_dist = d
			best = kind
	grab_food(make_food(best))
	
func put_in_fryer(st: Strainer) -> void:
	var i := strainers.find(st)
	var spot: Marker2D = get_node("Fryer/StrainerSpot" + str(i + 1))
	st.move_to(spot.global_position, Strainer.COOKING)


# Fryer is oiled while at least one strainer is cooking in it
func update_oil() -> void:
	var s1 := strainers[0] as Strainer
	var s2 := strainers[1] as Strainer
	$Fryer/Oiled.visible = s1.state == Strainer.COOKING or s2.state == Strainer.COOKING


# Build a new food piece using the pictures and size from FoodTemplates
func make_food(kind: String) -> Food:
	var f := Food.new()
	f.kind = kind

	# randomly use the first look or the second look (kikiam2_1, kikiam2_2, ...)
	var variant := randi_range(1, 3)
	var raw_scale := Vector2.ONE
	for i in 3:
		var template_name := kind + str(i + 1)
		if variant == 2:
			template_name = kind + "2_" + str(i + 1)
		var template: Sprite2D = $FoodTemplates.get_node(template_name)
		f.textures.append(template.texture)
		if i == 0:
			raw_scale = template.scale

	f.scale = raw_scale
	f.base_scale = raw_scale
	f.cook_time = randf_range(cook_time_min, cook_time_max)
	f.burn_time = randf_range(burn_time_min, burn_time_max)
	f.set_state(0)
	return f


# ---------------------------------------------------------
# CUSTOMERS (they come by themselves, at random times)
# ---------------------------------------------------------
func wait_for_customer(seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(customer_arrives)


# A random wait for the next customer (set per town at the top)
func next_wait() -> float:
	var w: Vector2 = TOWN_WAIT[town]
	return randf_range(w.x, w.y)


func customer_arrives() -> void:
	if game_over:
		return

	# the door is busy (the last customer is still there): try again soon
	if hand_busy:
		wait_for_customer(3.0)
		return

	hand_busy = true
	hand_order = Order.new()
	hand_order.randomize_order(buko_chance, burnt_chance)

	var hand_tex := random_texture(hand_textures)
	if hand_tex != null:
		$Hand.texture = hand_tex
	var paper_tex := random_texture(paper_textures)
	if paper_tex != null:
		$Hand/OrderPaper.texture = paper_tex
	$Hand/OrderPaper.visible = true
	hand_enter()

	# the next customer comes later, even if you are not done with this order
	wait_for_customer(next_wait())


func hand_enter() -> void:
	var tw := create_tween()
	tw.tween_property($Hand, "position", $HandIn.position, hand_reach_time)
	tw.tween_callback(_hand_arrived)


# The arm is fully stretched: now the paper can be taken
func _hand_arrived() -> void:
	paper_on_hand = true


func hand_leave() -> void:
	var tw := create_tween()
	tw.tween_property($Hand, "position", $HandOut.position, 0.8)
	tw.tween_callback(_hand_gone)


func _hand_gone() -> void:
	hand_busy = false


# Player takes the order paper from the customer's hand. The paper keeps its own order.
func take_paper(point: Vector2) -> void:
	paper_on_hand = false
	var p: Sprite2D = $Hand/OrderPaper
	var paper: Sprite2D = p.duplicate()
	paper.show_behind_parent = false
	paper.add_to_group("paper")
	paper.set_meta("order", hand_order)
	add_child(paper)
	paper.global_position = p.global_position
	paper.global_scale = p.global_scale
	paper.global_rotation = p.global_rotation
	p.visible = false
	hold(paper, point)
	hand_leave()
	paper.z_index = 98

# ---------------------------------------------------------
# MONEY (drops from the top, no hand)
# ---------------------------------------------------------
func drop_money() -> void:
	$MoneyBill.position = $MoneyStart.position
	$MoneyBill.visible = true
	var tw := create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property($MoneyBill, "position", $MoneyEnd.position, 0.7)
	tw.tween_callback(_money_landed)


func _money_landed() -> void:
	money_ready = true


func take_money() -> void:
	money_ready = false
	$MoneyBill.visible = false
	earnings += pending_payment
	pending_payment = 0
	update_score()
	if earnings >= goal:
		end_game()


func end_game() -> void:
	game_over = true
	message = "Goal reached! Earned Php %d" % earnings
	$OrderLabel.text = message
	finished.emit(earnings, served, mistakes)


# ---------------------------------------------------------
# TRAY (zoom, serve, swipe up)
# ---------------------------------------------------------
func open_tray() -> void:
	state = State.TRAY
	$Dim.visible = true
	$Tray.z_index = 60
	$ConfirmPanel.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property($Tray, "global_position", $TrayCenter.global_position, 0.25)
	tw.tween_property($Tray, "scale", tray_home_scale * tray_zoom, 0.25)


# Back button: zoom out and keep playing
func _on_back() -> void:
	$ConfirmPanel.visible = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property($Tray, "position", tray_home_pos, 0.25)
	tw.tween_property($Tray, "scale", tray_home_scale, 0.25)
	tw.chain().tween_callback(_after_tray_zoom_out)


func _after_tray_zoom_out() -> void:
	$Tray.z_index = 0
	$Dim.visible = false
	state = State.PLAY


# Serve button: the paper on the tray says which order to check
func _on_serve() -> void:
	var cups := []
	var bottles := []
	var paper: Sprite2D = null
	for n in $Tray.get_children():
		if n.is_in_group("cup"):
			cups.append(n)
		elif n.is_in_group("bottle"):
			bottles.append(n)
		elif n.is_in_group("paper"):
			paper = n

	if paper == null:
		show_message("Put the order paper on the tray!")
		return

	$ConfirmPanel.visible = false
	var order := paper.get_meta("order") as Order
	served += 1
	last_serve_ok = order.is_correct(cups, bottles)
	if last_serve_ok:
		pending_payment += order.get_price(prices)
	else:
		mistakes += 1
	update_score()

	# zoom out and swipe up
	var tw := create_tween().set_parallel(true)
	tw.tween_property($Tray, "scale", tray_home_scale, 0.4)
	tw.tween_property($Tray, "global_position", $TrayOut.global_position, 0.4)
	tw.chain().tween_callback(_after_serve_swipe)


func _after_serve_swipe() -> void:
	# clear the tray
	for n in $Tray.get_children():
		if n.is_in_group("cup") or n.is_in_group("bottle") or n.is_in_group("paper"):
			n.queue_free()

	# empty tray comes back
	$Tray.z_index = 0
	$Tray.position = tray_home_pos
	$Tray.modulate.a = 0.0
	create_tween().tween_property($Tray, "modulate:a", 1.0, 0.3)
	$Dim.visible = false
	state = State.PLAY

	# money drops if the order was right
	if last_serve_ok and not $MoneyBill.visible:
		drop_money()
