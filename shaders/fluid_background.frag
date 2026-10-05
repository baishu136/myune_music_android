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

// A plateau core and finite, C1-continuous edge. A core's pigment is painted
// at full opacity, not averaged with every other field on the screen.
float fluidBlobMask(vec2 point, vec2 center, vec2 radius, float outer) {
  vec2 delta = (point - center) / radius;
  float d2 = dot(delta, delta);
  return 1.0 - smoothstep(0.10, outer, d2);
}

float interleavedGradientNoise(vec2 pixel) {
  return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

void main() {
  vec2 size = max(uSize, vec2(1.0));
  vec2 uv = FlutterFragCoord().xy / size;
  // uTime is visible, unblocked wall-clock seconds. One orbit = 96.66s;
  // integer temporal harmonics preserve continuity at the Dart clock wrap.
  float phase = uTime * 0.065;
  float motion = clamp(uMotion, 0.0, 1.0);
  // Large-scale silk folds, never a high-frequency stripe/noise texture.
  vec2 firstWarp = vec2(sin(uv.y * 1.8 + phase),
                        cos(uv.x * 2.0 - phase));
  vec2 secondWarp = vec2(
      cos(uv.x * 1.6 + firstWarp.y * 0.6 - phase),
      sin(uv.y * 2.2 + firstWarp.x * 0.6 + phase));
  vec2 warped = uv + motion * (firstWarp * 0.10 + secondWarp * 0.055);

  // Quintic smootherstep gives song changes zero velocity and acceleration at
  // both ends, avoiding the visible snap of a linear or cubic colour swap.
  float palettePhase = clamp(uPaletteMix, 0.0, 1.0);
  float paletteMix = palettePhase * palettePhase * palettePhase *
      (palettePhase * (palettePhase * 6.0 - 15.0) + 10.0);
  vec3 base = mix(uSourceBase.rgb, uTargetBase.rgb, paletteMix);
  vec3 blob1 = mix(uSource1.rgb, uTarget1.rgb, paletteMix);
  vec3 blob2 = mix(uSource3.rgb, uTarget3.rgb, paletteMix);
  vec3 ambient = mix(uSource2.rgb, uTarget2.rgb, paletteMix);
  // Two independently phased diagonal orbits, not four symmetric lights.
  vec2 p1 = vec2(0.26 + sin(phase) * 0.32 * motion,
                 0.28 + sin(phase + 0.35) * 0.32 * motion);
  vec2 p2 = vec2(0.78 + sin(phase + 2.4) * 0.30 * motion,
                 0.74 + sin(phase + 2.85) * 0.30 * motion);
  vec2 pa = vec2(0.48 + cos(phase + 1.3) * 0.12 * motion,
                 0.50 + sin(phase + 1.3) * 0.10 * motion);
  float mask1 = fluidBlobMask(warped, p1, vec2(0.62, 0.78), 1.0);
  float mask2 = fluidBlobMask(warped, p2, vec2(0.55, 0.70), 1.0);
  float ambientMask = fluidBlobMask(warped, pa, vec2(1.10, 1.0), 1.6) * 0.16;
  // Fixed layer order: canvas -> diffuse tint -> blob 1 -> blob 2.
  // Ambient cannot bleach an opaque core. No energy sum or weight division.
  vec3 color = mix(base, ambient, ambientMask);
  color = mix(color, blob1, mask1);
  color = mix(color, blob2, mask2);
  // Preserve the existing 48-float ABI; slot 0 / glow are legacy metadata,
  // not additional lights. Dark artwork's base is finally consumed directly.

  // Defined GLSL smoothstep: edge0 must be less than edge1.
  float vignette = 1.0 - smoothstep(0.35, 1.10, distance(uv, vec2(0.5, 0.48)));
  color *= mix(0.98, 1.00, vignette);
  color *= 1.0 - clamp(uDim, 0.0, 0.60) * 0.25;
  // A static sub-LSB dither breaks up visible 8-bit gradient bands without
  // adding animated grain, texture sampling, or another rendering pass.
  float dither = (interleavedGradientNoise(FlutterFragCoord().xy) - 0.5) *
      (0.70 / 255.0);
  color += vec3(dither);
  color = clamp(color, vec3(0.0), vec3(1.0));
  fragColor = vec4(color, 1.0);
}
