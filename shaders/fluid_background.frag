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

vec2 orbitCentre(float orbit, float phase, float offset, float motion) {
  float angle = phase + offset + 0.14 * motion * sin(2.0 * orbit + offset);
  float radius = 0.26 + motion * (
      0.04 * sin(2.0 * orbit + offset + 0.7) +
      0.015 * sin(3.0 * orbit - offset));
  return vec2(0.50) + radius * vec2(cos(angle), sin(angle) * 1.08);
}

float pigmentWeight(vec2 point, vec2 centre) {
  vec2 delta = (point - centre) / 0.32;
  float falloff = 1.0 / (1.0 + dot(delta, delta));
  return falloff * falloff * falloff;
}

float interleavedGradientNoise(vec2 pixel) {
  return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

void main() {
  vec2 size = max(uSize, vec2(1.0));
  vec2 uv = FlutterFragCoord().xy / size;
  // uTime is visible, unblocked wall-clock seconds. One orbit = 41.89s;
  // integer temporal harmonics preserve continuity at the Dart clock wrap.
  float orbit = uTime * 0.15;
  // Smooth pseudo-random pacing: never replace speed with a per-frame RNG.
  // Integer harmonics preserve position/velocity through the clock wrap.
  // Angular speed is bounded to 0.057..0.243 radians/second (old 0.0975).
  float phase = orbit + 0.32 * sin(orbit) + 0.10 * sin(3.0 * orbit + 1.7);
  float phase2 = orbit + 0.26 * sin(orbit + 2.1) +
      0.09 * sin(4.0 * orbit + 0.8);
  float motion = clamp(uMotion, 0.0, 1.0);
  // Three separated, irregular orbital lanes, never a fixed rainbow strip.
  // Shared circulation plus independent bounded speed/radius modulation keeps
  // centres apart instead of letting one colour swallow another's centre.
  vec2 p0 = orbitCentre(orbit, phase, 0.0, motion);
  vec2 p1 = orbitCentre(orbit, phase, 2.0943951024, motion);
  vec2 p2 = orbitCentre(orbit, phase, 4.1887902048, motion);
  vec2 point = uv + motion * vec2(
      0.055 * sin(uv.y * 2.3 + phase2),
      0.045 * sin(uv.x * 2.0 - phase));
  vec3 weights = vec3(pigmentWeight(point, p0),
                      pigmentWeight(point, p1), pigmentWeight(point, p2));
  weights /= max(weights.x + weights.y + weights.z, 0.00001);

  // Quintic smootherstep gives song changes zero velocity and acceleration at
  // both ends, avoiding the visible snap of a linear or cubic colour swap.
  float palettePhase = clamp(uPaletteMix, 0.0, 1.0);
  float paletteMix = palettePhase * palettePhase * palettePhase *
      (palettePhase * (palettePhase * 6.0 - 15.0) + 10.0);
  vec3 base = mix(uSourceBase.rgb, uTargetBase.rgb, paletteMix);
  vec3 lead = mix(uSource1.rgb, uTarget1.rgb, paletteMix);
  vec3 secondary = mix(uSource3.rgb, uTarget3.rgb, paletteMix);
  vec3 ambient = mix(uSource2.rgb, uTarget2.rgb, paletteMix);
  // Each pigment continuously borrows a little of another real cover colour.
  // Different temporal harmonics avoid simultaneous static colour plateaus;
  // no invented hue wheel, per-frame RNG or periodic hard colour assignment.
  vec3 c0 = mix(lead, ambient, 0.08 + 0.05 * sin(orbit));
  vec3 c1 = mix(ambient, secondary, 0.08 + 0.05 * sin(2.0 * orbit + 1.4));
  vec3 c2 = mix(secondary, lead, 0.08 + 0.05 * sin(3.0 * orbit + 2.1));
  // Equal falloffs partition the canvas with smooth convex colour weights.
  // They do not overlay radial rings or add lights; there is no black gap.
  vec3 pigment = c0 * weights.x + c1 * weights.y + c2 * weights.z;
  float coverage = 0.66 + 0.16 * (0.5 + 0.5 * sin(uv.y * 2.8 + phase2));
  vec3 color = mix(base, pigment, coverage);
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
