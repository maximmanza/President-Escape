extends Node2D

const MAP_TEXTURE := preload("res://prison_map_reference.png")
const CAMERA_LEFT_BODY := preload("res://security_camera_left_body.png")
const CAMERA_LEFT_BEAM := preload("res://security_camera_left_beam.png")
const CAMERA_RIGHT_BODY := preload("res://security_camera_right_body.png")
const CAMERA_RIGHT_BEAM := preload("res://security_camera_right_beam.png")
const WORLD_WIDTH := 2172.0
const WORLD_HEIGHT := 724.0
const FLOOR_Y := [184.0, 354.0, 524.0, 694.0]
const ELEVATOR_STATIONS := [Vector2i(190, 0), Vector2i(190, 1), Vector2i(1980, 1), Vector2i(190, 2), Vector2i(1980, 2), Vector2i(190, 3)]
const DOOR_CODE := "6767"
const CODE_NOTE_POSITION := Vector2(870.0, 452.0)
const FINAL_DOOR_POSITION := Vector2(2050.0, 110.0)
const LASER_SWITCH_POSITION := Vector2(1385.0, 292.0)

var player: CharacterBody2D
var message_label: Label
var won := false
var security_cameras: Array[Dictionary] = []
var guard_area: Area2D
var elevator_doors: Array[Dictionary] = []
var elapsed := 0.0
var alarm_triggered := false
var code_note_read := false
var keypad_active := false
var typed_code := ""
var final_gate_open := false
var laser_enabled := true
var laser_area: Area2D
var elevator_selected_x := -1.0
var elevator_busy := false
var map_material: ShaderMaterial
var note_overlay: Control
var keypad_overlay: Control
var keypad_display: Label
var keypad_status: Label
var win_overlay: Control
var exit_door_collider: CollisionShape2D
@onready var map_sprite: Sprite2D = $Kart
@onready var player: CharacterBody2D = $Trump

func _ready() -> void:
	# Vis hele den stablede fengselsbanen, slik referansebildet gjør.
	get_window().size = Vector2i(1440, 900)
	_build_level()
	_build_player()
	_build_ui()

func _build_level() -> void:
	# Vis kartbildet urørt. Bare spillkollisjon og usynlige spillområder legges til.
	var map_shader := Shader.new()
	map_shader.code = """
	shader_type canvas_item;
	uniform bool left_camera_active = true;
	uniform bool right_camera_active = true;
	uniform bool laser_enabled = true;
	uniform bool final_gate_open = false;
	uniform float map_brightness = 1.45;
	void fragment() {
		vec4 pixel = texture(TEXTURE, UV) * COLOR;
		vec2 at = UV * vec2(2172.0, 724.0);
		float amount = clamp((at.y - 576.0) / 118.0, 0.0, 1.0);
		if (!left_camera_active && at.y > 594.0 && at.y < 694.0) {
			float right_edge = 803.0 + 137.0 * amount;
			if (at.x >= 803.0 && at.x <= right_edge) {
				pixel = texture(TEXTURE, vec2((1606.0 - at.x) / 2172.0, UV.y)) * COLOR;
			}
		}
		if (!right_camera_active && at.y > 594.0 && at.y < 694.0) {
			float left_edge = 1358.0 - 143.0 * amount;
			if (at.x >= left_edge && at.x <= 1358.0) {
				pixel = texture(TEXTURE, vec2((2716.0 - at.x) / 2172.0, UV.y)) * COLOR;
			}
		}
		if (!laser_enabled && at.x > 830.0 && at.x < 1290.0 && at.y > 282.0 && at.y < 307.0) {
			float replacement_y = at.y < 294.0 ? at.y + 16.0 : at.y - 16.0;
			pixel = texture(TEXTURE, vec2(UV.x, replacement_y / 724.0)) * COLOR;
		}
		if (final_gate_open && at.x > 1844.0 && at.x < 1984.0 && at.y > 55.0 && at.y < 178.0) {
			float opening_shade = 0.055 + 0.035 * clamp((at.y - 55.0) / 123.0, 0.0, 1.0);
			pixel.rgb = vec3(opening_shade, opening_shade * 1.25, opening_shade * 1.65);
		}
		pixel.rgb *= map_brightness;
		COLOR = pixel;
	}
	"""
	map_material = ShaderMaterial.new()
	map_material.shader = map_shader
	map_sprite.material = map_material
	_build_laser_area()
	_build_security_cameras()
	_build_guard_detection()
	_build_hidden_buttons()
	_build_elevator_doors()
	_build_exit_blocker()

