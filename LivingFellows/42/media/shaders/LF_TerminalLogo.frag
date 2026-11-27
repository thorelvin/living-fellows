// SPDX-License-Identifier: MIT
#version 330
uniform sampler2D DIFFUSE;
uniform float PaletteR;
uniform float PaletteG;
uniform float PaletteB;
uniform float KeyR;
uniform float KeyG;
uniform float KeyB;
uniform float Keyed;
uniform float Monochrome;
uniform float DarkInk;
in vec4 col;
in vec2 texCoord;
void main() {
    vec4 sampleColor = texture(DIFFUSE, texCoord);
    if (Keyed > 0.5) {
        float delta = length(sampleColor.rgb - vec3(KeyR, KeyG, KeyB));
        sampleColor.a *= smoothstep(0.025, 0.10, delta);
    }
    if (sampleColor.a < 0.003) discard;
    vec3 phosphor = vec3(PaletteR, PaletteG, PaletteB);
    float high = max(sampleColor.r, max(sampleColor.g, sampleColor.b));
    float low = min(sampleColor.r, min(sampleColor.g, sampleColor.b));
    float luminance = dot(sampleColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    if (Monochrome > 0.5 || high - low < 0.065) {
        float ink = DarkInk > 0.5 ? 1.0-luminance : luminance;
        // Keep small black subtitles visible without flattening a white
        // wordmark and its dark outline into the same ink value.
        float floorInk = DarkInk > 0.5 ? 0.0 : 0.16;
        sampleColor.rgb = phosphor * sqrt(max(floorInk,ink));
    } else {
        float lift = clamp((0.52 - luminance) / max(0.01, 1.0 - luminance), 0.0, 0.65);
        sampleColor.rgb = mix(sampleColor.rgb, vec3(1.0), lift) * (0.84 + 0.16 * phosphor);
    }
    gl_FragColor = sampleColor * col;
}
