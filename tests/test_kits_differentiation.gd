class_name TestKitsDifferentiation
extends "res://tests/base_test.gd"

const KitDataScript = preload("res://resources/kits/KitData.gd")
const ColorClashDetectorScript = preload("res://scripts/kits/ColorClashDetector.gd")
const BaseIndicator2DScript = preload("res://scripts/kits/BaseIndicator2D.gd")

func _init() -> void:
	super()
	suite_name = "KitsDifferentiation"

func run_all() -> void:
	test_tier_1_feature_coverage()
	test_tier_2_boundary_cases()
	test_tier_3_cross_feature_interactions()

## Tier 1: Feature Coverage
func test_tier_1_feature_coverage() -> void:
	set_tier(1)
	
	# 1. Project configuration checks
	var viewport_w = ProjectSettings.get_setting("display/window/size/viewport_width")
	var viewport_h = ProjectSettings.get_setting("display/window/size/viewport_height")
	var stretch_mode = ProjectSettings.get_setting("display/window/stretch/mode")
	var stretch_aspect = ProjectSettings.get_setting("display/window/stretch/aspect")
	var tex_filter = ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")
	var renderer = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	
	assert_eq(viewport_w, 1280, "Window viewport width is 1280")
	assert_eq(viewport_h, 720, "Window viewport height is 720")
	assert_eq(stretch_mode, "canvas_items", "Stretch mode is canvas_items")
	assert_eq(stretch_aspect, "keep", "Stretch aspect is keep")
	assert_eq(tex_filter, 0, "Default texture filter is nearest (0)")
	assert_eq(renderer, "gl_compatibility", "Renderer is gl_compatibility")
	
	# 2. KitData class instantiation, properties & serialization
	var kit = KitDataScript.new()
	assert_not_null(kit, "KitData instantiated successfully")
	kit.team_name = "Inazuma Japan"
	kit.is_away = false
	kit.primary_color = Color("#2F80ED")
	kit.secondary_color = Color("#F2C94C")
	kit.trim_color = Color.WHITE
	kit.number_color = Color.BLACK
	
	assert_true(kit.validate(), "KitData.validate() passes on valid kit")
	var kit_dict = kit.to_dict()
	assert_eq(kit_dict["team_name"], "Inazuma Japan", "to_dict preserves team_name")
	assert_eq(kit_dict["is_away"], false, "to_dict preserves is_away")
	
	var restored_kit = KitDataScript.new()
	restored_kit.from_dict(kit_dict)
	assert_eq(restored_kit.team_name, "Inazuma Japan", "from_dict restores team_name")
	assert_color_almost_eq(restored_kit.primary_color, Color("#2F80ED"), 0.01, "from_dict restores primary_color")
	
	var duplicated = kit.duplicate_kit()
	assert_eq(duplicated.team_name, kit.team_name, "duplicate_kit copies team_name")
	assert_color_almost_eq(duplicated.secondary_color, kit.secondary_color, 0.01, "duplicate_kit copies secondary_color")
	
	var invalid_kit = KitDataScript.new()
	invalid_kit.team_name = ""
	assert_false(invalid_kit.validate(), "KitData.validate() fails on empty team_name")
	
	# 3. Sample kit resources loading (.tres)
	var sample_kits = [
		{"path": "res://resources/kits/kit_raimon_home.tres", "name": "Raimon", "away": false},
		{"path": "res://resources/kits/kit_raimon_away.tres", "name": "Raimon", "away": true},
		{"path": "res://resources/kits/kit_royal_home.tres", "name": "Royal Academy", "away": false},
		{"path": "res://resources/kits/kit_royal_away.tres", "name": "Royal Academy", "away": true}
	]
	
	for s in sample_kits:
		assert_true(ResourceLoader.exists(s["path"]), "Resource exists: " + s["path"])
		var k = ResourceLoader.load(s["path"]) as KitData
		assert_not_null(k, "Resource loads as KitData: " + s["path"])
		if k:
			assert_true(k.validate(), "Resource validation passes: " + s["path"])
			assert_eq(k.team_name, s["name"], "Team name matches: " + s["name"])
			assert_eq(k.is_away, s["away"], "is_away flag matches: " + str(s["away"]))
			assert_in_range(k.primary_color.a, 0.9, 1.0, "primary_color alpha is valid")
			assert_in_range(k.secondary_color.a, 0.9, 1.0, "secondary_color alpha is valid")
			assert_in_range(k.trim_color.a, 0.9, 1.0, "trim_color alpha is valid")
			assert_in_range(k.number_color.a, 0.9, 1.0, "number_color alpha is valid")
	
	# 4. Shader file existence and uniforms
	var shader_path = "res://shaders/kit_color_swap.gdshader"
	assert_true(FileAccess.file_exists(shader_path), "Shader file exists at " + shader_path)
	var shader_res = ResourceLoader.load(shader_path) as Shader
	assert_not_null(shader_res, "Shader resource loads successfully")
	var shader_file = FileAccess.open(shader_path, FileAccess.READ)
	if shader_file:
		var code = shader_file.get_as_text()
		shader_file.close()
		assert_true(code.contains("shader_type canvas_item;"), "Shader type is canvas_item")
		assert_true(code.contains("source_primary"), "Shader declares source_primary uniform")
		assert_true(code.contains("target_primary"), "Shader declares target_primary uniform")
		assert_true(code.contains("COLOR_REPLACE_SRC_1"), "Shader provides COLOR_REPLACE_SRC_1 alias")
		assert_true(code.contains("COLOR_REPLACE_DST_1"), "Shader provides COLOR_REPLACE_DST_1 alias")
		assert_true(code.contains("luminance_blend"), "Shader declares luminance_blend uniform")
		assert_true(code.contains("color_distance"), "Shader implements color_distance function")
	
	# Test shader material assignment
	var mat = ShaderMaterial.new()
	mat.shader = shader_res
	var raimon_home = ResourceLoader.load("res://resources/kits/kit_raimon_home.tres") as KitData
	raimon_home.apply_to_material(mat)
	assert_not_null(mat.get_shader_parameter("target_primary"), "target_primary set via apply_to_material")
	assert_not_null(mat.get_shader_parameter("COLOR_REPLACE_DST_1"), "COLOR_REPLACE_DST_1 set via apply_to_material")
	
	# 5. Redmean color distance calculation against theoretical values
	# Pure Green vs Black: r_mean = 0, delta_sq = 4.0, sqrt(4)/3 = 2/3 ≈ 0.6667
	var d_green = ColorClashDetectorScript.calculate_color_distance(Color(0, 1, 0), Color.BLACK)
	assert_almost_eq(d_green, 2.0 / 3.0, 0.001, "Redmean pure Green from Black = 2/3")
	
	# Pure Blue vs Black: r_mean = 0, delta_sq = 3.0, sqrt(3)/3 ≈ 0.57735
	var d_blue = ColorClashDetectorScript.calculate_color_distance(Color(0, 0, 1), Color.BLACK)
	assert_almost_eq(d_blue, sqrt(3.0) / 3.0, 0.001, "Redmean pure Blue from Black = sqrt(3)/3")
	assert_true(d_green > d_blue, "Human perception weight: Green distance > Blue distance")
	
	# 6. BaseIndicator2D presence and properties
	var indicator = BaseIndicator2DScript.new()
	assert_not_null(indicator, "BaseIndicator2D instantiated")
	assert_almost_eq(indicator.outer_radius, 14.0, 0.1, "Default outer_radius is 14.0")
	assert_almost_eq(indicator.inner_radius, 10.0, 0.1, "Default inner_radius is 10.0")
	assert_almost_eq(indicator.ring_width, 2.4, 0.1, "Default ring_width is 2.4")
	assert_true(indicator.is_ellipse, "Default is_ellipse is true")
	
	indicator.set_team_color(Color.RED)
	assert_color_almost_eq(indicator.team_color, Color.RED, 0.01, "set_team_color updates team_color")
	
	indicator.set_indicator_radii(16.0, 11.0)
	assert_almost_eq(indicator.outer_radius, 16.0, 0.1, "outer_radius updated")
	assert_almost_eq(indicator.inner_radius, 11.0, 0.1, "inner_radius updated")
	
	indicator.set_selection_state(true, false)
	assert_true(indicator.is_controlled, "is_controlled flag set")
	assert_false(indicator.is_pass_target, "is_pass_target flag false")
	indicator.free()

