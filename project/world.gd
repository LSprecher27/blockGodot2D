extends Node2D

@onready var tile_map: TileMapLayer = $TileMapLayer
@onready var back_wall_layer: TileMapLayer = $BackWallLayer
@onready var player: CharacterBody2D = $Player
@onready var crack_overlay: AnimatedSprite2D = $CrackOverlay

const ITEM_DROP_SCENE = preload("res://item_drop.tscn")

const TILE_SIZE: int = 16
const CHUNK_WIDTH: int = 16
const CHUNK_HEIGHT: int = 80
const LOAD_DISTANCE: int = 3
const MINING_REACH: float = 120.0

const SOURCE_ID: int = 13
const TILE_GRASS: Vector2i = Vector2i(2, 0)
const TILE_DIRT: Vector2i = Vector2i(0, 0)
const TILE_STONE: Vector2i = Vector2i(1, 0)

const WALL_DIRT: Vector2i = Vector2i(0, 0)
const WALL_STONE: Vector2i = Vector2i(1, 0)

const BLOCK_DURABILITY: Dictionary = {
	TILE_GRASS: 3.0,
	TILE_DIRT: 3.0,
	TILE_STONE: 15.0
}

# Mapping tiles to drop names
const BLOCK_NAMES: Dictionary = {
	TILE_GRASS: "dirt", # Breaking grass drops dirt like Terraria/Minecraft
	TILE_DIRT: "dirt",
	TILE_STONE: "stone"
}

var current_tool_power: float = 10.0
var block_damage_map: Dictionary = {}
var current_target_cell: Vector2i = Vector2i(-999999, -999999)

const GRASS_TICK_RATE: float = 0.5
const SPREAD_ATTEMPTS: int = 10
var grass_tick_timer: float = 0.0

var surface_noise: FastNoiseLite = FastNoiseLite.new()
var cave_noise: FastNoiseLite = FastNoiseLite.new()

const CAVE_START_DEPTH: int = 8
const CAVE_THRESHOLD: float = 0.28

var loaded_chunks: Dictionary = {}

func _ready() -> void:
	surface_noise.seed = randi()
	surface_noise.frequency = 0.03
	surface_noise.noise_type = FastNoiseLite.TYPE_PERLIN

	cave_noise.seed = randi()
	cave_noise.frequency = 0.05
	cave_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	cave_noise.fractal_octaves = 3
	cave_noise.fractal_gain = 0.5

	if is_instance_valid(crack_overlay):
		crack_overlay.visible = false
		var frame_tex: Texture2D = crack_overlay.sprite_frames.get_frame_texture("default", 0)
		if frame_tex:
			var tex_size: Vector2 = frame_tex.get_size()
			crack_overlay.scale = Vector2(float(TILE_SIZE) / tex_size.x, float(TILE_SIZE) / tex_size.y)

	update_chunks_around_player()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	update_chunks_around_player()
	handle_continuous_mining(delta)
	update_grass_growth(delta)

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(player):
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var active_item = player.get_active_item()
		if active_item != null:
			var mouse_pos: Vector2 = get_global_mouse_position()
			if player.global_position.distance_to(mouse_pos) <= MINING_REACH:
				var cell: Vector2i = tile_map.local_to_map(tile_map.to_local(mouse_pos))
				
				# Only place if empty AND connected to terrain/wall
				if tile_map.get_cell_source_id(cell) == -1 and can_place_at(cell):
					tile_map.set_cell(cell, SOURCE_ID, active_item["atlas_coords"])
					player.consume_active_item()

# Check if target cell touches an existing block or sits on a back wall
func can_place_at(cell: Vector2i) -> bool:
	# Check adjacent orthogonal neighbors (Left, Right, Up, Down)
	var neighbors: Array[Vector2i] = [
		cell + Vector2i.LEFT,
		cell + Vector2i.RIGHT,
		cell + Vector2i.UP,
		cell + Vector2i.DOWN
	]
	for n in neighbors:
		if tile_map.get_cell_source_id(n) != -1:
			return true

	# Allow placement if placed in front of an underground back wall
	if is_instance_valid(back_wall_layer) and back_wall_layer.get_cell_source_id(cell) != -1:
		return true

	return false

func handle_continuous_mining(delta: float) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse_pos: Vector2 = get_global_mouse_position()

		if player.global_position.distance_to(mouse_pos) > MINING_REACH:
			reset_mining_target()
			return

		var target_cell: Vector2i = tile_map.local_to_map(tile_map.to_local(mouse_pos))
		var atlas_coords: Vector2i = tile_map.get_cell_atlas_coords(target_cell)

		if BLOCK_DURABILITY.has(atlas_coords):
			var max_health: float = BLOCK_DURABILITY[atlas_coords]

			if target_cell != current_target_cell:
				current_target_cell = target_cell
				if not block_damage_map.has(target_cell):
					block_damage_map[target_cell] = max_health

			block_damage_map[target_cell] -= current_tool_power * delta
			var current_health: float = block_damage_map[target_cell]

			update_crack_overlay(target_cell, current_health, max_health)

			if current_health <= 0.0:
				spawn_item_drop(target_cell, atlas_coords)
				tile_map.set_cell(target_cell, -1)
				block_damage_map.erase(target_cell)
				reset_mining_target()
		else:
			reset_mining_target()
	else:
		reset_mining_target()

