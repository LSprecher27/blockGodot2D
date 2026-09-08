extends CharacterBody2D

@onready var camera: Camera2D = $Camera2D
@onready var light: PointLight2D = $PointLight2D
@onready var sprite: Sprite2D = $Sprite2D # Change to AnimatedSprite2D if you use an animated player

const SPEED: float = 160.0
const JUMP_VELOCITY: float = -280.0
const FALL_GRAVITY_MULTIPLIER: float = 1.5

const ZOOM_STEP: float = 0.15
const MAX_ZOOM_IN: float = 3.0
var min_zoom_out: float = 1.0
var target_zoom: float = 1.0

# Cave lighting & shadow settings
const MAX_LIGHT_ENERGY: float = 1.2
var target_light_energy: float = 0.0

# Player shading: pure white outside, darkened underground
const SURFACE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const CAVE_SHADOW_COLOR: Color = Color(0.4, 0.4, 0.5, 1.0) # Deep cave tint
var target_player_color: Color = SURFACE_COLOR

var back_wall_layer: TileMapLayer

func _ready() -> void:
	min_zoom_out = camera.zoom.x
	target_zoom = min_zoom_out
	
	back_wall_layer = get_parent().get_node_or_null("BackWallLayer")
	if light:
		light.energy = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clamp(target_zoom + ZOOM_STEP, min_zoom_out, MAX_ZOOM_IN)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clamp(target_zoom - ZOOM_STEP, min_zoom_out, MAX_ZOOM_IN)

func _physics_process(delta: float) -> void:
	camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), 12.0 * delta)

	if not is_on_floor():
		var grav: Vector2 = get_gravity()
		if velocity.y > 0.0:
			velocity += grav * FALL_GRAVITY_MULTIPLIER * delta
		else:
			velocity += grav * delta

	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= 0.5

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction: float = Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 1.5)

	move_and_slide()
	update_cave_lighting(delta)

func update_cave_lighting(delta: float) -> void:
	# Default to surface appearance
	target_light_energy = 0.0
	target_player_color = SURFACE_COLOR

	if is_instance_valid(back_wall_layer):
		var tile_pos: Vector2i = back_wall_layer.local_to_map(back_wall_layer.to_local(global_position))
		
		# If inside cave/behind back wall
		if back_wall_layer.get_cell_source_id(tile_pos) != -1:
			target_light_energy = MAX_LIGHT_ENERGY
			target_player_color = CAVE_SHADOW_COLOR

	# Smoothly fade light intensity
	if is_instance_valid(light):
		light.energy = move_toward(light.energy, target_light_energy, 2.5 * delta)

	# Smoothly tint player sprite to blend into cave shadows
	if is_instance_valid(sprite):
		sprite.modulate = sprite.modulate.lerp(target_player_color, 4.0 * delta)
