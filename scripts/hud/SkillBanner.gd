class_name SkillBanner
extends Control

## SkillBanner: Transient floating announcement banner for Hissatsu / special skills.
## Driven by smooth, fast Tween:
##   - 0.20s quadratic ease-out slide-in
##   - 1.20s hold
##   - 0.20s quadratic ease-in slide-out
## Supports character portraits (*_portrait.png) while keeping outside the central action corridor.

signal banner_started(player_name: String, skill_name: String, element: String)
signal banner_finished(player_name: String, skill_name: String, element: String)

const SLIDE_IN_DURATION: float = 0.20
const HOLD_DURATION: float = 1.20
const SLIDE_OUT_DURATION: float = 0.20
const TOTAL_DURATION: float = SLIDE_IN_DURATION + HOLD_DURATION + SLIDE_OUT_DURATION

const DEFAULT_ONSCREEN_POS: Vector2 = Vector2(920.0, 14.0)
const DEFAULT_OFFSCREEN_POS: Vector2 = Vector2(1320.0, 14.0)
const BANNER_SIZE: Vector2 = Vector2(340.0, 52.0)

const ELEMENT_COLORS: Dictionary = {
	"FIRE": Color(1.0, 0.35, 0.12, 1.0),
	"FUEGO": Color(1.0, 0.35, 0.12, 1.0),
	"WOOD": Color(0.22, 0.82, 0.36, 1.0),
	"BOSQUE": Color(0.22, 0.82, 0.36, 1.0),
	"AIR": Color(0.22, 0.72, 1.0, 1.0),
	"VIENTO": Color(0.22, 0.72, 1.0, 1.0),
	"WIND": Color(0.22, 0.72, 1.0, 1.0),
	"EARTH": Color(0.92, 0.70, 0.20, 1.0),
	"MONTAÑA": Color(0.92, 0.70, 0.20, 1.0),
	"NEUTRAL": Color(0.85, 0.85, 0.90, 1.0)
}

var onscreen_position: Vector2 = DEFAULT_ONSCREEN_POS
var offscreen_position: Vector2 = DEFAULT_OFFSCREEN_POS

var current_player: String = ""
var current_skill: String = ""
var current_element: String = "FIRE"
var current_portrait_path: String = ""
var is_active: bool = false

var _active_tween: Tween = null
var _portrait_cache: Dictionary = {}

@onready var panel: PanelContainer = get_node_or_null("PanelContainer")
@onready var portrait_rect: TextureRect = get_node_or_null("PanelContainer/MarginContainer/HBoxContainer/PortraitRect")
@onready var player_label: Label = get_node_or_null("PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/PlayerLabel")
@onready var skill_label: Label = get_node_or_null("PanelContainer/MarginContainer/HBoxContainer/VBoxContainer/SkillLabel")
@onready var element_badge: Label = get_node_or_null("PanelContainer/MarginContainer/HBoxContainer/ElementBadge")

func _ready() -> void:
	custom_minimum_size = BANNER_SIZE
	size = BANNER_SIZE
	position = offscreen_position
	modulate.a = 0.0
	visible = false
	is_active = false
	_build_ui_if_needed()

func _build_ui_if_needed() -> void:
	if panel != null:
		return

	panel = PanelContainer.new()
	panel.name = "PanelContainer"
	panel.custom_minimum_size = BANNER_SIZE
	panel.size = BANNER_SIZE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.86)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = ELEMENT_COLORS["FIRE"]
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	portrait_rect = TextureRect.new()
	portrait_rect.name = "PortraitRect"
	portrait_rect.custom_minimum_size = Vector2(42, 42)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.visible = false
	hbox.add_child(portrait_rect)

	element_badge = Label.new()
	element_badge.name = "ElementBadge"
	element_badge.text = "[FIRE]"
	element_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	element_badge.add_theme_font_size_override("font_size", 11)
	element_badge.add_theme_color_override("font_color", ELEMENT_COLORS["FIRE"])
	hbox.add_child(element_badge)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	hbox.add_child(vbox)

	player_label = Label.new()
	player_label.name = "PlayerLabel"
	player_label.text = "PLAYER"
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	player_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 0.92))
	player_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(player_label)

	skill_label = Label.new()
	skill_label.name = "SkillLabel"
	skill_label.text = "SKILL NAME"
	skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	skill_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.70, 1.0))
	skill_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(skill_label)

func _exit_tree() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
		_active_tween = null

func preload_portrait(path: String) -> void:
	_load_portrait_texture(path)

func _load_portrait_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _portrait_cache.has(path):
		return _portrait_cache[path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(ProjectSettings.globalize_path(path)) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex != null:
		_portrait_cache[path] = tex
	return tex

func display_skill(player_name: String, skill_name: String, element: String = "FIRE", portrait_path: String = "") -> void:
	_build_ui_if_needed()

	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
		_active_tween = null

	current_player = player_name
	current_skill = skill_name
	current_element = element.to_upper()
	current_portrait_path = portrait_path
	is_active = true

	var elem_color: Color = ELEMENT_COLORS.get(current_element, ELEMENT_COLORS["NEUTRAL"])

	if portrait_rect != null:
		var tex := _load_portrait_texture(portrait_path)
		portrait_rect.texture = tex
		portrait_rect.visible = (tex != null)

	if player_label != null:
		player_label.text = current_player.to_upper()
	if skill_label != null:
		skill_label.text = "★ " + current_skill.to_upper() + " ★"
	if element_badge != null:
		element_badge.text = "[" + current_element + "]"
		element_badge.add_theme_color_override("font_color", elem_color)

	if panel != null:
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.border_color = elem_color

	visible = true
	position = offscreen_position
	modulate.a = 0.0

	emit_signal("banner_started", current_player, current_skill, current_element)

	_active_tween = create_tween()

	# Phase 1: Slide-in (0.20s quadratic ease-out)
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "position:x", onscreen_position.x, SLIDE_IN_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "position:y", onscreen_position.y, SLIDE_IN_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "modulate:a", 1.0, 0.15)

	# Phase 2: Hold (1.20s interval)
	_active_tween.chain().tween_interval(HOLD_DURATION)

	# Phase 3: Slide-out (0.20s quadratic ease-in)
	_active_tween.chain().set_parallel(true)
	_active_tween.tween_property(self, "position:x", offscreen_position.x, SLIDE_OUT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(self, "modulate:a", 0.0, SLIDE_OUT_DURATION)

	_active_tween.chain().tween_callback(func():
		visible = false
		is_active = false
		emit_signal("banner_finished", current_player, current_skill, current_element)
	)

func reset_banner() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
		_active_tween = null
	position = offscreen_position
	modulate.a = 0.0
	visible = false
	is_active = false

func get_banner_rect() -> Rect2:
	return Rect2(position, size)
