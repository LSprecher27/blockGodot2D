extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

var item_name: String = "dirt"
var atlas_coords: Vector2i = Vector2i(1, 0)
var target_player: CharacterBody2D = null

var velocity_y: float = -60.0 # Initial pop upwards
var gravity: float = 380.0
var is_resting: bool = false
var can_pickup: bool = false
var float_offset: float = 0.0
var magnet_speed: float = 0.0

const MAGNET_DISTANCE: float = 120.0 # Pull starts from further away
const PICKUP_DISTANCE: float = 75.0  # Big enough to cover the 56px sprite offset!

func _ready() -> void:
	await get_tree().create_timer(0.2).timeout
	can_pickup = true

func setup(name_id: String, coords: Vector2i, tex: Texture2D, tile_size: int, player_ref: CharacterBody2D = null) -> void:
	item_name = name_id
	atlas_coords = coords
	target_player = player_ref

	if sprite and tex:
		sprite.texture = tex
		sprite.region_enabled = true
		sprite.region_rect = Rect2(coords.x * tile_size, coords.y * tile_size, tile_size, tile_size)
		sprite.scale = Vector2(0.55, 0.55)

func _process(delta: float) -> void:
	if not is_instance_valid(target_player):
		return

	var dist: float = global_position.distance_to(target_player.global_position)

	if can_pickup:
		# 1. Instant Collection Check
		if dist <= PICKUP_DISTANCE:
			if target_player.has_method("add_item"):
				if target_player.add_item(item_name, atlas_coords, 1):
					queue_free()
			return

		# 2. Magnet Suction
		if dist <= MAGNET_DISTANCE:
			is_resting = false
			magnet_speed = move_toward(magnet_speed, 480.0, 950.0 * delta)
			var dir: Vector2 = (target_player.global_position - global_position).normalized()
			global_position += dir * magnet_speed * delta
			return

	# 3. Gravity and Floor Snapping
	var tile_map: TileMapLayer = get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	
	if is_resting:
		# Terraria hover bobbing
		float_offset += delta * 4.0
		if sprite:
			sprite.position.y = sin(float_offset) * 1.5

		# Fall if floor is mined
		if is_instance_valid(tile_map):
			var check_cell: Vector2i = tile_map.local_to_map(tile_map.to_local(global_position + Vector2(0, 10)))
			if tile_map.get_cell_source_id(check_cell) == -1:
				is_resting = false
				if sprite:
					sprite.position.y = 0.0
		return

	velocity_y += gravity * delta
	global_position.y += velocity_y * delta

	# Snap to tile surface
	if is_instance_valid(tile_map):
		var check_cell: Vector2i = tile_map.local_to_map(tile_map.to_local(global_position + Vector2(0, 6)))
		if tile_map.get_cell_source_id(check_cell) != -1:
			var cell_world_y: float = tile_map.to_global(tile_map.map_to_local(check_cell)).y
			global_position.y = cell_world_y - 12.0
			velocity_y = 0.0
			is_resting = true 