## Tier 2: Boundary Cases
func test_tier_2_boundary_cases() -> void:
	set_tier(2)
	
	# 1. Identical colors -> distance == 0.0
	var test_palette = [
		Color.BLACK,
		Color.WHITE,
		Color.RED,
		Color.GREEN,
		Color.BLUE,
		Color("#F2C94C"),
		Color("#2F80ED"),
		Color("#219653")
	]
	for col in test_palette:
		var d = ColorClashDetectorScript.calculate_color_distance(col, col)
		assert_almost_eq(d, 0.0, 0.00001, "Identical color distance must be 0.0")
	
	# 2. Maximum distance: Black (0,0,0) vs White (1,1,1) -> 1.0
	var max_dist = ColorClashDetectorScript.calculate_color_distance(Color.BLACK, Color.WHITE)
	assert_almost_eq(max_dist, 1.0, 0.0001, "Black vs White normalized distance is exactly 1.0")
	
	# Symmetry check
	var d_ab = ColorClashDetectorScript.calculate_color_distance(Color(0.2, 0.7, 0.3), Color(0.8, 0.1, 0.9))
	var d_ba = ColorClashDetectorScript.calculate_color_distance(Color(0.8, 0.1, 0.9), Color(0.2, 0.7, 0.3))
	assert_almost_eq(d_ab, d_ba, 0.0001, "Color distance must be symmetric")
	
	# 3. Clash threshold tau = 0.38 auto-swap trigger
	var kit_base = KitDataScript.new()
	kit_base.team_name = "Base"
	kit_base.primary_color = Color("#F2C94C")
	kit_base.secondary_color = Color("#2F80ED")
	
	# Identical kits must clash
	assert_true(ColorClashDetectorScript.is_clashing(kit_base, kit_base), "Identical kits must clash")
	
	# Near identical kit (distance < 0.38)
	var kit_near = KitDataScript.new()
	kit_near.team_name = "Near Rival"
	kit_near.primary_color = Color("#E6BE43") # Slightly darker yellow
	kit_near.secondary_color = Color("#2975D8")
	var dist_near = ColorClashDetectorScript.calculate_kit_distance(kit_base, kit_near)
	assert_true(dist_near < 0.38, "Distance must be < 0.38 (got %.4f)" % dist_near)
	assert_true(ColorClashDetectorScript.is_clashing(kit_base, kit_near), "Near yellow kit must clash")
	
	# High contrast kit (distance >= 0.38)
	var kit_far = KitDataScript.new()
	kit_far.team_name = "Far Rival"
	kit_far.primary_color = Color("#111827") # Very dark slate
	kit_far.secondary_color = Color("#E11D48") # Crimson
	var dist_far = ColorClashDetectorScript.calculate_kit_distance(kit_base, kit_far)
	assert_true(dist_far >= 0.38, "Distance must be >= 0.38 (got %.4f)" % dist_far)
	assert_false(ColorClashDetectorScript.is_clashing(kit_base, kit_far), "Contrasting kit must not clash")

