#include <flutter/runtime_effect.glsl>

uniform vec2 uOrigin;
uniform vec2 uSize;
uniform float uRasterScale;
uniform float uId;
uniform float uTranslationId;
uniform float uFront;
uniform float uFeather;
uniform float uDirection;
uniform float uStrength;
uniform vec4 uActive;
uniform vec4 uInactive;
uniform sampler2D uAtlas;
uniform sampler2D uCoverage;
out vec4 fragColor;

// Raster colours identify shaped ink, not selection rectangles. Decode each
// neighbouring texel BEFORE interpolation so another glyph's descender can
// never leak into this glyph when it moves by a fraction of a device pixel.
float ownedAlpha(vec2 texel) {
  if (any(lessThan(texel, vec2(0.0))) || any(greaterThanEqual(texel, uSize))) return 0.0;
  // Exact native run coverage: no RGB decoding for colour/complex glyphs.
  if (uId < -1.5) return texture(uCoverage, (texel + 0.5) / uSize).a;
  vec4 ink = texture(uAtlas, (texel + 0.5) / uSize);
  if (ink.a < 0.004) return 0.0;
  vec3 code = clamp(floor((ink.rgb / ink.a * 255.0 - 28.0) / 28.0 + 0.5), 0.0, 7.0);
  float id = code.r + code.g * 8.0 + code.b * 64.0;
  bool selected = uId < 0.0 ? abs(id - uTranslationId) > 0.5 : abs(id - uId) < 0.5;
  // Colour-dependent text rasterisation must not alter edge coverage. The
  // untouched white paragraph supplies alpha; the coloured atlas supplies ID.
  return selected ? texture(uCoverage, (texel + 0.5) / uSize).a : 0.0;
}

void main() {
  vec2 point = FlutterFragCoord().xy;
  vec2 pixel = (point - uOrigin) * uRasterScale - 0.5;
  vec2 base = floor(pixel);
  vec2 fraction = fract(pixel);
  float top = mix(ownedAlpha(base), ownedAlpha(base + vec2(1.0, 0.0)), fraction.x);
  float bottom = mix(ownedAlpha(base + vec2(0.0, 1.0)), ownedAlpha(base + vec2(1.0, 1.0)), fraction.x);
  float alpha = mix(top, bottom, fraction.y);
  float highlight = clamp((uFront - point.x) * uDirection / max(uFeather, 1.0) + 0.5, 0.0, 1.0) * uStrength;
  fragColor = mix(uInactive, uActive, highlight) * alpha;
}
