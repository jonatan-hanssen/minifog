extends Control

signal on_m1_pressed(pressed: bool)
signal on_m2_pressed(pressed: bool)
signal on_mouse_pos_changed(position: Vector2)
signal brush_size_changed(size: int)
signal tool_changed(index: int)
signal selector_finished(start: Vector2, end: Vector2)
signal pretend_to_draw

enum tool { SQUARE_BRUSH, ROUND_BRUSH, SELECTOR, TOKEN_PLACER, POINTER, LENGTH }

const PerlinTexture = preload("res://resources/Fog.jpg")
const PlasmaTexture = preload("res://resources/Plasma.jpg")
const InfoDegus = preload("res://resources/Info.png")
const PlayerInfoDegus = preload("res://resources/PlayerInfo.png")
const Pointer = preload("res://resources/PointerIcon.png")
const BRUSH_SIZE_MIN := 5
const BRUSH_SIZE_MAX := 500
const UNDO_LIST_MAX := 200 # should not matter, we use very little ram
const MAX_IMAGE_SIZE := 3000.0
const CORNER_BASE_SIZE := 16
const FOG_SCALING: float = 1.2
const FOG_COLOR_LIST: Array = [
	Color.BURLYWOOD, # not actually used, stand in for fog
	Color.DEEP_PINK, # not actually used, stand in for colorful fog
	Color.BLACK,
	Color.WHITE,
	Color.DARK_GRAY,
	Color.FUCHSIA,
	Color.BLUE,
	Color.LIME,
]
const TOKEN_COLOR_LIST: Array = [
	[Color.GREEN, Color.DARK_GREEN, Color.WHITE],
	[Color.RED, Color.DARK_RED, Color.WHITE],
	[Color.BLUE, Color.DARK_BLUE, Color.WHITE],
	[Color.YELLOW, Color.GOLD, Color.BLACK],
	[Color.BLACK, Color.WHITE, Color.WHITE],
	[Color.WHITE, Color.BLACK, Color.BLACK],
]
const TOKEN_TOOLTIP_TEXT := "Hold left mouse to drag.\nPress left mouse to delete.\nType a number to change label."


# make the correct type
const ping_scene: PackedScene = preload("res://ping_effect.tscn")

var current_tool: int = 0
var fog_color_index: int = 0
var token_color_index: int = 0
var brush_size: int = 50
var fog_image_height: int
var fog_image_width: int
var last_brush_size: int = 50
var last_token_size: int = 50
var ctrl_held := false
var m1_held := false
var m2_held := false
var selecting := false
var hovering_over_menu := false
var hovering_over_sidebar := false
var performance_mode := false
var is_dirty := false
var prev_image: Image
var undo_list: Array = []
var corner_list: Array = []
var selector_start_pos := Vector2.ZERO
var selector_end_pos := Vector2.ZERO
var all_placed_tokens: Array[Dictionary] = []
var current_file_path: String
var mask_image_texture: Texture2D
var mask_texture: ImageTexture
var map_image: Image
var mask_image: Image
var light_brush: Image
var dark_brush: Image
var hovered_tokens: Dictionary[String, Panel] = { }
var held_tokens: Dictionary[String, Panel] = { }
var stylebox_button_pressed: StyleBox
var stylebox_button_not_pressed: StyleBox
var stylebox_cursor_normal: StyleBox
var button_list: Array

@onready var debug_text: TextEdit = $GUI/TextEdit
@onready var menu_bar: MenuBar = $GUI/MenuBar
@onready var file_menu: PopupMenu = $GUI/MenuBar/File
@onready var help_menu: PopupMenu = $GUI/MenuBar/Help
@onready var colorscheme_menu: PopupMenu = $GUI/MenuBar/Colorscheme
@onready var tool_sidebar: PanelContainer = $GUI/ToolContainer
@onready var scroll_sidebar: PanelContainer = $GUI/ScrollBarContainer
@onready var color_picker_container: PanelContainer = $GUI/ColorContainer
@onready var color_picker_vbox: VBoxContainer = $GUI/ColorContainer/VBoxContainer
@onready var scrollbar: VScrollBar = $GUI/ScrollBarContainer/VBoxContainer/VScrollBar
@onready var scrollbar_label: Label = $GUI/ScrollBarContainer/VBoxContainer/Label
@onready var square_brush_button: Button = $GUI/ToolContainer/VBoxContainer/SquareBrushButton
@onready var round_brush_button: Button = $GUI/ToolContainer/VBoxContainer/CircleBrushButton
@onready var selector_button: Button = $GUI/ToolContainer/VBoxContainer/SelectorButton
@onready var token_button: Button = $GUI/ToolContainer/VBoxContainer/TokenButton
@onready var pointer_button: Button = $GUI/ToolContainer/VBoxContainer/PointerButton
# @onready var separator : HSeparator = $GUI/ToolContainer/VBoxContainer/Separator
@onready var tool_label: Label = $GUI/ToolContainer/VBoxContainer/ToolLabel
@onready var load_dialog: FileDialog = $LoadDialog
@onready var save_dialog: FileDialog = $SaveDialog
@onready var warning: AcceptDialog = $Warning
@onready var cursor_node: Node2D = $CursorNode
@onready var cursor_panel: Panel = $CursorNode/Panel
@onready var drawing_viewport: SubViewport = $DrawingViewport
@onready var drawing_node: Node2D = $DrawingViewport/DrawingNode
@onready var drawing_texture: TextureRect = $DrawingViewport/DrawingTexture
@onready var dm_camera: Camera2D = $Camera
@onready var dm_fog: TextureRect = $DmFog
@onready var dm_root: Node2D = $DmRoot
@onready var dm_background: TextureRect = $DmRoot/Background
@onready var player_window: Window = $PlayerWindow
@onready var player_camera: Camera2D = $PlayerWindow/Camera
@onready var player_fog: TextureRect = $PlayerWindow/PlayerFog
@onready var player_root: Node2D = $PlayerWindow/PlayerRoot
@onready var player_background: TextureRect = $PlayerWindow/PlayerRoot/Background
@onready var player_pointer: Panel = $PlayerWindow/PlayerPointer
@onready var player_view: Panel = $PlayerViewRectangle
@onready var player_view_text: TextEdit = $PlayerViewRectangle/TextEdit



