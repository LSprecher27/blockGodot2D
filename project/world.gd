extends Node2D

const ITEM_DROP_SCENE: PackedScene = preload("res://item_drop.tscn")

const TILE_SIZE: int = 16
const SOURCE_ID: int = 13

# World Dimensions
const WORLD_WIDTH: int = 120
const WORLD_HEIGHT: int = 80
const SURFACE_LEVEL: int = 35

# Atlas Coordinates (Matching TileSet)
const TILE_GRASS: Vector2i = Vector2i(2, 0)
const TILE_DIRT: Vector2i = Vector2i(0, 0)
const TILE_STONE: Vector2i = Vector2i(1, 0)

const BLOCK_NAMES: Dictionary = {
	TILE_GRASS: "dirt",
	TILE_DIRT: "dirt",
	TILE_STONE: "stone"
}

# Scene Node References
@onready var tile_map: TileMapLayer = $TileMapLayer
@onready var back_wall_layer: TileMapLayer = get_node_or_null("BackWallLayer")
@onready var player: CharacterBody2D = $Player
@onready var preview_root: Node2D = $PlacementPreview
@onready var block_ghost: Sprite2D = $PlacementPreview/BlockGhost
@onready var selection_box: ReferenceRect = $PlacementPreview/SelectionBox

# Noise Generators
var surface_noise: FastNoiseLite = FastNoiseLite.new()
var cave_noise: FastNoiseLite = FastNoiseLite.new()

# --- CONTINUOUS MINING SYSTEM ---
var is_mining: bool = false
var mining_target_cell: Vector2i = Vector2i.ZERO
var mining_progress: float = 0.0
const BLOCK_BREAK_TIME: float = 0.35 # Time in seconds it takes to break one block

# --- DAMAGE OVERLAY ---
var damage_overlay: Sprite2D

func _ready() -> void:
	setup_noise()
	generate_world()
	spawn_player()
	
	if preview_root:
		preview_root.visible = false
	if selection_box:
		selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dynamically create the crack overlay sprite
	damage_overlay = Sprite2D.new()
	damage_overlay.texture = generate_crack_sheet()
	damage_overlay.hframes = 4
	damage_overlay.frame = 0
	damage_overlay.visible = false
	damage_overlay.z_index = 50 # Ensure it draws on top of blocks
	damage_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(damage_overlay)

func setup_noise() -> void:
	randomize()
	var world_seed: int = randi()

	surface_noise.seed = world_seed
	surface_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	surface_noise.frequency = 0.04

	cave_noise.seed = world_seed + 1
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cave_noise.frequency = 0.07

func generate_world() -> void:
	if not is_instance_valid(tile_map):
		return

	tile_map.clear()
	if is_instance_valid(back_wall_layer):
		back_wall_layer.clear()

	for x in range(WORLD_WIDTH):
		var height_offset: int = int(surface_noise.get_noise_1d(x) * 12.0)
		var ground_y: int = SURFACE_LEVEL + height_offset

		for y in range(ground_y, WORLD_HEIGHT):
			var cell: Vector2i = Vector2i(x, y)
			var depth: int = y - ground_y

			var is_cave: bool = cave_noise.get_noise_2d(x, y) > 0.32 and depth > 4

			if is_instance_valid(back_wall_layer) and depth > 2:
				back_wall_layer.set_cell(cell, SOURCE_ID, TILE_DIRT)

			if not is_cave:
				if depth == 0:
					tile_map.set_cell(cell, SOURCE_ID, TILE_GRASS)
				elif depth < 6:
					tile_map.set_cell(cell, SOURCE_ID, TILE_DIRT)
				else:
					tile_map.set_cell(cell, SOURCE_ID, TILE_STONE)

func spawn_player() -> void:
	if not is_instance_valid(player) or not is_instance_valid(tile_map):
		return

	var spawn_x: int = int(WORLD_WIDTH * 0.5)
	var height_offset: int = int(surface_noise.get_noise_1d(spawn_x) * 12.0)
	var spawn_y: int = (SURFACE_LEVEL + height_offset) - 3

	var spawn_pos: Vector2 = tile_map.to_global(tile_map.map_to_local(Vector2i(spawn_x, spawn_y)))
	player.global_position = spawn_pos