func _build_exit_blocker() -> void:
	var blocker := StaticBody2D.new()
	blocker.name = "Låst utgang"
	blocker.position = Vector2(1914.0, 116.0)
	exit_door_collider = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(100.0, 120.0)
	exit_door_collider.shape = shape
	blocker.add_child(exit_door_collider)
	add_child(blocker)

func _build_elevator_doors() -> void:
	# Dørpanelene er utsnitt fra det innlagte kartet, så den tegnede stilen bevares.
	for station in ELEVATOR_STATIONS:
		var floor_y: float = FLOOR_Y[station.y]
		var center_x := float(station.x) - 8.0
		var opening := ColorRect.new()
		opening.position = Vector2(center_x - 52.0, floor_y - 109.0)
		opening.size = Vector2(104.0, 109.0)
		opening.color = Color("#101827")
		opening.z_index = 0
		opening.visible = false
		add_child(opening)
		var left_leaf := _make_elevator_leaf(Rect2(128, 75, 52, 109), Vector2(center_x - 52.0, floor_y - 109.0))
		var right_leaf := _make_elevator_leaf(Rect2(180, 75, 52, 109), Vector2(center_x, floor_y - 109.0))
		elevator_doors.append({
			"floor": station.y,
			"x": float(station.x),
			"center": center_x,
			"opening": opening,
			"left": left_leaf,
			"right": right_leaf,
			"progress": 0.0,
			"target": 0.0
		})

func _make_elevator_leaf(region: Rect2, pos: Vector2) -> Sprite2D:
	var leaf := Sprite2D.new()
	leaf.texture = MAP_TEXTURE
	leaf.region_enabled = true
	leaf.region_rect = region
	leaf.centered = false
	leaf.position = pos
	leaf.z_index = 1
	leaf.visible = false
	add_child(leaf)
	return leaf

func _update_elevator_doors(delta: float) -> void:
	var feet_y: float = player.global_position.y + 36.0
	for door in elevator_doors:
		var floor_index: int = door["floor"]
		var door_x: float = door["x"]
		var near_this_door := absf(player.global_position.x - door_x) <= 108.0 and absf(feet_y - FLOOR_Y[floor_index]) <= 64.0
		door["target"] = 1.0 if near_this_door else 0.0
		door["progress"] = move_toward(float(door["progress"]), float(door["target"]), delta * 3.5)
		var progress: float = door["progress"]
		var opening: ColorRect = door["opening"]
		var left_leaf: Sprite2D = door["left"]
		var right_leaf: Sprite2D = door["right"]
		var open_visible := progress > 0.0
		opening.visible = open_visible
		left_leaf.visible = open_visible
		right_leaf.visible = open_visible
		var floor_y: float = FLOOR_Y[floor_index]
		var center_x: float = door["center"]
		left_leaf.position = Vector2(center_x - 52.0 - 52.0 * progress, floor_y - 109.0)
		right_leaf.position = Vector2(center_x + 52.0 * progress, floor_y - 109.0)

