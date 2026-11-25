shader_type canvas_item;

void fragment() {
	vec4 pixel = texture(TEXTURE, UV) * COLOR;
	vec3 hsv = rgb_to_hsv(pixel.rgb);
	// Farg hele dressjakken, skjorten og slipset som én oransje fangedrakt.
	// Ansikt, hår, hender og kontur beholdes fra originalspriten.
	bool torso = UV.y > 0.54 && UV.y < 0.84 && UV.x > 0.36 && UV.x < 0.66;
	bool blue_suit = hsv.x > 0.52 && hsv.x < 0.76 && hsv.y > 0.22;
	bool pale_shirt = UV.x > 0.45 && UV.x < 0.57 && hsv.y < 0.24 && hsv.z > 0.42;
	bool red_tie = UV.x > 0.47 && UV.x < 0.56 && hsv.x < 0.035 && hsv.y > 0.45;
	if (pixel.a > 0.05 && torso && (blue_suit || pale_shirt || red_tie)) {
		hsv.x = 0.075;
		hsv.y = 0.88;
		pixel.rgb = hsv_to_rgb(hsv);
	}
	COLOR = pixel;
}
