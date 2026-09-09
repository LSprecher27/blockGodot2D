extends CharacterBody2D

@onready var camera: Camera2D = $Camera2D
@onready var light: PointLight2D = $PointLight2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var held_item_sprite: Sprite2D = $HeldItemSprite

const SPEED: float = 160.0
const JUMP_VELOCITY: float = -280.0
const FALL_GRAVITY_MULTIPLIER: float = 1.5

const ZOOM_STEP: float = 0.15
const MAX_ZOOM_IN: float = 3.0
var min_zoom_out: float = 1.0
var target_zoom: float = 1.0

const MAX_LIGHT_ENERGY: float = 1.2
var target_light_energy: float = 0.0
const SURFACE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const CAVE_SHADOW_COLOR: Color = Color(0.4, 0.4, 0.5, 1.0)
var target_player_color: Color = SURFACE_COLOR

var back_wall_layer: TileMapLayer
var tile_map_layer: TileMapLayer

# --- ANIMATION & MINING STATE ---
var anim_timer: float = 0.0
var idle_timer: float = 0.0
var walk_frame: int = 2
var is_mining: bool = false
var mining_timer: float = 0.0
const MAX_MINING_RANGE_TILES: int = 2

# --- INVENTORY ---
const INVENTORY_SIZE: int = 5
var inventory: Array = []
var active_slot: int = 0
var hotbar_ui: CanvasLayer

func _ready() -> void:
	add_to_group("player")
	
	if sprite:
		sprite.texture = generate_animated_character_sheet()
		sprite.region_enabled = false
		sprite.hframes = 7
		sprite.vframes = 1
		sprite.frame = 0
		sprite.scale = Vector2(1.0, 1.0)
		sprite.position = Vector2.ZERO
		sprite.centered = true

	if camera:
		min_zoom_out = camera.zoom.x
		target_zoom = min_zoom_out
	
	back_wall_layer = get_parent().get_node_or_null("BackWallLayer")
	tile_map_layer = get_parent().get_node_or_null("TileMapLayer")
	
	inventory.clear()
	for i in range(INVENTORY_SIZE):
		inventory.append(null)

	if light:
		light.energy = 0.0

	hotbar_ui = get_parent().get_node_or_null("HotbarUI")
	if not hotbar_ui:
		hotbar_ui = get_tree().root.find_child("HotbarUI", true, false)

	if hotbar_ui and hotbar_ui.has_method("setup_slots"):
		hotbar_ui.setup_slots(INVENTORY_SIZE)
		hotbar_ui.update_slot_display(inventory, active_slot)

	update_held_item_display()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clamp(target_zoom + ZOOM_STEP, min_zoom_out, MAX_ZOOM_IN)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clamp(target_zoom - ZOOM_STEP, min_zoom_out, MAX_ZOOM_IN)

	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			active_slot = event.keycode - KEY_1
			if hotbar_ui and hotbar_ui.has_method("update_slot_display"):
				hotbar_ui.update_slot_display(inventory, active_slot)
			update_held_item_display()

func update_held_item_display() -> void:
	if not held_item_sprite:
		return

	var active_item = get_active_item()
	if active_item == null:
		held_item_sprite.visible = false
		held_item_sprite.texture = null
		return

	if not is_instance_valid(tile_map_layer):
		tile_map_layer = get_parent().get_node_or_null("TileMapLayer")
		if not tile_map_layer:
			tile_map_layer = get_tree().root.find_child("TileMapLayer", true, false)

	if is_instance_valid(tile_map_layer) and tile_map_layer.tile_set:
		var t_size: Vector2i = tile_map_layer.tile_set.tile_size
		var source_id: int = tile_map_layer.tile_set.get_source_id(0)
		var source: TileSetAtlasSource = tile_map_layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if source and source.texture:
			var coords: Vector2i = active_item["atlas_coords"]
			var atlas_tex: AtlasTexture = AtlasTexture.new()
			atlas_tex.atlas = source.texture
			atlas_tex.region = Rect2(coords.x * t_size.x, coords.y * t_size.y, t_size.x, t_size.y)
			
			held_item_sprite.texture = atlas_tex
			held_item_sprite.visible = true

func _physics_process(delta: float) -> void:
	if camera:
		camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), 12.0 * delta)

	# Gravity
	if not is_on_floor():
		var grav: Vector2 = get_gravity()
		if grav == Vector2.ZERO:
			grav = Vector2(0, 700.0)
			
		if velocity.y > 0.0:
			velocity += grav * FALL_GRAVITY_MULTIPLIER * delta
		else:
			velocity += grav * delta

	# Jump
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Movement
	var direction: float = Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = direction * SPEED
		if not is_mining and sprite:
			sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 1.5)

	move_and_slide()
	update_cave_lighting(delta)
	handle_animations(delta, direction)
	update_held_item_position()

