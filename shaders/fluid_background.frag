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
uniform vec4 uRelay;
out vec4 fragColor;

float pigmentWeight(vec2 point, vec2 centre, vec4 shape) {
  vec2 scale = uSize / max(min(uSize.x, uSize.y), 1.0);
  vec2 local = (point - centre) * scale;
  vec2 delta = vec2(dot(shape.xy, local), dot(shape.zw, local));
  // Bounded asymmetric curvature without extra pixel sine, noise or texture.
  float bend = uMotion / (1.0 + dot(delta, delta));
  delta += bend * vec2(0.20 * delta.y * delta.y, 0.16 * delta.x * delta.y);
  float falloff = 1.0 / (1.0 + dot(delta, delta));
  // Convex, open fields retain the wide edge while reducing distant pigment
  // contamination of dark centres; no additive whitening or layered enclosure.
  return falloff * falloff * (0.80 + 0.20 * falloff);
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
  float mass = dot(weights, vec4(1.0));
  weights /= max(mass, 0.00001);
  // Colour enters through shared edges; isolated cores keep their own pigment.
  vec3 donor0 = uRelay.x < 0.0 ? uPigment1 : uPigment3;
  vec3 donor1 = uRelay.y < 0.0 ? uPigment2 : uPigment0;
  vec3 donor2 = uRelay.z < 0.0 ? uPigment3 : uPigment1;
  vec3 donor3 = uRelay.w < 0.0 ? uPigment0 : uPigment2;
  vec4 donorWeights = vec4(
      uRelay.x < 0.0 ? weights.y : weights.w,
      uRelay.y < 0.0 ? weights.z : weights.x,
      uRelay.z < 0.0 ? weights.w : weights.y,
      uRelay.w < 0.0 ? weights.x : weights.z);
  vec4 edge = abs(uRelay) * 2.0 * min(weights, donorWeights);
  vec3 pigment = mix(uPigment0, donor0, edge.x) * weights.x +
      mix(uPigment1, donor1, edge.y) * weights.y +
      mix(uPigment2, donor2, edge.z) * weights.z +
      mix(uPigment3, donor3, edge.w) * weights.w;
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
