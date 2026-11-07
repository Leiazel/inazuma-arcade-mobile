class_name KitData
extends Resource

## Data-driven resource defining team uniforms, color palettes, and differentiation settings.

@export_group("Identity")
@export var team_name: String = "Raimon"
@export var is_away: bool = false

@export_group("Kit Colors")
## Primary jersey and body color
@export var primary_color: Color = Color("#F2C94C")
## Secondary shorts, sleeves, and secondary details color
@export var secondary_color: Color = Color("#2F80ED")
## Trim, collar, socks, and accent border color
@export var trim_color: Color = Color.WHITE
## Squad number and lettering color
@export var number_color: Color = Color.BLACK

@export_group("Base Indicator")
## Ring indicator color under player's feet. If set to transparent, primary_color is used.
@export var indicator_color: Color = Color(0, 0, 0, 0)

@export_group("Shader Palette Keys")
## Original base sprite primary key to replace
@export var base_primary_key: Color = Color(0.949, 0.788, 0.298, 1.0) # #F2C94C
## Original base sprite secondary key to replace
@export var base_secondary_key: Color = Color(0.184, 0.502, 0.929, 1.0) # #2F80ED
## Original base sprite trim key to replace
@export var base_trim_key: Color = Color(1.0, 1.0, 1.0, 1.0)

## Validates kit resource integrity
func validate() -> bool:
	if team_name.strip_edges().is_empty():
		push_warning("KitData validation failed: team_name is empty.")
		return false
	if primary_color.a <= 0.0:
		push_warning("KitData validation failed: primary_color has zero alpha.")
		return false
	if not _is_valid_color(primary_color):
		push_warning("KitData validation failed: primary_color has invalid RGB channels (must be in [0.0, 1.0] and not NaN).")
		return false
	if secondary_color.a <= 0.0:
		push_warning("KitData validation failed: secondary_color has zero alpha.")
		return false
	if not _is_valid_color(secondary_color):
		push_warning("KitData validation failed: secondary_color has invalid RGB channels (must be in [0.0, 1.0] and not NaN).")
		return false
	if trim_color.a <= 0.0:
		push_warning("KitData validation failed: trim_color has zero alpha.")
		return false
	if not _is_valid_color(trim_color):
		push_warning("KitData validation failed: trim_color has invalid RGB channels (must be in [0.0, 1.0] and not NaN).")
		return false
	if number_color.a <= 0.0:
		push_warning("KitData validation failed: number_color has zero alpha.")
		return false
	if not _is_valid_color(number_color):
		push_warning("KitData validation failed: number_color has invalid RGB channels (must be in [0.0, 1.0] and not NaN).")
		return false
	return true

## Serializes kit data to a standard dictionary representation
func to_dict() -> Dictionary:
	return {
		"team_name": team_name,
		"is_away": is_away,
		"primary_color": primary_color.to_html(true),
		"secondary_color": secondary_color.to_html(true),
		"trim_color": trim_color.to_html(true),
		"number_color": number_color.to_html(true),
		"indicator_color": indicator_color.to_html(true),
		"base_primary_key": base_primary_key.to_html(true),
		"base_secondary_key": base_secondary_key.to_html(true),
		"base_trim_key": base_trim_key.to_html(true)
	}

## Deserializes kit data from a dictionary
func from_dict(data: Dictionary) -> void:
	if data.has("team_name"):
		if data["team_name"] == null:
			team_name = ""
		else:
			team_name = str(data["team_name"])
	if data.has("is_away"):
		var val = data["is_away"]
		if val is bool:
			is_away = val
		elif val is int or val is float:
			is_away = (val != 0)
		elif val is String:
			var s: String = val.to_lower().strip_edges()
			is_away = (s == "true" or s == "1" or s == "yes")
		else:
			is_away = false
	if data.has("primary_color"):
		primary_color = _parse_color(data["primary_color"], primary_color)
	if data.has("secondary_color"):
		secondary_color = _parse_color(data["secondary_color"], secondary_color)
	if data.has("trim_color"):
		trim_color = _parse_color(data["trim_color"], trim_color)
	if data.has("number_color"):
		number_color = _parse_color(data["number_color"], number_color)
	if data.has("indicator_color"):
		indicator_color = _parse_color(data["indicator_color"], indicator_color)
	if data.has("base_primary_key"):
		base_primary_key = _parse_color(data["base_primary_key"], base_primary_key)
	if data.has("base_secondary_key"):
		base_secondary_key = _parse_color(data["base_secondary_key"], base_secondary_key)
	if data.has("base_trim_key"):
		base_trim_key = _parse_color(data["base_trim_key"], base_trim_key)

## Returns the effective color for the base ring indicator under feet
func get_effective_indicator_color() -> Color:
	if indicator_color.a > 0.0:
		return indicator_color
	return Color(primary_color.r, primary_color.g, primary_color.b, 0.88)

## Applies kit colors to a given ShaderMaterial
func apply_to_material(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	# Standard naming
	mat.set_shader_parameter("source_primary", base_primary_key)
	mat.set_shader_parameter("source_secondary", base_secondary_key)
	mat.set_shader_parameter("source_trim", base_trim_key)
	mat.set_shader_parameter("target_primary", primary_color)
	mat.set_shader_parameter("target_secondary", secondary_color)
	mat.set_shader_parameter("target_trim", trim_color)
	# Compatibility aliases (e.g. COLOR_REPLACE_SRC_1)
	mat.set_shader_parameter("COLOR_REPLACE_SRC_1", base_primary_key)
	mat.set_shader_parameter("COLOR_REPLACE_DST_1", primary_color)
	mat.set_shader_parameter("COLOR_REPLACE_SRC_2", base_secondary_key)
	mat.set_shader_parameter("COLOR_REPLACE_DST_2", secondary_color)

## Clones this kit data resource
func duplicate_kit() -> KitData:
	var copy = KitData.new()
	copy.team_name = team_name
	copy.is_away = is_away
	copy.primary_color = primary_color
	copy.secondary_color = secondary_color
	copy.trim_color = trim_color
	copy.number_color = number_color
	copy.indicator_color = indicator_color
	copy.base_primary_key = base_primary_key
	copy.base_secondary_key = base_secondary_key
	copy.base_trim_key = base_trim_key
	return copy

func _parse_color(val: Variant, default_color: Color) -> Color:
	if val is Color:
		return val
	if val is String:
		var c = Color.from_string(val, default_color)
		return c
	return default_color

func _is_valid_color(c: Color) -> bool:
	if c.a <= 0.0 or is_nan(c.a) or is_inf(c.a):
		return false
	if is_nan(c.r) or is_nan(c.g) or is_nan(c.b):
		return false
	if is_inf(c.r) or is_inf(c.g) or is_inf(c.b):
		return false
	if c.r < 0.0 or c.r > 1.0 or c.g < 0.0 or c.g > 1.0 or c.b < 0.0 or c.b > 1.0:
		return false
	return true