func _ready() -> void:
	debug_text.visible = false
	button_list = [
		[square_brush_button, "Square Brush"],
		[round_brush_button, "Round Brush"],
		[selector_button, "Selector"],
		[token_button, "Token Placer"],
		[pointer_button, "Pointer"],
	]

	make_button_styleboxes()
	connect_signals()
	make_pointer_red()
	populate_color_bar()

	scrollbar.set_value_no_signal(brush_size)

	select_tool(tool.SQUARE_BRUSH)

	load_dialog.add_filter("*.png, *.jpg, *.jpeg, *.map", "Images / .map files")
	save_dialog.add_filter("*.map", ".map files")
	update_brush_size(brush_size)

	cursor_panel.size = Vector2(brush_size, brush_size)

	get_window().title = "DM Window"
	var args: Array = OS.get_cmdline_args()

	if len(args) > 0:
		load_map(args[0])
	else:
		load_map("")


func make_pointer_red() -> void:
	var stylebox_cursor: StyleBox = player_pointer.get_theme_stylebox("panel").duplicate()
	stylebox_cursor.bg_color = Color.RED
	stylebox_cursor.border_color = Color.RED
	player_pointer.add_theme_stylebox_override("panel", stylebox_cursor)


func make_button_styleboxes() -> void:
	stylebox_button_pressed = selector_button.get_theme_stylebox("normal").duplicate()
	stylebox_button_pressed.border_width_left = 2
	stylebox_button_pressed.border_width_right = 2
	stylebox_button_pressed.border_width_top = 2
	stylebox_button_pressed.border_width_bottom = 2

	stylebox_button_not_pressed = selector_button.get_theme_stylebox("normal").duplicate()
	stylebox_button_not_pressed.border_width_left = 0
	stylebox_button_not_pressed.border_width_right = 0
	stylebox_button_not_pressed.border_width_top = 0
	stylebox_button_not_pressed.border_width_bottom = 0

	stylebox_cursor_normal = cursor_panel.get_theme_stylebox("panel").duplicate()
	stylebox_cursor_normal.corner_radius_top_left = 3
	stylebox_cursor_normal.corner_radius_top_right = 3
	stylebox_cursor_normal.corner_radius_bottom_left = 3
	stylebox_cursor_normal.corner_radius_bottom_right = 3
	stylebox_cursor_normal.bg_color = Color.TRANSPARENT
	stylebox_cursor_normal.border_color = Color.BLACK


func connect_signals() -> void:
	get_window().files_dropped.connect(func(paths: PackedStringArray) -> void: load_map(paths[0]))

	load_dialog.connect("file_selected", func(path: String) -> void: load_map(path))
	save_dialog.connect("file_selected", func(path: String) -> void: write_map(path))
	scrollbar.connect("value_changed", update_brush_size)

	file_menu.connect("id_pressed", _on_file_id_pressed)
	help_menu.connect("id_pressed", _on_help_id_pressed)
	colorscheme_menu.connect("id_pressed", update_colorscheme)


	for i in range(len(button_list)):
		var button: Button = button_list[i][0]
		var tool_name: String = button_list[i][1]

		button.connect("pressed", func() -> void: select_tool(i))
		button.connect("mouse_entered", func() -> void: tool_label.text = tool_name)
		button.connect("mouse_exited", func() -> void:
			update_tool_visuals()
			button.release_focus()
		)
	drawing_node.connect("on_finished_drawing", func() -> void:
		await RenderingServer.frame_post_draw
		copy_viewport_texture()
	)

	menu_bar.connect("mouse_entered", func() -> void: hovering_over_menu = true)
	menu_bar.connect("mouse_exited", func() -> void: hovering_over_menu = false)

	var sidebar_list: Array = [
		tool_sidebar,
		scroll_sidebar,
		scrollbar,
		square_brush_button,
		round_brush_button,
		selector_button,
		token_button,
		pointer_button,
		color_picker_container,
	]

	for i in range(len(sidebar_list)):
		sidebar_list[i].connect("mouse_entered", are_we_inside_sidebar)
		sidebar_list[i].connect("mouse_exited", func() -> void: hovering_over_sidebar = false)