func _build_hidden_buttons() -> void:
	# Usynlige klikkfelt ligger over knappene i kartbildet; de tegner ingenting.
	_add_hidden_button(Vector2(190, 47), Vector2(88, 42), "elevator", 190.0, 0)
	_add_hidden_button(Vector2(190, 217), Vector2(88, 42), "elevator", 190.0, 1)
	_add_hidden_button(Vector2(1980, 217), Vector2(88, 42), "elevator", 1980.0, 1)
	_add_hidden_button(Vector2(190, 387), Vector2(88, 42), "elevator", 190.0, 2)
	_add_hidden_button(Vector2(1980, 387), Vector2(88, 42), "elevator", 1980.0, 2)
	_add_hidden_button(Vector2(190, 557), Vector2(88, 42), "elevator", 190.0, 3)
	_add_hidden_button(LASER_SWITCH_POSITION, Vector2(48, 48), "laser")
	_add_hidden_button(CODE_NOTE_POSITION, Vector2(90, 100), "note")
	_add_hidden_button(FINAL_DOOR_POSITION, Vector2(100, 125), "keypad")

func _add_hidden_button(center: Vector2, size: Vector2, action: String, elevator_x: float = -1.0, floor_index: int = -1) -> void:
	var hit_area := Area2D.new()
	hit_area.position = center
	hit_area.input_pickable = true
	hit_area.collision_layer = 1
	var hit_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	hit_shape.shape = rectangle
	hit_area.add_child(hit_shape)
	hit_area.input_event.connect(_on_hidden_button_input.bind(action, elevator_x, floor_index))
	add_child(hit_area)

