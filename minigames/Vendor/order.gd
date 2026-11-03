extends RefCounted
class_name Order
# What one customer wants.

var foods := {}          # example: {"kikiam": 2, "fishball": 1}
var food_state := 1      # 1 = cooked, 2 = burnt
var sauce := "plain"     # "plain", "sweet" or "spicy"
var has_buko := false


# Make a random order
func randomize_order(buko_chance: float, burnt_chance: float) -> void:
	var kinds := ["kikiam", "fishball", "squidball"]
	var sauces := ["plain", "sweet", "spicy"]
	for i in randi_range(1, 4):                 # 1 to 4 pieces of food
		var k: String = kinds.pick_random()
		foods[k] = foods.get(k, 0) + 1
	food_state = 2 if randf() < burnt_chance else 1
	sauce = sauces.pick_random()
	has_buko = randf() < buko_chance


# Text shown at the top of the screen
func to_text() -> String:
	var parts: PackedStringArray = []
	for k in foods:
		parts.append(str(foods[k]) + " " + str(k))
	var state_word := "burnt" if food_state == 2 else "cooked"
	var text := ", ".join(parts) + " (" + state_word + ")\nSauce: " + sauce
	if has_buko:
		text += "\n+ Buko juice"
	return text


# How much the customer pays
func get_price(prices: Dictionary) -> int:
	var total := 0
	for k in foods:
		total += foods[k] * prices[k]
	if has_buko:
		total += prices["buko"]
	return total


# Is what is on the tray the right order?
func is_correct(cups: Array, bottles: Array) -> bool:
	if cups.size() != 1:
		return false
	var cup: Cup = cups[0]
	if cup.sauce != sauce:
		return false

	# count the food inside the cup
	var counts := {}
	for f in cup.foods:
		if f.state != food_state:
			return false
		counts[f.kind] = counts.get(f.kind, 0) + 1
	if counts.size() != foods.size():
		return false
	for k in foods:
		if counts.get(k, 0) != foods[k]:
			return false

	# buko bottles
	var wanted := 1 if has_buko else 0
	var filled := 0
	for b in bottles:
		if b.filled:
			filled += 1
	return filled == wanted and bottles.size() == wanted
