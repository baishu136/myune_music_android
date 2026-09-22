#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uMotion;
uniform float uDim;
uniform float uPaletteMix;
uniform vec4 uSource0;
uniform vec4 uSource1;
uniform vec4 uSource2;
uniform vec4 uSource3;
uniform vec4 uTarget0;
uniform vec4 uTarget1;
uniform vec4 uTarget2;
uniform vec4 uTarget3;

out vec4 fragColor;

float colourField(vec2 point, vec2 center, vec2 radius) {
  vec2 delta = (point - center) / radius;
  return exp(-dot(delta, delta) * 0.74);
}

float interleavedGradientNoise(vec2 pixel) {
  return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

void main() {
  vec2 size = max(uSize, vec2(1.0));
  vec2 uv = FlutterFragCoord().xy / size;
  float phase = uTime;
  float motion = clamp(uMotion, 0.0, 1.0);
  // Salt Player's reference has broad colour fronts that sweep sideways
  // through the whole viewport. Bend the x coordinate by y so those fronts
  // remain organic, while keeping the displacement low-frequency and smooth.
  // Use one spatial wave per axis. The previous overlapping harmonics could
  // form a repeated interference pattern after display scaling or recording.
  float horizontalBend = sin(uv.y * 2.10 + phase * 0.31) * 0.090;
  float verticalDrift = cos(uv.x * 1.75 - phase * 0.19) * 0.022;
  vec2 warped = uv + motion * vec2(horizontalBend, verticalDrift);

  // Quintic smootherstep gives song changes zero velocity and acceleration at
  // both ends, avoiding the visible snap of a linear or cubic colour swap.
  float p = clamp(uPaletteMix, 0.0, 1.0);
  float paletteMix = p * p * p * (p * (p * 6.0 - 15.0) + 10.0);
  vec3 c0 = mix(uSource0.rgb, uTarget0.rgb, paletteMix);
  vec3 c1 = mix(uSource1.rgb, uTarget1.rgb, paletteMix);
  vec3 c2 = mix(uSource2.rgb, uTarget2.rgb, paletteMix);
  vec3 c3 = mix(uSource3.rgb, uTarget3.rgb, paletteMix);
  // Keep four broad fronts distributed through the viewport. Their bounded
  // travel guarantees that no main colour can move completely off-screen,
  // while unequal phases prevent a static four-band appearance.
  vec2 p0 = vec2(0.08 + sin(phase * 0.23) * 0.16 * motion,
                 0.16 + cos(phase * 0.17) * 0.10 * motion);
  vec2 p1 = vec2(0.38 + sin(phase * 0.19 + 1.7) * 0.18 * motion,
                 0.40 + sin(phase * 0.13 + 0.6) * 0.12 * motion);
  vec2 p2 = vec2(0.70 + sin(phase * 0.17 + 3.2) * 0.18 * motion,
                 0.66 + cos(phase * 0.11 + 1.8) * 0.11 * motion);
  vec2 p3 = vec2(0.94 + sin(phase * 0.29 + 4.5) * 0.16 * motion,
                 0.88 + sin(phase * 0.07 + 2.7) * 0.09 * motion);

  // Every retained colour has equal mixing mass. Extraction percentages are
  // intentionally ignored so a dominant cover colour cannot erase accents.
  float w0 = 0.010 + colourField(warped, p0, vec2(0.40, 0.72));
  float w1 = 0.010 + colourField(warped, p1, vec2(0.38, 0.68));
  float w2 = 0.010 + colourField(warped, p2, vec2(0.38, 0.70));
  float w3 = 0.010 + colourField(warped, p3, vec2(0.40, 0.74));
  float total = max(w0 + w1 + w2 + w3, 0.001);
  vec3 color = (c0 * w0 + c1 * w1 + c2 * w2 + c3 * w3) / total;

  float vignette = smoothstep(0.98, 0.18, distance(uv, vec2(0.5)));
  color *= mix(0.88, 1.0, vignette);
  color *= 1.0 - clamp(uDim, 0.2, 0.9) * 0.58;
  // A static sub-LSB dither breaks up visible 8-bit gradient bands without
  // adding animated grain, texture sampling, or another rendering pass.
  float dither = (interleavedGradientNoise(FlutterFragCoord().xy) - 0.5) *
      (0.70 / 255.0);
  color += vec3(dither);
  color = clamp(color, vec3(0.0), vec3(1.0));
  fragColor = vec4(color, 1.0);
}
