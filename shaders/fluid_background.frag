#include <flutter/runtime_effect.glsl>

// Packed with FluidFrameUniforms; frame-only work is evaluated once in Dart.
uniform vec2 uSize;
uniform float uMotion;
uniform float uDim;
uniform vec2 uPhases;
uniform vec2 uCentre0;
uniform vec2 uCentre1;
uniform vec2 uCentre2;
uniform vec2 uCentre3;
uniform vec3 uPigment0;
uniform vec3 uPigment1;
uniform vec3 uPigment2;
uniform vec3 uPigment3;
uniform vec3 uBase;
uniform vec4 uShape0;
uniform vec4 uShape1;
uniform vec4 uShape2;
uniform vec4 uShape3;
// Appended colour controls retain the original 45 uniform offsets.
uniform vec4 uWeightDelta;
uniform vec4 uMixProtection;
uniform vec4 uPigmentChroma;
uniform vec2 uChildCentre0;
uniform vec4 uChildShape0;
uniform vec3 uChildColor0;
uniform float uChildStrength0;
uniform vec2 uChildCentre1;
uniform vec4 uChildShape1;
uniform vec3 uChildColor1;
uniform float uChildStrength1;
out vec4 fragColor;

float chroma(vec3 color) {
  return max(color.r, max(color.g, color.b)) - min(color.r, min(color.g, color.b));
}

// Display-luma in encoded RGB, not physical linear-light luminance. Keep its
// original spatial field while restoring colour; HSL midpoint preservation
// can instead brighten/darken the join as the largest RGB channel changes.
float displayLuma(vec3 color) {
  return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float pigmentWeight(vec2 point, vec2 centre, vec4 shape) {
  vec2 scale = uSize / max(min(uSize.x, uSize.y), 1.0);
  vec2 local = (point - centre) * scale;
  vec2 delta = vec2(dot(shape.xy, local), dot(shape.zw, local));
  // Bounded asymmetric curvature without extra pixel sine, noise or texture.
  float bend = uMotion / (1.0 + dot(delta, delta));
  delta += bend * vec2(0.20 * delta.y * delta.y, 0.16 * delta.x * delta.y);
  // Widen the overlap by 25% without changing centres, deformation or motion.
  float squaredDistance = dot(delta, delta);
  float falloff = 1.0 / (1.0 + 0.64 * squaredDistance);
  // A low-strength, wider skirt connects the four fields. Both kernels share
  // the centre and curvature, with no ring, hard winner or extra texture.
  float diffuse = 1.0 / (1.0 + 0.28 * squaredDistance);
  float core = falloff * falloff * (0.65 + 0.35 * falloff);
  return mix(core, diffuse * diffuse, 0.20);
}
float interleavedGradientNoise(vec2 pixel) {
  return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}
void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));
  vec2 point = uv + uMotion * vec2(
      0.055 * sin(uv.y * 2.3 + uPhases.y),
      0.045 * sin(uv.x * 2.0 - uPhases.x));
  vec4 weights = vec4(pigmentWeight(point, uCentre0, uShape0),
      pigmentWeight(point, uCentre1, uShape1), pigmentWeight(point, uCentre2, uShape2),
      pigmentWeight(point, uCentre3, uShape3));
  weights *= clamp(vec4(1.0) + uWeightDelta, vec4(0.55), vec4(1.65));
  float mass = dot(weights, vec4(1.0));
  vec3 pigment = uPigment0 * weights.x + uPigment1 * weights.y +
      uPigment2 * weights.z + uPigment3 * weights.w;
  float expectedChroma = dot(weights, uPigmentChroma);
  // Optional related darker pigments join the same non-additive mixture. Their
  // strengths fade with the cover transition; no new light layer or hard edge.
  if (uChildStrength0 > 0.0) {
    float w = 0.38 * uChildStrength0 * pigmentWeight(point, uChildCentre0, uChildShape0);
    mass += w;
    pigment += uChildColor0 * w;
    expectedChroma += chroma(uChildColor0) * w;
  }
  if (uChildStrength1 > 0.0) {
    float w = 0.38 * uChildStrength1 * pigmentWeight(point, uChildCentre1, uChildShape1);
    mass += w;
    pigment += uChildColor1 * w;
    expectedChroma += chroma(uChildColor1) * w;
  }
  pigment /= max(mass, 0.00001);
  expectedChroma /= max(mass, 0.00001);
  // Protect partially cancelled colour too, while leaving low-chroma artwork
  // alone. The stable cover axis steers deep cancellation without picking a
  // per-pixel winner, which would form a seam as fields cross.
  float strength = clamp(uMixProtection.a * 5.0, 0.0, 1.0) *
      smoothstep(0.04, 0.18, expectedChroma);
  float cancellation = 1.0 - smoothstep(0.22, 0.78,
      chroma(pigment) / max(expectedChroma, 0.0001));
  float level = displayLuma(pigment);
  vec3 axis = pigment - vec3(level) +
      (uMixProtection.rgb - vec3(displayLuma(uMixProtection.rgb))) *
      (0.20 * strength * cancellation);
  float correctedChroma = chroma(axis);
  float loss = max(expectedChroma - correctedChroma, 0.0) / max(expectedChroma, 0.0001);
  float gain = 1.0 + 0.45 * strength * smoothstep(0.0, 0.50, loss);
  // Fit the complete zero-luma colour direction inside the available channel
  // headroom. Per-channel clipping would change brightness again at the edge.
  float upper = max(axis.r, max(axis.g, axis.b));
  float lower = -min(axis.r, min(axis.g, axis.b));
  gain = min(gain, min((1.0 - level) / max(upper, 0.0001),
      level / max(lower, 0.0001)));
  pigment = vec3(level) + axis * gain;
  // Do not reinforce a rounded outline with a distance-dependent colour veil.
  float coverage = 0.84;
  vec3 color = mix(uBase, pigment, coverage);
  float vignette = 1.0 - smoothstep(0.35, 1.10, distance(uv, vec2(0.5, 0.48)));
  color *= mix(0.98, 1.00, vignette);
  color *= 1.0 - clamp(uDim, 0.0, 0.60) * 0.25;
  float dither = (interleavedGradientNoise(FlutterFragCoord().xy) - 0.5) * (0.70 / 255.0);
  color = clamp(color + vec3(dither), vec3(0.0), vec3(1.0));
  fragColor = vec4(color, 1.0);
}