func _on_hidden_button_input(_viewport: Node, event: InputEvent, _shape_index: int, action: String, elevator_x: float, floor_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return
	_viewport.set_input_as_handled()
	if action == "elevator":
		var station_position := Vector2(elevator_x, FLOOR_Y[floor_index] - 70.0)
		if player.global_position.distance_to(station_position) <= 120.0:
			elevator_selected_x = elevator_x
			message_label.text = "HEISKALL-KNAPP TRYKKET — ↑/↓ FOR ETASJE"
		else:
			message_label.text = "GÅ TIL HEISEN FØRST"
	elif action == "laser":
		if player.global_position.distance_to(LASER_SWITCH_POSITION) <= 110.0:
			_toggle_laser()
			message_label.text = "LASEREN ER %s" % ("PÅ" if laser_enabled else "AV")
		else:
			message_label.text = "GÅ TIL LASERBRYTEREN FØRST"
	elif action == "note":
		if player.global_position.distance_to(CODE_NOTE_POSITION) <= 100.0:
			_open_note()
		else:
			message_label.text = "GÅ TIL NOTATET FØRST"
	elif action == "keypad":
		if player.global_position.distance_to(FINAL_DOOR_POSITION) <= 235.0:
			_handle_interaction()
		else:
			message_label.text = "GÅ TIL DØREN FØRST"

func _build_guard_detection() -> void:
	# Vekteren er allerede tegnet i kartet; området gjør den plasseringen aktiv.
	guard_area = Area2D.new()
	guard_area.name = "Vaktens synsfelt"
	guard_area.position = Vector2(490, 465)
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 54.0
	collider.shape = shape
	guard_area.add_child(collider)
	guard_area.body_entered.connect(_on_guard_body_entered)
	add_child(guard_area)

func _build_security_cameras() -> void:
	# De to originale kamerautsnittene gjenbrukes på de øvre etasjene.
	var camera_index := 0
	for floor_index in range(FLOOR_Y.size()):
		var floor_y: float = FLOOR_Y[floor_index]
		var placements := [
			{"sprite_x": 700.0, "body": CAMERA_LEFT_BODY, "beam": CAMERA_LEFT_BEAM, "points": PackedVector2Array([Vector2(101, 28), Vector2(240, 144), Vector2(101, 144)])},
			{"sprite_x": 1240.0, "body": CAMERA_RIGHT_BODY, "beam": CAMERA_RIGHT_BEAM, "points": PackedVector2Array([Vector2(113, 28), Vector2(0, 144), Vector2(113, 144)])}
		]
		for placement in placements:
			var beam_sprite: Sprite2D = null
			if floor_index < FLOOR_Y.size() - 1:
				var camera_sprite := Sprite2D.new()
				camera_sprite.texture = placement["body"]
				camera_sprite.centered = false
				camera_sprite.position = Vector2(placement["sprite_x"], floor_y - 144.0)
				camera_sprite.z_index = 1
				add_child(camera_sprite)
				beam_sprite = Sprite2D.new()
				beam_sprite.texture = placement["beam"]
				beam_sprite.centered = false
				beam_sprite.position = camera_sprite.position
				beam_sprite.z_index = 0
				beam_sprite.visible = false
				add_child(beam_sprite)
			var sensor := Area2D.new()
			sensor.name = "Kamera sensor %d" % (camera_index + 1)
			sensor.position = Vector2(placement["sprite_x"], floor_y - 144.0)
			sensor.monitoring = false
			var shape := CollisionPolygon2D.new()
			shape.polygon = placement["points"]
			sensor.add_child(shape)
			sensor.body_entered.connect(_on_camera_body_entered.bind(sensor))
			add_child(sensor)
			var initial_active := fposmod(float(camera_index) * 0.51, 6.0) < 3.6
			sensor.monitoring = initial_active
			if beam_sprite != null:
				beam_sprite.visible = initial_active
			if floor_index == FLOOR_Y.size() - 1:
				var uniform_name := "left_camera_active" if camera_index % 2 == 0 else "right_camera_active"
				map_material.set_shader_parameter(uniform_name, initial_active)
			security_cameras.append({"area": sensor, "beam": beam_sprite, "phase": float(camera_index) * 0.51, "active": initial_active, "floor": floor_index, "side": camera_index % 2})
			camera_index += 1

func _build_laser_area() -> void:
	laser_area = Area2D.new()
	laser_area.name = "Laserfelt"
	laser_area.position = Vector2(1060.0, 294.0)
	laser_area.monitoring = true
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(450, 14)
	shape_node.shape = shape
	laser_area.add_child(shape_node)
	laser_area.body_entered.connect(_on_laser_body_entered)
	add_child(laser_area)

func _build_player() -> void:
	player.position = Vector2(280, FLOOR_Y[0] - 36)
	# Trump, drakten, kollisjon og kameravisning er lagt inn som redigerbare noder i main.tscn.
	pass

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.04, 0.07, 0.11, 0.88)
	panel.position = Vector2(18, 16)
	panel.size = Vector2(720, 60)
	layer.add_child(panel)
	var title := _label("PRESIDENT ESCAPE", Vector2(30, 18), 17, Color("#f2f4f8"))
	layer.add_child(title)
	var controls := _label("← → GÅ   •   SHIFT SNIKE   •   E KNAPP   •   ↑/↓ HEIS", Vector2(30, 42), 12, Color("#c3cbd2"))
	layer.add_child(controls)
	message_label = _label("", Vector2(595, 23), 16, Color("#a9edc8"))
	layer.add_child(message_label)
	_build_note_overlay(layer)
	_build_keypad_overlay(layer)
	_build_win_overlay(layer)

func _build_win_overlay(layer: CanvasLayer) -> void:
	win_overlay = Control.new()
	win_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_overlay.visible = false
	win_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(win_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.04, 0.86)
	win_overlay.add_child(shade)
	var victory := _label("DU VANT!", Vector2.ZERO, 78, Color("#ffe28a"))
	victory.anchor_left = 0.5
	victory.anchor_right = 0.5
	victory.anchor_top = 0.5
	victory.anchor_bottom = 0.5
	victory.offset_left = -320
	victory.offset_right = 320
	victory.offset_top = -150
	victory.offset_bottom = -65
	victory.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_overlay.add_child(victory)
	var subtitle := _label("Trump har rømt fra fengselet!", Vector2.ZERO, 30, Color("#f2f4f8"))
	subtitle.anchor_left = 0.5
	subtitle.anchor_right = 0.5
	subtitle.anchor_top = 0.5
	subtitle.anchor_bottom = 0.5
	subtitle.offset_left = -360
	subtitle.offset_right = 360
	subtitle.offset_top = -50
	subtitle.offset_bottom = 5
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_overlay.add_child(subtitle)
	var replay := Button.new()
	replay.text = "SPILL IGJEN"
	replay.anchor_left = 0.5
	replay.anchor_right = 0.5
	replay.anchor_top = 0.5
	replay.anchor_bottom = 0.5
	replay.offset_left = -100
	replay.offset_right = 100
	replay.offset_top = 45
	replay.offset_bottom = 109
	replay.add_theme_font_size_override("font_size", 22)
	replay.pressed.connect(_restart_after_win)
	win_overlay.add_child(replay)