func _process(_delta: float) -> void:
	# debug()
	move_player_view()
	update_cursor_position()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		process_keypresses(event)

	elif event is InputEventMouseButton:
		on_mouse_pos_changed.emit(get_global_mouse_position())

		# dont process clicks when over gui, but process releases
		if (hovering_over_menu or hovering_over_sidebar) and event.pressed:
			return


		match current_tool:
			tool.TOKEN_PLACER:
				if event.pressed:
					if event.button_index == MOUSE_BUTTON_LEFT:
						# make a token
						if hovered_tokens.is_empty():
							var tokens: Dictionary[String, Panel] = make_token()
							hovered_tokens = tokens
							cursor_node.visible = false
							set_cursor_shape(CursorShape.CURSOR_MOVE)
							add_to_undo_list(["place_token", { 'tokens': tokens }])
							is_dirty = true
							if len(undo_list) > UNDO_LIST_MAX:
								undo_list.pop_front()

						else:
							# move a token
							add_to_undo_list(["move_token", { 'tokens': hovered_tokens, 'position': hovered_tokens['dm'].position }])
							hovered_tokens['dm'].tooltip_text = ""
							is_dirty = true
							if len(undo_list) > UNDO_LIST_MAX:
								undo_list.pop_front()
							held_tokens = hovered_tokens
							held_tokens['dm'].mouse_default_cursor_shape = CursorShape.CURSOR_MOVE


					# delete a token
					if event.button_index == MOUSE_BUTTON_RIGHT and not hovered_tokens.is_empty():
						var dm_token: Panel = hovered_tokens['dm']
						var player_token: Panel = hovered_tokens['player']
						dm_token.visible = false
						player_token.visible = false
						add_to_undo_list(["remove_token", { 'tokens': { 'dm': dm_token, 'player': player_token } }])
						is_dirty = true
						if len(undo_list) > UNDO_LIST_MAX:
							undo_list.pop_front()

						hovered_tokens = { }

				# not pressed (released)
				else:
					if event.button_index == MOUSE_BUTTON_LEFT:
						# release held token
						if not held_tokens.is_empty():
							held_tokens['dm'].mouse_default_cursor_shape = CursorShape.CURSOR_POINTING_HAND
							held_tokens['dm'].tooltip_text = TOKEN_TOOLTIP_TEXT
							held_tokens = { }
							# get_viewport().gui_disable_tooltips = true

			tool.SELECTOR:
				if (
						event.button_index == MOUSE_BUTTON_LEFT
						or event.button_index == MOUSE_BUTTON_RIGHT
				):
					if event.pressed:
						selecting = true
						selector_start_pos = get_global_mouse_position()

					if event.pressed == false:
						if m1_held or m2_held:
							selecting = false
							selector_end_pos = get_global_mouse_position()
							selector_finished.emit(selector_start_pos, selector_end_pos)
					if event.button_index == MOUSE_BUTTON_LEFT:
						m1_held = event.pressed
						on_m1_pressed.emit(event.pressed)
					elif event.button_index == MOUSE_BUTTON_RIGHT:
						m2_held = event.pressed
						on_m2_pressed.emit(event.pressed)
					reshape_selector_cursor_panel()
			tool.POINTER:
				if event.pressed:
					if event.button_index == MOUSE_BUTTON_LEFT:
						var ping: Node2D = ping_scene.instantiate()
						ping.position = get_global_mouse_position()
						add_child(ping)
						# add it to player view too
						var ping_player: Node2D = ping_scene.instantiate()
						ping_player.position = get_global_mouse_position()
						player_window.add_child(ping_player)

			_:
				if event.button_index == MOUSE_BUTTON_LEFT:
					drawing_texture.visible = false

					if event.pressed == false and m1_held:
						copy_viewport_texture()
					m1_held = event.pressed
					on_m1_pressed.emit(event.pressed)

				if event.button_index == MOUSE_BUTTON_RIGHT:
					drawing_texture.visible = false

					if event.pressed == false and m2_held:
						copy_viewport_texture()

					m2_held = event.pressed
					on_m2_pressed.emit(event.pressed)

		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					set_cursor_shape(CursorShape.CURSOR_DRAG)
				else:
					update_tool_visuals()

			MOUSE_BUTTON_WHEEL_UP:
				if ctrl_held:
					update_brush_size(min(max(BRUSH_SIZE_MIN, brush_size - 5), BRUSH_SIZE_MAX))
					scrollbar.set_value_no_signal(brush_size)
			MOUSE_BUTTON_WHEEL_DOWN:
				if ctrl_held:
					update_brush_size(min(max(BRUSH_SIZE_MIN, brush_size + 5), BRUSH_SIZE_MAX))
					scrollbar.set_value_no_signal(brush_size)

	elif event is InputEventMouseMotion:
		on_mouse_pos_changed.emit(get_global_mouse_position())

		if m1_held or m2_held:
			drawing_texture.visible = false

		if hovered_tokens.is_empty():
			cursor_node.visible = true
			set_cursor_shape()

		match current_tool:
			tool.POINTER:
				player_pointer.position = get_global_mouse_position() - player_pointer.size / 2

			tool.TOKEN_PLACER:
				if not held_tokens.is_empty():
					held_tokens['dm'].position = get_global_mouse_position() - Vector2.ONE * held_tokens['dm'].size / 2
					held_tokens['player'].position = get_global_mouse_position() - Vector2.ONE * held_tokens['player'].size / 2

				if hovered_tokens.is_empty():
					cursor_node.visible = true
					set_cursor_shape()

				elif not m1_held and not m2_held:
					cursor_node.visible = false
					set_cursor_shape(CursorShape.CURSOR_POINTING_HAND)


