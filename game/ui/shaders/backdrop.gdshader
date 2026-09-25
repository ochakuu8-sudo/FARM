shader_type canvas_item;
// 画面の地：上の中ほどにごく弱い明かり、四隅は暗く、細かな粒を少しだけ。
uniform vec4 base : source_color = vec4(0.055, 0.037, 0.045, 1.0);
uniform vec4 glow : source_color = vec4(0.30, 0.08, 0.11, 1.0);
uniform float grain = 0.02;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec2 d = (uv - vec2(0.5, 0.18)) * vec2(1.0, 1.6);
	float light = exp(-dot(d, d) * 2.2);
	vec2 v = uv - 0.5;
	float vig = smoothstep(0.95, 0.25, length(v * vec2(1.0, 1.25)));
	vec3 col = mix(base.rgb, glow.rgb, light * 0.55);
	col *= mix(0.55, 1.0, vig);
	col += (hash(FRAGCOORD.xy) - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
