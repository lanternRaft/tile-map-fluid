shader_type canvas_item;
render_mode unshaded;

uniform vec4 water_tint : source_color = vec4(0.14, 0.48, 0.58, 0.55);
uniform sampler2D wetness_field : filter_nearest, repeat_disable;
uniform sampler2D patch_table : filter_nearest, repeat_disable;
varying vec4 saturation;
varying vec2 field_uv;

ivec2 address(int index, int width) {
	return ivec2(index % width, index / width);
}

float contact(float index) {
	return texelFetch(wetness_field,
		address(int(index), textureSize(wetness_field, 0).x), 0).r;
}

void vertex() {
	int slot = int(UV.x);
	int width = textureSize(patch_table, 0).x;
	vec4 corners = texelFetch(patch_table, address(slot, width), 0);
	vec4 domain = texelFetch(patch_table, address(slot + 1, width), 0);
	saturation = vec4(contact(corners.r), contact(corners.g),
		contact(corners.b), contact(corners.a));
	field_uv = (VERTEX - domain.xy) / domain.zw;
}

void fragment() {
	float top = mix(saturation.r, saturation.g, field_uv.x);
	float bottom = mix(saturation.b, saturation.a, field_uv.x);
	float wetness = mix(top, bottom, field_uv.y);
	COLOR = texture(TEXTURE, field_uv) * water_tint;
	COLOR.a *= wetness;
}
