shader_type canvas_item;
render_mode unshaded;

uniform vec4 water_tint : source_color = vec4(0.14, 0.48, 0.58, 0.55);
uniform bool use_patch_water = false;
uniform vec4 patch_saturation = vec4(0.0);
varying vec4 saturation;
varying vec2 field_uv;

void vertex() {
	saturation = use_patch_water ? patch_saturation : INSTANCE_CUSTOM;
	field_uv = VERTEX + vec2(0.5);
}

void fragment() {
	float top = mix(saturation.r, saturation.g, field_uv.x);
	float bottom = mix(saturation.b, saturation.a, field_uv.x);
	float wetness = mix(top, bottom, field_uv.y);
	COLOR = texture(TEXTURE, field_uv) * water_tint;
	COLOR.a *= wetness;
}