# --- MINING & RANGE CHECKS ---
func start_mining(target_pos: Vector2 = Vector2.INF) -> bool:
	if target_pos != Vector2.INF and not is_position_in_range(target_pos):
		stop_mining()
		return false

	is_mining = true
	mining_timer = 0.0
	return true

func stop_mining() -> void:
	is_mining = false
	mining_timer = 0.0

func is_tile_in_range(target_tile: Vector2i) -> bool:
	if not is_instance_valid(tile_map_layer):
		tile_map_layer = get_parent().get_node_or_null("TileMapLayer")
		if not is_instance_valid(tile_map_layer):
			tile_map_layer = get_tree().root.find_child("TileMapLayer", true, false)
			if not is_instance_valid(tile_map_layer):
				return false

	var player_tile: Vector2i = tile_map_layer.local_to_map(tile_map_layer.to_local(global_position))
	var diff: Vector2i = (target_tile - player_tile).abs()
	return diff.x <= MAX_MINING_RANGE_TILES and diff.y <= MAX_MINING_RANGE_TILES

func is_position_in_range(target_pos: Vector2) -> bool:
	if not is_instance_valid(tile_map_layer):
		tile_map_layer = get_parent().get_node_or_null("TileMapLayer")
		if not is_instance_valid(tile_map_layer):
			tile_map_layer = get_tree().root.find_child("TileMapLayer", true, false)
			if not is_instance_valid(tile_map_layer):
				return false

	var target_tile: Vector2i = tile_map_layer.local_to_map(tile_map_layer.to_local(target_pos))
	return is_tile_in_range(target_tile)

func update_held_item_position() -> void:
	if not held_item_sprite or not held_item_sprite.visible or not sprite:
		return

	var facing_left: bool = sprite.flip_h
	held_item_sprite.flip_h = facing_left
	var sign_x: float = -1.0 if facing_left else 1.0

	match sprite.frame:
		0: held_item_sprite.position = Vector2(5.0 * sign_x, 2.0)
		1: held_item_sprite.position = Vector2(5.0 * sign_x, 3.0)
		2: held_item_sprite.position = Vector2(6.0 * sign_x, 1.0)
		3: held_item_sprite.position = Vector2(5.0 * sign_x, 2.0)
		4: held_item_sprite.position = Vector2(4.0 * sign_x, 1.0)
		5: held_item_sprite.position = Vector2(4.0 * sign_x, -7.0)
		6: held_item_sprite.position = Vector2(7.0 * sign_x, -1.0)

func handle_animations(delta: float, direction: float) -> void:
	if not sprite:
		return

	# 1. Mining Animation
	if is_mining:
		var mouse_pos: Vector2 = get_global_mouse_position()
		
		# Automatically stop mining animation if cursor or player moves out of range
		if not is_position_in_range(mouse_pos):
			stop_mining()
		else:
			mining_timer += delta * 12.0
			sprite.flip_h = mouse_pos.x < global_position.x
			sprite.frame = 5 + (int(mining_timer) % 2)
			return

	# 2. Airborne Pose
	if not is_on_floor():
		sprite.frame = 3
		return

	# 3. Walking vs Idle
	if abs(direction) > 0.1:
		anim_timer += delta * 10.0
		if anim_timer >= 1.0:
			anim_timer = 0.0
			walk_frame += 1
			if walk_frame > 4:
				walk_frame = 2
		sprite.frame = walk_frame
		idle_timer = 0.0
	else:
		idle_timer += delta * 2.2
		sprite.frame = int(idle_timer) % 2
		anim_timer = 0.0