func _process(delta: float) -> void:
	update_placement_preview()
	process_mining(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_pos: Vector2 = get_global_mouse_position()
		var cell: Vector2i = tile_map.local_to_map(tile_map.to_local(mouse_pos))

		# Hold Left Click: Start/Stop continuous mining
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_mining = true
				mining_target_cell = cell
				mining_progress = 0.0
				if is_instance_valid(player) and player.has_method("start_mining"):
					player.start_mining()
			else:
				is_mining = false
				mining_progress = 0.0
				if damage_overlay:
					damage_overlay.visible = false
				if is_instance_valid(player) and player.has_method("stop_mining"):
					player.stop_mining()

		# Right Click: Place Block
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			place_tile(cell)

func process_mining(delta: float) -> void:
	if not is_mining or not is_instance_valid(tile_map):
		if damage_overlay:
			damage_overlay.visible = false
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	var hovered_cell: Vector2i = tile_map.local_to_map(tile_map.to_local(mouse_pos))

	# If mouse moves to a different block, reset the break timer
	if hovered_cell != mining_target_cell:
		mining_target_cell = hovered_cell
		mining_progress = 0.0

	var source_id: int = tile_map.get_cell_source_id(hovered_cell)
	if source_id != -1:
		mining_progress += delta
		
		# Update crack visual
		if damage_overlay:
			damage_overlay.visible = true
			damage_overlay.global_position = tile_map.to_global(tile_map.map_to_local(hovered_cell))
			
			# Calculate which of the 4 crack frames to show based on progress percentage
			var progress_percent: float = mining_progress / BLOCK_BREAK_TIME
			var stage: int = int(progress_percent * 4.0)
			damage_overlay.frame = clamp(stage, 0, 3)

		# Break block
		if mining_progress >= BLOCK_BREAK_TIME:
			mine_tile(hovered_cell)
			mining_progress = 0.0
			if damage_overlay:
				damage_overlay.visible = false
	else:
		if damage_overlay:
			damage_overlay.visible = false

func mine_tile(cell: Vector2i) -> void:
	if not is_instance_valid(tile_map):
		return

	var source_id: int = tile_map.get_cell_source_id(cell)
	if source_id != -1:
		var atlas_coords: Vector2i = tile_map.get_cell_atlas_coords(cell)
		tile_map.set_cell(cell, -1)
		spawn_item_drop(cell, atlas_coords)

func place_tile(cell: Vector2i) -> void:
	if not is_instance_valid(tile_map) or not is_instance_valid(player):
		return

	if tile_map.get_cell_source_id(cell) != -1:
		return

	var active_item = null
	if player.has_method("get_active_item"):
		active_item = player.get_active_item()

	if active_item == null:
		return

	var cell_local_center: Vector2 = tile_map.map_to_local(cell)
	var cell_top_left: Vector2 = tile_map.to_global(cell_local_center) - Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
	var tile_box: Rect2 = Rect2(cell_top_left, Vector2(TILE_SIZE, TILE_SIZE))
	var player_box: Rect2 = Rect2(player.global_position - Vector2(5, 16), Vector2(10, 32))

	if player_box.intersects(tile_box):
		return

	var place_coords: Vector2i = active_item["atlas_coords"]
	tile_map.set_cell(cell, SOURCE_ID, place_coords)

	if player.has_method("consume_active_item"):
		player.consume_active_item()

func spawn_item_drop(cell: Vector2i, atlas_coords: Vector2i) -> void:
	if not ITEM_DROP_SCENE:
		return

	var drop = ITEM_DROP_SCENE.instantiate()
	drop.global_position = tile_map.to_global(tile_map.map_to_local(cell))

	var item_name: String = BLOCK_NAMES.get(atlas_coords, "dirt")
	var drop_coords: Vector2i = TILE_DIRT if atlas_coords == TILE_GRASS else atlas_coords

	var tile_set_atlas: TileSetAtlasSource = tile_map.tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	var tex: Texture2D = tile_set_atlas.texture if tile_set_atlas else null

	add_child(drop)
	drop.setup(item_name, drop_coords, tex, TILE_SIZE, player)

func update_placement_preview() -> void:
	if not is_instance_valid(player) or not is_instance_valid(tile_map) or not preview_root:
		if preview_root:
			preview_root.visible = false
		return

	var active_item = null
	if player.has_method("get_active_item"):
		active_item = player.get_active_item()

	if active_item == null:
		preview_root.visible = false
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	var hovered_cell: Vector2i = tile_map.local_to_map(tile_map.to_local(mouse_pos))

	var current_tile_size: Vector2i = Vector2i(TILE_SIZE, TILE_SIZE)
	if tile_map.tile_set:
		current_tile_size = tile_map.tile_set.tile_size

	var cell_local_center: Vector2 = tile_map.map_to_local(hovered_cell)
	var cell_top_left: Vector2 = tile_map.to_global(cell_local_center) - Vector2(current_tile_size.x * 0.5, current_tile_size.y * 0.5)
	preview_root.global_position = cell_top_left
	preview_root.visible = true

	if selection_box:
		selection_box.size = Vector2(current_tile_size)
		selection_box.custom_minimum_size = Vector2(current_tile_size)

	var is_occupied: bool = tile_map.get_cell_source_id(hovered_cell) != -1
	var player_box: Rect2 = Rect2(player.global_position - Vector2(5, 16), Vector2(10, 32))
	var tile_box: Rect2 = Rect2(cell_top_left, Vector2(current_tile_size))
	var overlaps_player: bool = player_box.intersects(tile_box)
	var can_place: bool = not is_occupied and not overlaps_player

	if selection_box:
		selection_box.border_color = Color(0.2, 1.0, 0.2, 0.9) if can_place else Color(1.0, 0.2, 0.2, 0.7)

	if block_ghost and tile_map.tile_set:
		var coords: Vector2i = active_item["atlas_coords"]
		var source: TileSetAtlasSource = tile_map.tile_set.get_source(SOURCE_ID) as TileSetAtlasSource

		if source and source.texture:
			block_ghost.texture = source.texture
			block_ghost.region_enabled = true
			block_ghost.region_rect = Rect2(coords.x * current_tile_size.x, coords.y * current_tile_size.y, current_tile_size.x, current_tile_size.y)
			block_ghost.modulate = Color(1.0, 1.0, 1.0, 0.5) if can_place else Color(1.0, 0.3, 0.3, 0.3)

# --- PROCEDURAL CRACK TEXTURE GENERATOR ---
func generate_crack_sheet() -> ImageTexture:
	var img: Image = Image.create(64, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0)) # Fully transparent base

	var c: Color = Color(0.1, 0.1, 0.1, 0.8) # Dark grey semi-transparent cracks

	# Stage 1 cracks (Light)
	var p1: Array = [
		Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2),
		Vector2i(15, 14), Vector2i(14, 13)
	]
	
	# Stage 2 cracks (Medium)
	var p2: Array = p1 + [
		Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 4), Vector2i(4, 5),
		Vector2i(13, 12), Vector2i(12, 11), Vector2i(11, 11), Vector2i(11, 10),
		Vector2i(15, 2), Vector2i(14, 3)
	]
	
	# Stage 3 cracks (Heavy)
	var p3: Array = p2 + [
		Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 8),
		Vector2i(9, 8), Vector2i(10, 9), Vector2i(13, 5), Vector2i(12, 6),
		Vector2i(11, 6), Vector2i(10, 7), Vector2i(1, 14), Vector2i(2, 13),
		Vector2i(3, 13), Vector2i(4, 12)
	]

	# Frame 0 is left empty (x offset 0)
	
	# Draw Frame 1 (x offset 16)
	for p in p1: img.set_pixel(16 + p.x, p.y, c)
	
	# Draw Frame 2 (x offset 32)
	for p in p2: img.set_pixel(32 + p.x, p.y, c)
	
	# Draw Frame 3 (x offset 48)
	for p in p3: img.set_pixel(48 + p.x, p.y, c)

	return ImageTexture.create_from_image(img)