func _restart_after_win() -> void:
	get_tree().reload_current_scene()

func _build_note_overlay(layer: CanvasLayer) -> void:
	note_overlay = Control.new()
	note_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	note_overlay.visible = false
	note_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(note_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.04, 0.94)
	note_overlay.add_child(shade)
	var page_border := ColorRect.new()
	page_border.position = Vector2(82, 42)
	page_border.size = Vector2(1276, 816)
	page_border.color = Color("#a89470")
	note_overlay.add_child(page_border)
	var page := ColorRect.new()
	page.position = Vector2(92, 52)
	page.size = Vector2(1256, 796)
	page.color = Color("#eee2c4")
	note_overlay.add_child(page)
	var heading := _label("NOTAT FRA VAKTEN", Vector2(210, 145), 36, Color("#453d31"))
	note_overlay.add_child(heading)
	var subtitle := _label("KODE TIL SIKKERHETSDØREN", Vector2(210, 220), 25, Color("#655844"))
	note_overlay.add_child(subtitle)
	var code := _label(DOOR_CODE, Vector2(210, 310), 116, Color("#2b2924"))
	note_overlay.add_child(code)
	var instruction := _label("Husk koden. Trykk X oppe i hjørnet for å lukke notatet.", Vector2(210, 485), 22, Color("#655844"))
	note_overlay.add_child(instruction)
	for i in range(5):
		var line := ColorRect.new()
		line.position = Vector2(210, 560 + i * 42)
		line.size = Vector2(1000, 2)
		line.color = Color(0.45, 0.39, 0.29, 0.22)
		note_overlay.add_child(line)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.position = Vector2(1270, 62)
	close_button.size = Vector2(58, 58)
	close_button.add_theme_font_size_override("font_size", 30)
	close_button.tooltip_text = "Lukk notatet"
	close_button.pressed.connect(_close_note)
	note_overlay.add_child(close_button)

func _open_note() -> void:
	code_note_read = true
	keypad_active = false
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	note_overlay.visible = true

func _close_note() -> void:
	note_overlay.visible = false
	player.set_physics_process(true)