func populate_color_bar() -> void:
	for i in range(len(TOKEN_COLOR_LIST)):
		var color_button: Button = Button.new()
		color_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		color_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		color_button.add_theme_color_override("font_color", TOKEN_COLOR_LIST[i][0])
		# override the stylebox to make it transparent, so we only see the text
		var stylebox: StyleBox = color_button.get_theme_stylebox("normal").duplicate()
		stylebox.bg_color = Color.TRANSPARENT
		color_button.add_theme_stylebox_override("normal", stylebox)

		# also override the pressed stylebox to make it transparent, so we only see the text
		var stylebox_pressed: StyleBox = color_button.get_theme_stylebox("pressed").duplicate()
		stylebox_pressed.bg_color = Color.TRANSPARENT
		color_button.add_theme_stylebox_override("pressed", stylebox_pressed)

		# make the font big
		color_button.add_theme_font_size_override("font_size", 24)
		color_button.add_theme_color_override("font_color_shadow", TOKEN_COLOR_LIST[i][1])
		color_button.text = "●"
		color_button.connect("mouse_entered", func() -> void: hovering_over_sidebar = true)
		color_button.connect("mouse_exited", func() -> void: hovering_over_sidebar = false)
		color_button.connect("mouse_entered", are_we_inside_sidebar)
		color_button.connect("mouse_exited", func() -> void: hovering_over_sidebar = false)
		color_button.connect(
			"pressed",
			func() -> void:
				token_color_index = i
				update_tool_visuals()
		)
		color_picker_vbox.add_child(color_button)


func update_cursor_position() -> void:
	if hovering_over_menu or hovering_over_sidebar:
		cursor_node.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if current_tool != tool.SELECTOR:
		if hovering_over_sidebar:
			cursor_node.position = dm_camera.position - Vector2.ONE * brush_size / 2
		else:
			cursor_node.position = get_global_mouse_position() - Vector2.ONE * brush_size / 2
	else:
		reshape_selector_cursor_panel()


func process_keypresses(event: InputEventKey) -> void:
	if event.keycode == KEY_CTRL:
		ctrl_held = event.pressed

	if event.pressed:
		if (not hovered_tokens.is_empty() or not held_tokens.is_empty()) and event.keycode in range(KEY_0, KEY_9 + 1):
			var active_tokens := held_tokens if not held_tokens.is_empty() else hovered_tokens
			var previous_number: String = active_tokens['dm'].get_child(0).text
			add_to_undo_list(['change_number', { 'tokens': active_tokens, 'number': previous_number }])
			is_dirty = true
			if len(undo_list) > UNDO_LIST_MAX:
				undo_list.pop_front()
			var number := str(event.keycode - KEY_0)
			active_tokens['dm'].get_child(0).text = number
			active_tokens['player'].get_child(0).text = number
			return

		match event.keycode:
			KEY_1:
				select_tool(tool.SQUARE_BRUSH)
			KEY_2:
				select_tool(tool.ROUND_BRUSH)
			KEY_3:
				select_tool(tool.SELECTOR)
			KEY_4:
				select_tool(tool.TOKEN_PLACER)
			KEY_5:
				select_tool(tool.POINTER)
			KEY_C:
				token_color_index = (token_color_index + 1) % len(TOKEN_COLOR_LIST)
				update_tool_visuals()
			KEY_Z:
				undo()
			KEY_SPACE:
				select_tool((current_tool + 1) % tool.LENGTH)
			KEY_T:
				var id: int = (fog_color_index + 1) % len(FOG_COLOR_LIST)
				update_colorscheme(id)
			KEY_P:
				performance_mode = not performance_mode
				if performance_mode:
					Engine.max_fps = 30
				else:
					Engine.max_fps = 60
			KEY_S:
				if ctrl_held:
					if current_file_path == "":
						warning.title = "Cannot save an empty map"
						warning.dialog_text = "Cannot save an empty map"
						warning.popup_centered()
					elif current_file_path.ends_with(".map"):
						set_cursor_shape(CursorShape.CURSOR_WAIT)
						get_window().title = "DM Window (saving...)"
						await get_tree().process_frame
						await get_tree().process_frame
						write_map(current_file_path)
						set_cursor_shape()
					else:
						save_dialog.popup()
			KEY_L:
				load_dialog.popup()
			KEY_K:
				# for tokens in all_placed_tokens:
				# 	if is_instance_valid(tokens['tokens']['dm']):
				# 		tokens[0]['dm'].visible = true
				# 		tokens[0]['player'].visible = true
				print(len(undo_list))
				serialize_tokens(all_placed_tokens)