func generate_animated_character_sheet() -> ImageTexture:
	var frame_w: int = 16
	var frame_h: int = 32
	var total_frames: int = 7
	var img: Image = Image.create(frame_w * total_frames, frame_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var c_outline: Color = Color("#0a0a0c")
	var c_hair: Color = Color("#1a161b")
	var c_suit: Color = Color("#202127")
	var c_highlight: Color = Color("#343640")
	var c_shirt: Color = Color("#e6e8ec")
	var c_skin: Color = Color("#d49b72")
	var _c_shadow: Color = Color("#ab734e")
	var c_steel: Color = Color("#c7ccd6")
	var c_wood: Color = Color("#8a5833")

	for f in range(total_frames):
		var ox: int = f * frame_w
		var head_y_offset: int = 1 if f == 1 else 0

		# Hair & Head
		for y in range(0, 3):
			for x in range(5, 11):
				img.set_pixel(ox + x, y + head_y_offset, c_hair)
		for x in range(5, 11):
			img.set_pixel(ox + x, head_y_offset, c_outline)

		# Face & Eyes
		for y in range(3, 6):
			img.set_pixel(ox + 5, y + head_y_offset, c_hair)
			for x in range(6, 10):
				img.set_pixel(ox + x, y + head_y_offset, c_skin)
			img.set_pixel(ox + 10, y + head_y_offset, c_hair)
		img.set_pixel(ox + 6, 4 + head_y_offset, c_outline)
		img.set_pixel(ox + 9, 4 + head_y_offset, c_outline)

		# Beard & Chin
		for y in range(6, 8):
			for x in range(5, 11):
				img.set_pixel(ox + x, y + head_y_offset, c_hair)
		for x in range(6, 10):
			img.set_pixel(ox + x, 8 + head_y_offset, c_hair)

		# Shirt Collar & Tie
		for y in range(9, 11):
			img.set_pixel(ox + 4, y + head_y_offset, c_suit)
			img.set_pixel(ox + 5, y + head_y_offset, c_highlight)
			img.set_pixel(ox + 6, y + head_y_offset, c_shirt)
			img.set_pixel(ox + 7, y + head_y_offset, c_outline)
			img.set_pixel(ox + 8, y + head_y_offset, c_outline)
			img.set_pixel(ox + 9, y + head_y_offset, c_shirt)
			img.set_pixel(ox + 10, y + head_y_offset, c_highlight)
			img.set_pixel(ox + 11, y + head_y_offset, c_suit)

		# Torso
		for y in range(11, 19):
			var cur_y = clamp(y + head_y_offset, 0, 31)
			for x in range(5, 11):
				img.set_pixel(ox + x, cur_y, c_suit)
			img.set_pixel(ox + 7, cur_y, c_highlight)

		# Limbs by Frame
		match f:
			0: # Idle 1
				for y in range(11, 18):
					img.set_pixel(ox + 3, y, c_suit)
					img.set_pixel(ox + 12, y, c_suit)
				img.set_pixel(ox + 3, 18, c_skin)
				img.set_pixel(ox + 12, 18, c_skin)
				for y in range(19, 29):
					for x in range(5, 8): img.set_pixel(ox + x, y, c_suit)
					for x in range(8, 11): img.set_pixel(ox + x, y, c_suit)
					img.set_pixel(ox + 7, y, c_outline)
				for x in range(4, 12):
					img.set_pixel(ox + x, 29, c_hair)
					img.set_pixel(ox + x, 30, c_hair)
					img.set_pixel(ox + x, 31, c_outline)

			1: # Idle 2 (Breath Dip)
				for y in range(12, 19):
					img.set_pixel(ox + 3, y, c_suit)
					img.set_pixel(ox + 12, y, c_suit)
				img.set_pixel(ox + 3, 19, c_skin)
				img.set_pixel(ox + 12, 19, c_skin)
				for y in range(19, 29):
					for x in range(5, 8): img.set_pixel(ox + x, y, c_suit)
					for x in range(8, 11): img.set_pixel(ox + x, y, c_suit)
					img.set_pixel(ox + 7, y, c_outline)
				for x in range(4, 12):
					img.set_pixel(ox + x, 29, c_hair)
					img.set_pixel(ox + x, 30, c_hair)
					img.set_pixel(ox + x, 31, c_outline)

			2: # Walk 1
				for y in range(11, 17): img.set_pixel(ox + 4, y, c_suit)
				for y in range(10, 16): img.set_pixel(ox + 12, y, c_suit)
				img.set_pixel(ox + 4, 17, c_skin)
				img.set_pixel(ox + 12, 16, c_skin)
				for y in range(19, 28):
					for x in range(4, 7): img.set_pixel(ox + x, y, c_suit)
					for x in range(9, 12): img.set_pixel(ox + x, y, c_suit)
				for x in range(3, 7): img.set_pixel(ox + x, 29, c_hair)
				for x in range(9, 13): img.set_pixel(ox + x, 28, c_hair)

			3: # Walk 2
				for y in range(11, 18):
					img.set_pixel(ox + 3, y, c_suit)
					img.set_pixel(ox + 12, y, c_suit)
				img.set_pixel(ox + 3, 18, c_skin)
				img.set_pixel(ox + 12, 18, c_skin)
				for y in range(19, 28):
					for x in range(6, 10): img.set_pixel(ox + x, y, c_suit)
				for x in range(5, 11):
					img.set_pixel(ox + x, 29, c_hair)
					img.set_pixel(ox + x, 30, c_outline)

			4: # Walk 3
				for y in range(10, 16): img.set_pixel(ox + 3, y, c_suit)
				for y in range(11, 17): img.set_pixel(ox + 11, y, c_suit)
				img.set_pixel(ox + 3, 16, c_skin)
				img.set_pixel(ox + 11, 17, c_skin)
				for y in range(19, 28):
					for x in range(4, 7): img.set_pixel(ox + x, y, c_suit)
					for x in range(9, 12): img.set_pixel(ox + x, y, c_suit)
				for x in range(3, 7): img.set_pixel(ox + x, 28, c_hair)
				for x in range(9, 13): img.set_pixel(ox + x, 29, c_hair)

			5: # Mining Windup
				img.set_pixel(ox + 11, 10, c_suit)
				img.set_pixel(ox + 12, 9, c_suit)
				img.set_pixel(ox + 12, 8, c_skin)
				img.set_pixel(ox + 11, 7, c_wood)
				img.set_pixel(ox + 10, 6, c_wood)
				img.set_pixel(ox + 9, 5, c_steel)
				img.set_pixel(ox + 8, 5, c_steel)
				img.set_pixel(ox + 10, 5, c_steel)
				for y in range(12, 18): img.set_pixel(ox + 3, y, c_suit)
				img.set_pixel(ox + 3, 18, c_skin)
				for y in range(19, 29):
					for x in range(5, 11): img.set_pixel(ox + x, y, c_suit)
					img.set_pixel(ox + 7, y, c_outline)
				for x in range(4, 12):
					img.set_pixel(ox + x, 29, c_hair)
					img.set_pixel(ox + x, 31, c_outline)

			6: # Mining Strike
				img.set_pixel(ox + 11, 14, c_suit)
				img.set_pixel(ox + 12, 14, c_suit)
				img.set_pixel(ox + 13, 15, c_skin)
				img.set_pixel(ox + 13, 16, c_wood)
				img.set_pixel(ox + 14, 17, c_wood)
				img.set_pixel(ox + 15, 18, c_steel)
				img.set_pixel(ox + 15, 19, c_steel)
				img.set_pixel(ox + 14, 19, c_steel)
				for y in range(12, 18): img.set_pixel(ox + 3, y, c_suit)
				img.set_pixel(ox + 3, 18, c_skin)
				for y in range(19, 29):
					for x in range(5, 11): img.set_pixel(ox + x, y, c_suit)
					img.set_pixel(ox + 7, y, c_outline)
				for x in range(4, 12):
					img.set_pixel(ox + x, 29, c_hair)
					img.set_pixel(ox + x, 31, c_outline)

	return ImageTexture.create_from_image(img)

# --- INVENTORY HELPERS ---
func add_item(item_name: String, atlas_coords: Vector2i, count: int = 1) -> bool:
	if not hotbar_ui:
		hotbar_ui = get_parent().get_node_or_null("HotbarUI")
		if not hotbar_ui:
			hotbar_ui = get_tree().root.find_child("HotbarUI", true, false)

	for i in range(inventory.size()):
		if inventory[i] != null and inventory[i]["name"] == item_name:
			inventory[i]["count"] += count
			if hotbar_ui and hotbar_ui.has_method("update_slot_display"):
				hotbar_ui.update_slot_display(inventory, active_slot)
			update_held_item_display()
			return true

	for i in range(inventory.size()):
		if inventory[i] == null:
			inventory[i] = {
				"name": item_name,
				"atlas_coords": atlas_coords,
				"count": count
			}
			if hotbar_ui and hotbar_ui.has_method("update_slot_display"):
				hotbar_ui.update_slot_display(inventory, active_slot)
			update_held_item_display()
			return true

	return false

func get_active_item():
	if active_slot >= 0 and active_slot < inventory.size():
		return inventory[active_slot]
	return null

func consume_active_item() -> void:
	if active_slot >= 0 and active_slot < inventory.size() and inventory[active_slot] != null:
		inventory[active_slot]["count"] -= 1
		if inventory[active_slot]["count"] <= 0:
			inventory[active_slot] = null
		if hotbar_ui and hotbar_ui.has_method("update_slot_display"):
			hotbar_ui.update_slot_display(inventory, active_slot)
		update_held_item_display()

func update_cave_lighting(delta: float) -> void:
	target_light_energy = 0.0
	target_player_color = SURFACE_COLOR

	if is_instance_valid(back_wall_layer):
		var tile_pos: Vector2i = back_wall_layer.local_to_map(back_wall_layer.to_local(global_position))
		if back_wall_layer.get_cell_source_id(tile_pos) != -1:
			target_light_energy = MAX_LIGHT_ENERGY
			target_player_color = CAVE_SHADOW_COLOR

	if is_instance_valid(light):
		light.energy = move_toward(light.energy, target_light_energy, 2.5 * delta)

	if is_instance_valid(sprite):
		sprite.modulate = sprite.modulate.lerp(target_player_color, 4.0 * delta)
	if is_instance_valid(held_item_sprite):
		held_item_sprite.modulate = sprite.modulate