func _build_keypad_overlay(layer: CanvasLayer) -> void:
	keypad_overlay = Control.new()
	keypad_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	keypad_overlay.visible = false
	keypad_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(keypad_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.015, 0.03, 0.88)
	keypad_overlay.add_child(shade)
	var panel := ColorRect.new()
	panel.position = Vector2(470, 115)
	panel.size = Vector2(500, 680)
	panel.color = Color("#263346")
	keypad_overlay.add_child(panel)
	var title := _label("SIKKERHETSDØR", Vector2(535, 155), 30, Color("#f2f4f8"))
	keypad_overlay.add_child(title)
	var prompt := _label("SKRIV INN FIRE-SIFRET KODE", Vector2(535, 205), 17, Color("#cbd5e1"))
	keypad_overlay.add_child(prompt)
	var display_box := ColorRect.new()
	display_box.position = Vector2(550, 255)
	display_box.size = Vector2(340, 68)
	display_box.color = Color("#101923")
	keypad_overlay.add_child(display_box)
	keypad_display = _label("____", Vector2(575, 263), 38, Color("#9af3b0"))
	keypad_overlay.add_child(keypad_display)
	keypad_status = _label("", Vector2(550, 328), 17, Color("#ffd27a"))
	keypad_overlay.add_child(keypad_status)
	for i in range(9):
		var digit := str(i + 1)
		var button := Button.new()
		button.text = digit
		button.position = Vector2(570 + (i % 3) * 100, 370 + int(i / 3) * 76)
		button.size = Vector2(78, 62)
		button.add_theme_font_size_override("font_size", 26)
		button.pressed.connect(_on_keypad_button.bind(digit))
		keypad_overlay.add_child(button)
	var clear_button := Button.new()
	clear_button.text = "C"
	clear_button.position = Vector2(570, 598)
	clear_button.size = Vector2(78, 62)
	clear_button.pressed.connect(_on_keypad_button.bind("clear"))
	keypad_overlay.add_child(clear_button)
	var zero_button := Button.new()
	zero_button.text = "0"
	zero_button.position = Vector2(670, 598)
	zero_button.size = Vector2(78, 62)
	zero_button.add_theme_font_size_override("font_size", 26)
	zero_button.pressed.connect(_on_keypad_button.bind("0"))
	keypad_overlay.add_child(zero_button)
	var enter_button := Button.new()
	enter_button.text = "ENTER"
	enter_button.position = Vector2(770, 598)
	enter_button.size = Vector2(100, 62)
	enter_button.pressed.connect(_on_keypad_button.bind("enter"))
	keypad_overlay.add_child(enter_button)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.position = Vector2(890, 130)
	close_button.size = Vector2(54, 54)
	close_button.add_theme_font_size_override("font_size", 26)
	close_button.pressed.connect(_close_keypad)
	keypad_overlay.add_child(close_button)

func _on_keypad_button(value: String) -> void:
	if value == "enter":
		_submit_door_code()
	elif value == "clear":
		typed_code = ""
		_update_keypad_message()
	elif typed_code.length() < DOOR_CODE.length():
		typed_code += value
		_update_keypad_message()

func _open_keypad() -> void:
	keypad_active = true
	typed_code = ""
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	keypad_status.text = ""
	keypad_overlay.visible = true
	_update_keypad_message()

func _close_keypad() -> void:
	keypad_active = false
	keypad_overlay.visible = false
	player.set_physics_process(true)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if note_overlay.visible:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			_close_note()
		get_viewport().set_input_as_handled()
		return
	if keypad_active:
		if event.keycode == KEY_ESCAPE:
			_close_keypad()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_submit_door_code()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_BACKSPACE:
			typed_code = typed_code.left(maxi(typed_code.length() - 1, 0))
			_update_keypad_message()
			get_viewport().set_input_as_handled()
		elif event.unicode >= 48 and event.unicode <= 57 and typed_code.length() < DOOR_CODE.length():
			typed_code += String.chr(event.unicode)
			_update_keypad_message()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_E:
		_handle_interaction()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_UP or event.keycode == KEY_W:
		if final_gate_open and player.global_position.distance_to(FINAL_DOOR_POSITION) <= 235.0:
			_show_win()
			get_viewport().set_input_as_handled()
		elif elevator_selected_x >= 0.0:
			_ride_elevator(-1)
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
		if elevator_selected_x >= 0.0:
			_ride_elevator(1)
			get_viewport().set_input_as_handled()