func spawn_item_drop(cell: Vector2i, atlas_coords: Vector2i) -> void:
	var drop = ITEM_DROP_SCENE.instantiate()
	drop.global_position = tile_map.to_global(tile_map.map_to_local(cell))
	
	var item_name: String = BLOCK_NAMES.get(atlas_coords, "dirt")
	var drop_coords: Vector2i = TILE_DIRT if atlas_coords == TILE_GRASS else atlas_coords
	
	var tile_set_atlas: TileSetAtlasSource = tile_map.tile_set.get_source(SOURCE_ID) as TileSetAtlasSource
	var tex: Texture2D = tile_set_atlas.texture if tile_set_atlas else null

	add_child(drop)
	drop.setup(item_name, drop_coords, tex, TILE_SIZE, player)

func update_crack_overlay(cell: Vector2i, current_hp: float, max_hp: float) -> void:
	if not is_instance_valid(crack_overlay):
		return

	crack_overlay.visible = true
	crack_overlay.global_position = tile_map.to_global(tile_map.map_to_local(cell))

	var total_frames: int = crack_overlay.sprite_frames.get_frame_count("default")
	if total_frames > 0:
		var progress: float = clamp(1.0 - (current_hp / max_hp), 0.0, 1.0)
		var target_frame: int = int(progress * total_frames)
		crack_overlay.frame = clamp(target_frame, 0, total_frames - 1)

func reset_mining_target() -> void:
	current_target_cell = Vector2i(-999999, -999999)
	if is_instance_valid(crack_overlay):
		crack_overlay.visible = false

func update_chunks_around_player() -> void:
	var player_chunk_x: int = int(floor(player.global_position.x / (CHUNK_WIDTH * TILE_SIZE)))

	for cx in range(player_chunk_x - LOAD_DISTANCE, player_chunk_x + LOAD_DISTANCE + 1):
		if not loaded_chunks.has(cx):
			generate_chunk(cx)

func generate_chunk(chunk_x: int) -> void:
	var start_x: int = chunk_x * CHUNK_WIDTH

	for x in range(CHUNK_WIDTH):
		var world_x: int = start_x + x
		var height_sample: float = surface_noise.get_noise_1d(world_x)
		var surface_y: int = int(height_sample * 12) + 20

		for y in range(surface_y, surface_y + CHUNK_HEIGHT):
			var cell: Vector2i = Vector2i(world_x, y)

			var is_cave: bool = false
			if y > surface_y + CAVE_START_DEPTH:
				var c_sample: float = cave_noise.get_noise_2d(world_x, y)
				if c_sample > CAVE_THRESHOLD:
					is_cave = true

			if y >= surface_y + 4 and is_instance_valid(back_wall_layer):
				var wall_tile: Vector2i = WALL_DIRT if y < surface_y + 10 else WALL_STONE
				back_wall_layer.set_cell(cell, SOURCE_ID, wall_tile)

			if is_cave:
				continue

			if y == surface_y:
				tile_map.set_cell(cell, SOURCE_ID, TILE_GRASS)
			elif y < surface_y + 6:
				tile_map.set_cell(cell, SOURCE_ID, TILE_DIRT)
			else:
				tile_map.set_cell(cell, SOURCE_ID, TILE_STONE)

	loaded_chunks[chunk_x] = true

func update_grass_growth(delta: float) -> void:
	grass_tick_timer += delta
	if grass_tick_timer < GRASS_TICK_RATE:
		return

	grass_tick_timer = 0.0

	var player_tile: Vector2i = tile_map.local_to_map(tile_map.to_local(player.global_position))
	var scan_radius_x: int = 30
	var scan_radius_y: int = 20

	for i in range(SPREAD_ATTEMPTS):
		var rx: int = randi_range(player_tile.x - scan_radius_x, player_tile.x + scan_radius_x)
		var ry: int = randi_range(player_tile.y - scan_radius_y, player_tile.y + scan_radius_y)
		var cell: Vector2i = Vector2i(rx, ry)

		if tile_map.get_cell_atlas_coords(cell) == TILE_DIRT:
			var cell_above: Vector2i = Vector2i(rx, ry - 1)
			if tile_map.get_cell_source_id(cell_above) == -1:
				tile_map.set_cell(cell, SOURCE_ID, TILE_GRASS)