## Tier 3: Cross-Feature Interactions
func test_tier_3_cross_feature_interactions() -> void:
	set_tier(3)
	
	# Raimon Home vs Rival wearing Yellow
	var raimon_home = ResourceLoader.load("res://resources/kits/kit_raimon_home.tres") as KitData
	assert_not_null(raimon_home, "Raimon home should load")
	
	var rival_home = KitDataScript.new()
	rival_home.team_name = "Zeus"
	rival_home.is_away = false
	rival_home.primary_color = Color("#F2C94C") # Clashing Yellow
	rival_home.secondary_color = Color("#2F80ED")
	
	var rival_away = KitDataScript.new()
	rival_away.team_name = "Zeus"
	rival_away.is_away = true
	rival_away.primary_color = Color("#1E293B") # Slate Blue away kit
	rival_away.secondary_color = Color("#F8FAFC") # White
	
	# 1. Arbitrate kits: should detect clash and swap away kit
	var arbitration = ColorClashDetectorScript.arbitrate_kits(raimon_home, rival_home, rival_away)
	assert_true(arbitration["clash_detected"], "Clash detected between two yellow home kits")
	assert_true(arbitration["swapped"], "Kit swapped to alternative away kit")
	assert_eq(arbitration["away_kit"], rival_away, "Selected away kit is rival_away")
	
	# 2. Update BaseIndicator2D with selected away kit
	var indicator = BaseIndicator2DScript.new()
	var selected_kit: KitData = arbitration["away_kit"]
	var effective_color = selected_kit.get_effective_indicator_color()
	indicator.set_team_color(effective_color)
	
	assert_color_almost_eq(indicator.team_color, effective_color, 0.01, "Indicator color updated from resolved kit")
	assert_color_almost_eq(indicator.team_color, Color("#1E293B"), 0.15, "Indicator reflects slate away kit")
	
	# 3. Non-clashing matchup: Raimon Home (Yellow) vs Royal Home (Dark Green)
	var royal_home = ResourceLoader.load("res://resources/kits/kit_royal_home.tres") as KitData
	var royal_away = ResourceLoader.load("res://resources/kits/kit_royal_away.tres") as KitData
	var royal_arb = ColorClashDetectorScript.arbitrate_kits(raimon_home, royal_home, royal_away)
	assert_false(royal_arb["clash_detected"], "Royal Green vs Raimon Yellow does not clash")
	assert_false(royal_arb["swapped"], "No kit swap when kits are distinct")
	assert_eq(royal_arb["away_kit"], royal_home, "Royal keeps home kit")
	
	indicator.free()