func _handle_interaction() -> void:
	if player.global_position.distance_to(CODE_NOTE_POSITION) <= 72.0:
		_open_note()
		return
	if player.global_position.distance_to(LASER_SWITCH_POSITION) <= 78.0:
		_toggle_laser()
		message_label.text = "LASEREN ER %s" % ("PÅ" if laser_enabled else "SLÅTT AV")
		message_label.add_theme_color_override("font_color", Color("#f0d78c"))
		return
	if player.global_position.distance_to(FINAL_DOOR_POSITION) <= 235.0:
		if final_gate_open:
			message_label.text = "DØREN ER ÅPEN — LØP MOT FRIHETEN!"
		else:
			_open_keypad()
		return
	for station in ELEVATOR_STATIONS:
		var station_position := Vector2(float(station.x), FLOOR_Y[station.y] - 70.0)
		if player.global_position.distance_to(station_position) <= 92.0:
			elevator_selected_x = float(station.x)
			message_label.text = "HEIS: TRYKK ↑ ELLER ↓ FOR Å VELGE ETASJE"
			message_label.add_theme_color_override("font_color", Color("#f0d78c"))
			return

func _update_keypad_message() -> void:
	message_label.text = "TAST KODE: %s  •  ENTER: LÅS OPP" % typed_code
	message_label.add_theme_color_override("font_color", Color("#f0d78c"))
	if keypad_display != null:
		keypad_display.text = typed_code + "_".repeat(maxi(DOOR_CODE.length() - typed_code.length(), 0))
	if keypad_status != null:
		keypad_status.text = ""

func _toggle_laser() -> void:
	laser_enabled = not laser_enabled
	laser_area.monitoring = laser_enabled
	map_material.set_shader_parameter("laser_enabled", laser_enabled)

func _submit_door_code() -> void:
	if typed_code == DOOR_CODE:
		final_gate_open = true
		exit_door_collider.set_deferred("disabled", true)
		map_material.set_shader_parameter("final_gate_open", true)
		keypad_active = false
		keypad_overlay.visible = false
		player.set_physics_process(true)
		keypad_status.text = "RIKTIG KODE"
		message_label.text = "RIKTIG KODE — GÅ GJENNOM DEN ÅPNE DØRA!"
		message_label.add_theme_color_override("font_color", Color("#a9edc8"))
	else:
		typed_code = ""
		_update_keypad_message()
		keypad_status.text = "FEIL KODE — PRØV IGJEN"
		keypad_status.add_theme_color_override("font_color", Color("#ff8b7c"))