func undo() -> void:
	if undo_list.is_empty():
		return

	var last: Array = undo_list.pop_back()

	var action: String = last[0]
	var payload: Variant = last[1]

	match action:
		"draw":
			pretend_to_draw.emit()

			var height: int = payload["size"].y
			var width: int = payload["size"].x
			var data: PackedByteArray = payload["data"]

			var uncompressed := data.decompress(
				height * width,
				FileAccess.COMPRESSION_ZSTD,
			)
			var image: = Image.create_from_data(
				width,
				height,
				false,
				Image.FORMAT_R8,
				uncompressed,
			)

			drawing_texture.texture = ImageTexture.create_from_image(image)
			drawing_texture.visible = true

			dm_fog.material.set_shader_parameter("mask_texture", drawing_viewport.get_texture())
			player_fog.material.set_shader_parameter("mask_texture", drawing_viewport.get_texture())

			prev_image = image

		"place_token":
			if not is_instance_valid(payload['tokens']['dm']):
				undo()
			else:
				payload['tokens']['dm'].queue_free()
				payload['tokens']['player'].queue_free()
		"remove_token":
			payload['tokens']['dm'].visible = true
			payload['tokens']['player'].visible = true
		"move_token":
			payload['tokens']['dm'].position = payload['position']
			payload['tokens']['player'].position = payload['position']
		"change_number":
			payload['tokens']['dm'].get_child(0).text = payload['number']
			payload['tokens']['player'].get_child(0).text = payload['number']


func make_token(pos: Vector2 = Vector2.INF, text: String = "", token_size_temp: int = -1, color_id: int = -1) -> Dictionary[String, Panel]:
	var token_dict: Dictionary[String, Panel] = { }

	var token_pos: Vector2
	if pos == Vector2.INF:
		token_pos = get_global_mouse_position() - Vector2.ONE * brush_size / 2
	else:
		token_pos = pos

	var token_size: int = brush_size if token_size_temp == -1 else token_size_temp
	var token_color_id: int = token_color_index if color_id == -1 else color_id
	var token_text: String = "1" if text == "" else text

	for i in range(2):
		var token := Panel.new()

		var label := Label.new()

		label.text = token_text
		label.set("theme_override_font_sizes/font_size", token_size / 2)
		# set the color of the label text
		label.add_theme_color_override("font_color", TOKEN_COLOR_LIST[token_color_id][2])

		label.size = Vector2(token_size, token_size)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		token.add_child(label)

		# token.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token.size = Vector2(token_size, token_size)
		token.position = token_pos
		token.z_index = -1

		var stylebox_cursor: StyleBox = cursor_panel.get_theme_stylebox("panel").duplicate()
		stylebox_cursor.corner_radius_top_left = token_size / 2 - 1
		stylebox_cursor.corner_radius_top_right = token_size / 2 - 1
		stylebox_cursor.corner_radius_bottom_left = token_size / 2 - 1
		stylebox_cursor.corner_radius_bottom_right = token_size / 2 - 1
		stylebox_cursor.corner_detail = 32
		stylebox_cursor.bg_color = TOKEN_COLOR_LIST[token_color_id][0]
		stylebox_cursor.border_color = TOKEN_COLOR_LIST[token_color_id][1]
		token.add_theme_stylebox_override("panel", stylebox_cursor)

		# token.mouse_default_cursor_shape = CursorShape.CURSOR_POINTING_HAND

		if i == 0:
			add_child(token)
			token_dict['dm'] = token
		else:
			player_window.add_child(token)
			token_dict['player'] = token

	token_dict['dm'].tooltip_text = TOKEN_TOOLTIP_TEXT
	token_dict['dm'].connect("mouse_entered", func() -> void: hovered_tokens = token_dict)
	token_dict['dm'].connect("mouse_exited", func() -> void: hovered_tokens = { })
	token_dict['player'].connect("mouse_entered", func() -> void: hovered_tokens = token_dict)
	token_dict['player'].connect("mouse_exited", func() -> void: hovered_tokens = { })

	all_placed_tokens.append({ 'tokens': token_dict, 'color_id': token_color_id })

	return token_dict


func update_brush_size(value: float) -> void:
	brush_size = int(value)
	brush_size_changed.emit(brush_size)

	scrollbar_label.text = str(int(value))

	if current_tool == tool.TOKEN_PLACER:
		last_token_size = brush_size
	else:
		last_brush_size = brush_size

	cursor_panel.size = Vector2(brush_size, brush_size)
	update_tool_visuals()


func set_cursor_shape(shape: CursorShape = CursorShape.CURSOR_ARROW) -> void:
	mouse_default_cursor_shape = shape
	cursor_panel.mouse_default_cursor_shape = shape
	player_view.mouse_default_cursor_shape = shape
	player_view_text.mouse_default_cursor_shape = shape


func move_player_view() -> void:
	var view_size: Vector2 = player_window.get_visible_rect().size
	var view_transform: Transform2D = player_window.get_canvas_transform()

	player_view.position = view_transform.origin / -view_transform.x[0]
	player_view.size = view_size / view_transform.x[0]


