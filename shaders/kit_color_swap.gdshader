shader_type canvas_item;
render_mode blend_mix;

// Base palette reference keys to identify in the source sprite
uniform vec4 source_primary : source_color = vec4(0.949, 0.788, 0.298, 1.0);
uniform vec4 source_secondary : source_color = vec4(0.184, 0.502, 0.929, 1.0);
uniform vec4 source_trim : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Target replacement colors from KitData
uniform vec4 target_primary : source_color = vec4(0.949, 0.788, 0.298, 1.0);
uniform vec4 target_secondary : source_color = vec4(0.184, 0.502, 0.929, 1.0);
uniform vec4 target_trim : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Compatibility uniforms (interface contract alias)
uniform vec4 COLOR_REPLACE_SRC_1 : source_color = vec4(0.0);
uniform vec4 COLOR_REPLACE_DST_1 : source_color = vec4(0.0);
uniform vec4 COLOR_REPLACE_SRC_2 : source_color = vec4(0.0);
uniform vec4 COLOR_REPLACE_DST_2 : source_color = vec4(0.0);

// Sensitivity and shading preservation parameters
uniform float color_tolerance : hint_range(0.01, 0.50) = 0.20;
uniform float luminance_blend : hint_range(0.0, 1.0) = 0.85;

// Standard ITU-R BT.601 luminance calculation
float get_luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Redmean perceptual color distance normalized
float color_distance(vec3 c1, vec3 c2) {
	vec3 diff = c1 - c2;
	float r_mean = 0.5 * (c1.r + c2.r);
	vec3 weights = vec3(2.0 + r_mean, 4.0, 3.0 - r_mean);
	return sqrt(dot(weights, diff * diff)) / 3.0;
}

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Preserve transparency
	if (tex_color.a < 0.01) {
		COLOR = tex_color;
		discard;
	}
	
	vec3 rgb = tex_color.rgb;
	float pixel_lum = get_luminance(rgb);
	vec3 final_rgb = rgb;
	
	// Resolve active sources and targets
	vec3 src_prim = COLOR_REPLACE_SRC_1.a > 0.0 ? COLOR_REPLACE_SRC_1.rgb : source_primary.rgb;
	vec3 dst_prim = COLOR_REPLACE_DST_1.a > 0.0 ? COLOR_REPLACE_DST_1.rgb : target_primary.rgb;
	vec3 src_sec = COLOR_REPLACE_SRC_2.a > 0.0 ? COLOR_REPLACE_SRC_2.rgb : source_secondary.rgb;
	vec3 dst_sec = COLOR_REPLACE_DST_2.a > 0.0 ? COLOR_REPLACE_DST_2.rgb : target_secondary.rgb;
	vec3 src_trm = source_trim.rgb;
	vec3 dst_trm = target_trim.rgb;
	
	float d_prim = color_distance(rgb, src_prim);
	float d_sec  = color_distance(rgb, src_sec);
	float d_trm  = color_distance(rgb, src_trm);
	
	// Protect skin tones (warm peach/tan/brown where R > G > B with moderate blue channel)
	bool is_skin = (rgb.r > rgb.g + 0.08) && (rgb.g > rgb.b + 0.04) && (rgb.b > 0.34) && (rgb.r < 0.98);
	
	// Determine best matching channel within tolerance
	if (!is_skin && d_prim < color_tolerance && d_prim <= d_sec && d_prim <= d_trm) {
		float base_lum = max(0.001, get_luminance(src_prim));
		float lum_ratio = clamp(pixel_lum / base_lum, 0.0, 3.0);
		vec3 shaded_target = dst_prim * mix(1.0, lum_ratio, luminance_blend);
		float weight = 1.0 - smoothstep(color_tolerance * 0.35, color_tolerance, d_prim);
		final_rgb = mix(final_rgb, shaded_target, weight);
	} else if (!is_skin && d_sec < color_tolerance && d_sec <= d_prim && d_sec <= d_trm) {
		float base_lum = max(0.001, get_luminance(src_sec));
		float lum_ratio = clamp(pixel_lum / base_lum, 0.0, 3.0);
		vec3 shaded_target = dst_sec * mix(1.0, lum_ratio, luminance_blend);
		float weight = 1.0 - smoothstep(color_tolerance * 0.35, color_tolerance, d_sec);
		final_rgb = mix(final_rgb, shaded_target, weight);
	} else if (!is_skin && d_trm < color_tolerance * 0.55 && d_trm <= d_prim && d_trm <= d_sec) {
		float base_lum = max(0.001, get_luminance(src_trm));
		float lum_ratio = clamp(pixel_lum / base_lum, 0.0, 3.0);
		vec3 shaded_target = dst_trm * mix(1.0, lum_ratio, luminance_blend);
		float weight = 1.0 - smoothstep(color_tolerance * 0.35, color_tolerance, d_trm);
		final_rgb = mix(final_rgb, shaded_target, weight);
	}
	
	COLOR = vec4(clamp(final_rgb, 0.0, 1.0), tex_color.a);
}
