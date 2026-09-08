extends CanvasLayer

@onready var container: HBoxContainer = $HBoxContainer

func _ready() -> void:
	if container:
		container.position = Vector2(16, 16)
		container.add_theme_constant_override("separation", 6)

func setup_slots(slot_count: int) -> void:
	if not container:
		container = $HBoxContainer

	for child in container.get_children():
		child.queue_free()

	for i in range(slot_count):
		var slot: PanelContainer = PanelContainer.new()
		slot.custom_minimum_size = Vector2(48, 48)

		# Box Styling
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.16, 0.85)
		style.border_color = Color(0.4, 0.4, 0.45, 1.0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		slot.add_theme_stylebox_override("panel", style)

		# 1. The Block Icon (Replaces the text name)
		var icon_rect: TextureRect = TextureRect.new()
		icon_rect.name = "IconRect"
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(32, 32)
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# 2. The Item Count (Bottom Right)
		var count_label: Label = Label.new()
		count_label.name = "CountLabel"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.add_theme_font_size_override("font_size", 14)

		# 3. The Slot Number (Top Left)
		var index_label: Label = Label.new()
		index_label.name = "IndexLabel"
		index_label.text = str(i + 1)
		index_label.modulate = Color(0.7, 0.7, 0.7, 0.6)
		index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		index_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		index_label.add_theme_font_size_override("font_size", 12)

		slot.add_child(icon_rect)
		slot.add_child(count_label)
		slot.add_child(index_label)
		container.add_child(slot)

func update_slot_display(inventory: Array, active_index: int) -> void:
	if not container:
		return

	# Dynamically fetch the tileset texture and size from the World
	var tile_map: TileMapLayer = get_tree().root.find_child("TileMapLayer", true, false)
	var base_tex: Texture2D = null
	var t_size: Vector2i = Vector2i(16, 16) # Fallback size
	
	if is_instance_valid(tile_map) and tile_map.tile_set:
		t_size = tile_map.tile_set.tile_size
		# Get the first atlas source attached to your TileMap
		var source_id = tile_map.tile_set.get_source_id(0)
		var source = tile_map.tile_set.get_source(source_id) as TileSetAtlasSource
		if source:
			base_tex = source.texture

	# Update UI for all slots
	for i in range(container.get_child_count()):
		var slot: PanelContainer = container.get_child(i) as PanelContainer
		var count_lbl: Label = slot.get_node_or_null("CountLabel")
		var icon_rect: TextureRect = slot.get_node_or_null("IconRect")
		
		# Active slot highlighting
		var style: StyleBoxFlat = slot.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if i == active_index:
			style.border_color = Color(1.0, 0.85, 0.2, 1.0)
			style.set_border_width_all(3)
		else:
			style.border_color = Color(0.4, 0.4, 0.45, 1.0)
			style.set_border_width_all(2)
		slot.add_theme_stylebox_override("panel", style)

		# Populate item data
		if i < inventory.size() and inventory[i] != null:
			if icon_rect and base_tex:
				var coords: Vector2i = inventory[i]["atlas_coords"]
				var atlas_tex = AtlasTexture.new()
				atlas_tex.atlas = base_tex
				# Crop exactly to the tile coordinates
				atlas_tex.region = Rect2(coords.x * t_size.x, coords.y * t_size.y, t_size.x, t_size.y)
				icon_rect.texture = atlas_tex
			
			if count_lbl:
				count_lbl.text = str(inventory[i]["count"])
		else:
			# Empty slot
			if icon_rect:
				icon_rect.texture = null
			if count_lbl:
				count_lbl.text = ""