func reshape_selector_cursor_panel() -> void:
	if selecting:
		cursor_node.visible = true
	else:
		cursor_node.visible = false

	var mouse_pos: Vector2 = get_global_mouse_position()

	cursor_panel.size = (selector_start_pos - mouse_pos).abs()

	if mouse_pos.x >= selector_start_pos.x:
		cursor_node.position.x = selector_start_pos.x
	else:
		cursor_node.position.x = mouse_pos.x
	if mouse_pos.y >= selector_start_pos.y:
		cursor_node.position.y = selector_start_pos.y
	else:
		cursor_node.position.y = mouse_pos.y


func update_tool_visuals() -> void:
	# make all buttons unpressed
	for i in range(len(button_list)):
		button_list[i][0].add_theme_stylebox_override("normal", stylebox_button_not_pressed)

	cursor_node.visible = true

	tool_label.text = button_list[current_tool][1]

	scrollbar.set_value_no_signal(last_brush_size)
	brush_size = last_brush_size
	brush_size_changed.emit(brush_size)
	scrollbar_label.text = str(int(brush_size))

	color_picker_container.visible = current_tool == tool.TOKEN_PLACER
	scroll_sidebar.visible = (current_tool != tool.SELECTOR) and (current_tool != tool.POINTER)
	player_pointer.visible = current_tool == tool.POINTER
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if current_tool != tool.POINTER else Input.MOUSE_MODE_HIDDEN)

	match current_tool:
		tool.SQUARE_BRUSH:
			set_cursor_shape(CursorShape.CURSOR_CROSS)
			cursor_panel.add_theme_stylebox_override("panel", stylebox_cursor_normal)

			square_brush_button.add_theme_stylebox_override("normal", stylebox_button_pressed)
		tool.ROUND_BRUSH:
			set_cursor_shape(CursorShape.CURSOR_CROSS)
			var stylebox_cursor := make_circular_stylebox()
			stylebox_cursor.bg_color = Color.TRANSPARENT
			stylebox_cursor.border_color = Color.BLACK
			cursor_panel.add_theme_stylebox_override("panel", stylebox_cursor)

			round_brush_button.add_theme_stylebox_override("normal", stylebox_button_pressed)
		tool.SELECTOR:
			set_cursor_shape()
			cursor_panel.add_theme_stylebox_override("panel", stylebox_cursor_normal)

			selector_button.add_theme_stylebox_override("normal", stylebox_button_pressed)
			reshape_selector_cursor_panel()
		tool.TOKEN_PLACER:
			set_cursor_shape()

			scrollbar.set_value_no_signal(last_token_size)
			brush_size = last_token_size
			scrollbar_label.text = str(int(brush_size))

			var stylebox_cursor := make_circular_stylebox()
			stylebox_cursor.bg_color = TOKEN_COLOR_LIST[token_color_index][0]
			stylebox_cursor.border_color = TOKEN_COLOR_LIST[token_color_index][1]
			cursor_panel.add_theme_stylebox_override("panel", stylebox_cursor)

			token_button.add_theme_stylebox_override("normal", stylebox_button_pressed)

		tool.POINTER:
			player_pointer.visible = true

			var stylebox_cursor := make_circular_stylebox()
			stylebox_cursor.bg_color = Color.RED
			stylebox_cursor.border_color = Color.RED
			cursor_panel.add_theme_stylebox_override("panel", stylebox_cursor)

			brush_size = 10
			pointer_button.add_theme_stylebox_override("normal", stylebox_button_pressed)

	cursor_panel.size = Vector2(brush_size, brush_size)


func make_circular_stylebox() -> StyleBox:
	var stylebox: StyleBox = cursor_panel.get_theme_stylebox("panel").duplicate()
	stylebox.corner_detail = 32
	stylebox.corner_radius_top_left = brush_size / 2 - 1
	stylebox.corner_radius_top_right = brush_size / 2 - 1
	stylebox.corner_radius_bottom_left = brush_size / 2 - 1
	stylebox.corner_radius_bottom_right = brush_size / 2 - 1

	return stylebox


func copy_viewport_texture() -> void:
	var image: Image = drawing_viewport.get_texture().get_image()
	image.convert(Image.FORMAT_R8)
	var buffer: PackedByteArray = prev_image.get_data()
	var compressed: PackedByteArray = buffer.compress(FileAccess.COMPRESSION_ZSTD)
	add_to_undo_list(["draw", { "data": compressed, "size": prev_image.get_size() }])
	is_dirty = true
	prev_image = image


func update_fog_texture(color: Color) -> void:
	var fog_image_texture: Texture2D
	if color == Color.BURLYWOOD:
		fog_image_texture = PerlinTexture
		RenderingServer.set_default_clear_color(Color.WHITE)
	elif color == Color.DEEP_PINK:
		fog_image_texture = PlasmaTexture
		RenderingServer.set_default_clear_color(Color.WHITE)
	else:
		var fog_image: Image = Image.create(
			fog_image_width,
			fog_image_height,
			false,
			Image.FORMAT_RGBA8,
		)
		fog_image.fill(color)
		fog_image_texture = ImageTexture.create_from_image(fog_image)
		RenderingServer.set_default_clear_color(color)

	player_fog.texture = fog_image_texture
	dm_fog.texture = fog_image_texture