func _label(text_value: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.text = text_value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _add_floor_collision(from_x: float, to_x: float, y: float) -> void:
	if to_x <= from_x:
		return
	var body := StaticBody2D.new()
	# Rektangelet er sentrert rundt body; venstrekanten her etterlot store hull.
	body.position = Vector2((from_x + to_x) * 0.5, y + 15.0)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(to_x - from_x, 30)
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func _process(_delta: float) -> void:
	if (note_overlay != null and note_overlay.visible) or (keypad_overlay != null and keypad_overlay.visible) or (win_overlay != null and win_overlay.visible):
		return
	elapsed += _delta
	_update_security_cameras()
	_update_elevator_doors(_delta)
	if laser_enabled and laser_area.overlaps_body(player):
		_trigger_alarm()
		return
	if not Input.is_key_pressed(KEY_SHIFT) and absf(player.velocity.x) > 5.0:
		for body in guard_area.get_overlapping_bodies():
			if body == player:
				_trigger_alarm()
				return
	if keypad_active or alarm_triggered or elevator_busy:
		return
	if player.global_position.distance_to(CODE_NOTE_POSITION) <= 82.0:
		message_label.text = "PAPIR: KODE %s" % DOOR_CODE if code_note_read else "PAPIR MED KODE — TRYKK E FOR Å LESE"
		message_label.add_theme_color_override("font_color", Color("#f0d78c"))
	elif player.global_position.distance_to(LASER_SWITCH_POSITION) <= 100.0:
		message_label.text = "LASERBRYTER — TRYKK E FOR Å SLÅ %s" % ("AV" if laser_enabled else "PÅ")
		message_label.add_theme_color_override("font_color", Color("#f0d78c"))
	elif player.global_position.distance_to(FINAL_DOOR_POSITION) <= 235.0:
		message_label.text = "TRYKK ↑ FOR Å GÅ INN" if final_gate_open else "SIKKERHETSDØR — TRYKK E FOR Å TASTE KODE"
		message_label.add_theme_color_override("font_color", Color("#f0d78c"))
	else:
		var near_elevator := false
		for station in ELEVATOR_STATIONS:
			var station_position := Vector2(float(station.x), FLOOR_Y[station.y] - 70.0)
			if player.global_position.distance_to(station_position) <= 92.0:
				elevator_selected_x = float(station.x)
				message_label.text = "HEIS: TRYKK ↑ OPP ELLER ↓ NED"
				message_label.add_theme_color_override("font_color", Color("#f0d78c"))
				near_elevator = true
				break
		if not near_elevator:
			elevator_selected_x = -1.0
			message_label.text = ""
	if not won and final_gate_open and player.global_position.x > 2080.0 and player.global_position.y < FLOOR_Y[0]:
		_show_win()

func _show_win() -> void:
	won = true
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	win_overlay.visible = true

func _physics_process(_delta: float) -> void:
	pass

func _ride_elevator(direction: int) -> void:
	if elevator_busy or elevator_selected_x < 0.0:
		return
	var current_floor := 0
	var feet_y: float = player.global_position.y + 36.0
	for i in range(FLOOR_Y.size()):
		if absf(feet_y - FLOOR_Y[i]) < 60.0:
			current_floor = i
			break
	var stops: Array[int] = []
	for station in ELEVATOR_STATIONS:
		if is_equal_approx(float(station.x), elevator_selected_x):
			stops.append(station.y)
	var target_floor := current_floor + direction
	if not stops.has(target_floor):
		message_label.text = "HEISEN KJØRER IKKE LENGER DEN VEIEN"
		return
	elevator_busy = true
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	message_label.text = "HEISEN KJØRER TIL ETASJE %d" % (FLOOR_Y.size() - target_floor)
	var target_position := Vector2(elevator_selected_x, FLOOR_Y[target_floor] - 36.0)
	var ride := create_tween()
	ride.tween_property(player, "position", target_position, 0.65).set_trans(Tween.TRANS_SINE)
	await ride.finished
	player.velocity = Vector2.ZERO
	player.set_physics_process(true)
	elevator_busy = false
	message_label.text = "HEISEN HAR STOPPET — GÅ UT NÅ"

func _update_security_cameras() -> void:
	for camera_data in security_cameras:
		var area: Area2D = camera_data["area"]
		var active := fposmod(elapsed + float(camera_data["phase"]), 6.0) < 3.6
		if active != bool(camera_data["active"]):
			camera_data["active"] = active
			area.monitoring = active
			var beam_sprite: Sprite2D = camera_data["beam"]
			if beam_sprite != null:
				beam_sprite.visible = active
			if int(camera_data["floor"]) == FLOOR_Y.size() - 1:
				var uniform_name := "left_camera_active" if int(camera_data["side"]) == 0 else "right_camera_active"
				map_material.set_shader_parameter(uniform_name, active)
		if active and area.monitoring:
			for body in area.get_overlapping_bodies():
				if body == player:
					_trigger_alarm()
					return

func _on_camera_body_entered(body: Node2D, area: Area2D) -> void:
	if body == player and area.monitoring:
		_trigger_alarm()

func _on_guard_body_entered(body: Node2D) -> void:
	if body == player and not Input.is_key_pressed(KEY_SHIFT) and absf(player.velocity.x) > 5.0:
		_trigger_alarm()

func _on_laser_body_entered(body: Node2D) -> void:
	if body == player and laser_enabled:
		_trigger_alarm()

func _trigger_alarm() -> void:
	if alarm_triggered:
		return
	alarm_triggered = true
	message_label.text = "ALARM! KAMERA OPPDAGET DEG — STARTER PÅ NYTT"
	message_label.add_theme_color_override("font_color", Color("#ff5147"))
	await get_tree().create_timer(1.2).timeout
	get_tree().reload_current_scene()
