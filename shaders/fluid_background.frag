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
uniform vec4 uSourceBase;
uniform vec4 uTargetBase;
uniform float uSourceGlow;
uniform float uTargetGlow;

out vec4 fragColor;

float colourField(vec2 point, vec2 center, vec2 radius) {
  vec2 delta = (point - center) / radius;
  return exp(-pow(max(dot(delta, delta), 0.00001), 0.65) * 1.25);
}

float interleavedGradientNoise(vec2 pixel) {
  return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

void main() {
  vec2 size = max(uSize, vec2(1.0));
  vec2 uv = FlutterFragCoord().xy / size;
  float t = uTime * 0.28;
  float phase = t;
  float motion = clamp(uMotion, 0.0, 1.0);
  // Nested low-spatial-frequency warps, not overlapping periodic stripes.
  // Temporal coefficients are integer hundredths. Dart wraps uTime at
  // 200π / .28, so the slowed phase still wraps seamlessly.
  vec2 firstWarp = vec2(sin(uv.y * 2.8 + phase * 0.31),
                        cos(uv.x * 2.2 - phase * 0.19));
  vec2 secondWarp = vec2(
      cos(uv.x * 2.3 + firstWarp.y * 0.8 - phase * 0.22),
      sin(uv.y * 2.0 + firstWarp.x * 0.7 + phase * 0.27));
  vec2 warped = uv + motion * (firstWarp * 0.11 + secondWarp * 0.065);

  // Quintic smootherstep gives song changes zero velocity and acceleration at
  // both ends, avoiding the visible snap of a linear or cubic colour swap.
  float p = clamp(uPaletteMix, 0.0, 1.0);
  float paletteMix = p * p * p * (p * (p * 6.0 - 15.0) + 10.0);
  vec3 c0 = mix(uSource0.rgb, uTarget0.rgb, paletteMix);
  vec3 c1 = mix(uSource1.rgb, uTarget1.rgb, paletteMix);
  vec3 c2 = mix(uSource2.rgb, uTarget2.rgb, paletteMix);
  vec3 c3 = mix(uSource3.rgb, uTarget3.rgb, paletteMix);
  // Distributed anchors + wide independent orbits. At the default clock rate
  // each axis now takes ~76–109s at the ambient clock rate.
  vec2 p0 = vec2(0.28 + sin(phase * 0.23) * 0.32 * motion,
                 0.24 + cos(phase * 0.19) * 0.30 * motion);
  vec2 p1 = vec2(0.72 + sin(phase * 0.21 + 1.7) * 0.34 * motion,
                 0.32 + sin(phase * 0.26 + 0.6) * 0.32 * motion);
  vec2 p2 = vec2(0.30 + cos(phase * 0.25 + 3.2) * 0.34 * motion,
                 0.76 + sin(phase * 0.18 + 1.8) * 0.30 * motion);
  vec2 p3 = vec2(0.74 + sin(phase * 0.20 + 4.5) * 0.32 * motion,
                 0.74 + cos(phase * 0.24 + 2.7) * 0.32 * motion);

  float w0 = colourField(warped, p0, vec2(0.85, 1.05));
  float w1 = colourField(warped, p1, vec2(0.80, 0.95));
  float w2 = colourField(warped, p2, vec2(0.75, 0.95));
  float w3 = colourField(warped, p3, vec2(0.80, 1.00));
  float glow = clamp(mix(uSourceGlow, uTargetGlow, paletteMix), 0.0, 1.0);
  vec3 base = mix(uSourceBase.rgb, uTargetBase.rgb, paletteMix);
  // Screen energy above an independent dark base, not a normalised average
  // of complementary pigments. Do not square the field: it would undo the
  // broad diffusion. Cap each channel's energy to keep Screen transmission
  // non-negative even for a saturated warm field amplified above unity.
  vec3 transmission = (1.0 - min(c0 * w0 * glow, vec3(0.98))) *
                      (1.0 - min(c1 * w1 * glow, vec3(0.98))) *
                      (1.0 - min(c2 * w2 * glow * 1.35, vec3(0.98))) *
                      (1.0 - min(c3 * w3 * glow * 1.15, vec3(0.98)));
  vec3 color = 1.0 - (1.0 - base) * transmission;

  // Defined GLSL smoothstep: edge0 must be less than edge1.
  float vignette = 1.0 - smoothstep(0.35, 1.10, distance(uv, vec2(0.5, 0.48)));
  color *= mix(0.90, 1.05, vignette);
  color *= 1.0 - clamp(uDim, 0.0, 0.60) * 0.25;
  // A static sub-LSB dither breaks up visible 8-bit gradient bands without
  // adding animated grain, texture sampling, or another rendering pass.
  float dither = (interleavedGradientNoise(FlutterFragCoord().xy) - 0.5) *
      (0.70 / 255.0);
  color += vec3(dither);
  color = clamp(color, vec3(0.0), vec3(1.0));
  fragColor = vec4(color, 1.0);
}