func get_fog_size(image_size: Vector2i) -> void:
	if image_size[0] > image_size[1]:
		fog_image_width = int(image_size[0] * FOG_SCALING)
		fog_image_height = int(image_size[0] * FOG_SCALING)
	else:
		fog_image_width = int(image_size[1] * FOG_SCALING)
		fog_image_height = int(image_size[1] * FOG_SCALING)


func load_map(path: String) -> void:
	# if empty we "load" the intro screens with the degus
	if path == "":
		get_fog_size(InfoDegus.get_size())
		mask_image = Image.create(fog_image_width, fog_image_width, false, Image.FORMAT_R8)
		mask_image.fill(Color.RED)

		mask_image_texture = ImageTexture.create_from_image(mask_image)
		drawing_texture.texture = mask_image_texture

		dm_background.texture = InfoDegus
		player_background.texture = PlayerInfoDegus

		dm_fog.material.set_shader_parameter("alpha_ceil", 0.2)
		player_fog.material.set_shader_parameter("alpha_ceil", 0.3)

	else:
		if not (
				path.ends_with(".jpg")
				or path.ends_with(".jpeg")
				or path.ends_with(".png")
				or path.ends_with(".map")
		):
			warning.title = "Invalid file format"
			warning.dialog_text = "File must be .jpg, .jpeg, .png or .map"
			warning.popup_centered()
			return

		# clear previous session
		undo_list = []

		for dictionary in all_placed_tokens:
			if is_instance_valid(dictionary['tokens']['dm']):
				dictionary['tokens']['dm'].queue_free()
				dictionary['tokens']['player'].queue_free()

		all_placed_tokens = []

		# load the .map file
		if path.ends_with(".map"):
			# .map is just a renamed zip with two images and a json in it
			var reader: ZIPReader = ZIPReader.new()
			var error := reader.open(path)

			if error != OK:
				warning.title = "Error"
				warning.dialog_text = "Error loading .map file. Error code: %s" % error
				warning.popup_centered()
				return

			mask_image = Image.new()
			mask_image.load_png_from_buffer(reader.read_file("mask.png"))
			mask_image.convert(Image.FORMAT_R8)

			mask_image_texture = ImageTexture.new()
			mask_image_texture.set_image(mask_image)
			drawing_texture.texture = mask_image_texture

			map_image = Image.new()
			map_image.load_png_from_buffer(reader.read_file("map.png"))
			map_image.convert(Image.FORMAT_RGB8)

			var objects: String = reader.read_file("objects.json").get_string_from_utf8()

			if len(objects) > 0:
				for line in objects.split("\n"):
					var dict: Dictionary = JSON.parse_string(line)
					make_token(Vector2(dict["x_pos"], dict["y_pos"]), dict["text"], dict["size"], dict["color_id"])

			reader.close()

		else:
			# if not .map, this is a new image
			map_image = Image.new()
			var error := map_image.load(path)

			if error != OK:
				warning.title = "Error"
				if error == ERR_FILE_NOT_FOUND:
					warning.dialog_text = "File not found"
				else:
					warning.dialog_text = "Error loading image. Error code: %s" % error
				warning.popup_centered()
				return

			map_image.convert(Image.FORMAT_RGB8)

			var map_image_width: int = map_image.get_size()[0]
			var map_image_height: int = map_image.get_size()[1]

			if map_image_width > MAX_IMAGE_SIZE or map_image_height > MAX_IMAGE_SIZE:
				var ratio: float
				if map_image_width > map_image_height:
					ratio = MAX_IMAGE_SIZE / map_image_width
				else:
					ratio = MAX_IMAGE_SIZE / map_image_height

				map_image.resize(
					int(map_image_width * ratio),
					int(map_image_height * ratio),
					Image.Interpolation.INTERPOLATE_CUBIC,
				)

			get_fog_size(map_image.get_size())
			mask_image = Image.create(fog_image_width, fog_image_width, false, Image.FORMAT_R8)
			mask_image.fill(Color.RED)

			mask_image_texture = ImageTexture.create_from_image(mask_image)
			drawing_texture.texture = mask_image_texture

		get_fog_size(map_image.get_size())
		var image_texture: Texture2D = ImageTexture.new()
		image_texture.set_image(map_image)
		dm_background.texture = image_texture
		player_background.texture = image_texture

		player_view.visible = true
		player_view_text.visible = true
		current_file_path = path

		dm_fog.material.set_shader_parameter("alpha_ceil", 0.5)
		player_fog.material.set_shader_parameter("alpha_ceil", 1)

	drawing_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE

	prev_image = mask_image

	dm_fog.visible = true
	player_fog.visible = true
	dm_fog.size = Vector2(fog_image_width, fog_image_height)
	player_fog.size = Vector2(fog_image_width, fog_image_height)
	drawing_viewport.size = Vector2(fog_image_width, fog_image_height)

	dm_camera.position = Vector2(fog_image_width * 0.5, fog_image_height * 0.5)
	player_camera.position = Vector2(fog_image_width * 0.5, fog_image_height * 0.5)

	offset_background(player_root)
	offset_background(dm_root)
	move_player_view()

	drawing_texture.visible = true
	pretend_to_draw.emit()
	dm_fog.material.set_shader_parameter("mask_texture", drawing_viewport.get_texture())
	player_fog.material.set_shader_parameter("mask_texture", drawing_viewport.get_texture())


func are_we_inside_sidebar() -> void:
	if m1_held or m2_held:
		return
	else:
		hovering_over_sidebar = true


func select_tool(index: int) -> void:
	current_tool = index
	tool_changed.emit(index)
	update_tool_visuals()

	# make all tokens mouse filter ignore if not in token placer
	for dictionary in all_placed_tokens:
		if is_instance_valid(dictionary['tokens']['dm']):
			if current_tool != tool.TOKEN_PLACER:
				# make all tokens mouse filter ignore
				dictionary['tokens']['dm'].mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				# make all tokens mouse filter stop
				dictionary['tokens']['dm'].mouse_filter = Control.MOUSE_FILTER_STOP


func offset_background(background_node: Node2D) -> void:
	var map_image_width: int
	var map_image_height: int
	if map_image != null:
		map_image_width = map_image.get_size()[0]
		map_image_height = map_image.get_size()[1]
	else:
		map_image_width = int(InfoDegus.get_size()[0])
		map_image_height = int(InfoDegus.get_size()[1])

	var x_diff: float = fog_image_width - map_image_width
	var y_diff: float = fog_image_height - map_image_height

	background_node.position.x = x_diff / 2
	background_node.position.y = y_diff / 2


func write_map(path: String) -> void:
	if not path.ends_with(".map"):
		warning.title = "Invalid file format"
		warning.dialog_text = "File must be .map"
		warning.popup_centered()
		return

	get_window().title = "DM Window"
	var writer: ZIPPacker = ZIPPacker.new()
	var error := writer.open(path)

	if error != OK:
		warning.title = "Error"
		warning.dialog_text = "Error writing map"
		warning.popup_centered()
		return

	current_file_path = path

	writer.start_file("mask.png")
	writer.write_file(drawing_viewport.get_texture().get_image().save_png_to_buffer())
	writer.start_file("map.png")
	writer.write_file(map_image.save_png_to_buffer())
	writer.start_file("objects.json")
	writer.write_file(serialize_tokens(all_placed_tokens).to_utf8_buffer())
	writer.close_file()

	writer.close()


func serialize_tokens(placed_tokens: Array[Dictionary]) -> String:
	var string: String = ""
	for dictionary in placed_tokens:
		if not is_instance_valid(dictionary['tokens']['dm']):
			continue
		if dictionary['tokens']['dm'].visible == false:
			continue

		var token: Panel = dictionary['tokens']['dm']
		var json_dict := {
			"x_pos": token.position.x,
			"y_pos": token.position.y,
			"size": token.size.x,
			"color_id": dictionary["color_id"],
			"text": token.get_child(0).text,
		}

		string += JSON.stringify(json_dict)
		string += "\n"

	return string.trim_suffix("\n")


func add_to_undo_list(action: Variant) -> void:
	undo_list.append(action)
	if current_file_path == "":
		return
	is_dirty = true
	get_window().title = "DM Window *"

func debug() -> void:
	var text := "Current tool: %s\n" % current_tool
	text += "Token color index: %s\n" % token_color_index
	text += "hovering_over_sidebar: %s\n" % hovering_over_sidebar
	text += "hovering_over_menu: %s\n" % hovering_over_menu
	text += "m1_held: %s\n" % m1_held
	text += "m2_held: %s\n" % m2_held
	text += "held_tokens: %s\n" % held_tokens
	text += "hovered_tokens: %s\n" % hovered_tokens
	text += "cursor_node.visible: %s\n" % cursor_node.visible

	for i in range(len(undo_list)):
		text += str(undo_list[i]) + "\n"

	debug_text.text = text



func update_colorscheme(id: int) -> void:
	fog_color_index = id
	update_fog_texture(FOG_COLOR_LIST[fog_color_index])
	colorscheme_menu.set_item_checked(id, true)

	for i in range(len(FOG_COLOR_LIST)):
		colorscheme_menu.set_item_checked(i, i == id)


func _on_help_id_pressed(id: int) -> void:
	if id == 0:
		warning.title = "Keybindings"
		warning.dialog_text = "General\n    Left click: Reveal areas\n    Right click: Hide areas\n    Middle mouse: Pan view\n    WASD/Arrow keys: Move view\n    Mouse wheel: Zoom\n    Ctrl+S: Save\n    Ctrl+Z: Undo\nExtra keybinds\n    Ctrl+Mouse wheel: Resize brush\n    Space: Change brush type\n    T: Toggle between fog themes\n    L: Load a map"
		warning.popup_centered()


func _on_file_id_pressed(id: int) -> void:
	if id == 0:
		load_dialog.popup()

	if id == 1:
		if current_file_path == "":
			warning.title = "Cannot save an empty map"
			warning.dialog_text = "Cannot save an empty map"
			warning.popup_centered()
		else:
			save_dialog.popup()

	if id == 2:
		get_tree().quit()
