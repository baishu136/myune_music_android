#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform float uMotion;
uniform float uDim;
uniform vec2 uPhase;
uniform vec3 uColor0;
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec3 uDark;
uniform vec3 uBase;
uniform float uDarkPresence;
uniform vec4 uEvent0;
uniform vec4 uEvent1;
uniform vec4 uEvent2;
out vec4 fragColor;

float smoothUnit(float x) {
  x = clamp(x, 0.0, 1.0);
  return x*x*x*(x*(x*6.0-15.0)+10.0);
}
float hash(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(.06711056,.00583715)))); }
float eventGain(vec2 p, vec4 event) {
  vec2 delta = p-event.xy;
  return event.w * (1.0 - smoothUnit(dot(delta,delta) / max(event.z*event.z, .0000000001)));
}
vec3 nodeColor(vec2 id, vec2 extent) {
  vec2 p = id * .1;
  vec2 d = p - extent * .5;
  float r = length(d);
  float warp = uMotion * ((.09*(d.x*d.x-d.y*d.y) + .12*d.x*d.y*uPhase.y)
      / (.20+dot(d,d)) + .12*(hash(id)-.5));
  float t = fract((r+warp)/.85-uPhase.x) * 3.0;
  vec3 color;
  if (t < 1.0) color = mix(uColor0,uColor1,smoothUnit(t));
  else if (t < 2.0) color = mix(uColor1,uColor2,smoothUnit(t-1.0));
  else color = mix(uColor2,uColor0,smoothUnit(t-2.0));
  // One irregular dark seed per 4x4 neighbourhood. The separating light nodes
  // prevent a continuous dark ring or a screen-spanning dark band.
  vec2 macro = floor(id/4.0);
  vec2 seed = vec2(1.0) + floor(vec2(hash(macro+11.0),hash(macro+37.0))*2.0);
  vec2 local = id-macro*4.0;
  float selected = (1.0-step(.5,abs(local.x-seed.x))) * (1.0-step(.5,abs(local.y-seed.y)));
  float darkPhase = fract(r*1.1-uPhase.x*.7+hash(macro+71.0));
  float darkPulse = smoothUnit(1.0-abs(darkPhase*2.0-1.0));
  color = mix(color,uDark,selected*darkPulse*.78*uDarkPresence);
  float gain = 1.0+eventGain(p,uEvent0)+eventGain(p,uEvent1)+eventGain(p,uEvent2);
  color *= clamp(gain,.70,1.30);
  color /= max(1.0,max(color.r,max(color.g,color.b)));
  return color;
}
void main() {
  float shortSide = max(1.0,min(uSize.x,uSize.y));
  vec2 extent = uSize/shortSide;
  vec2 uv = FlutterFragCoord().xy/max(uSize,vec2(1.0));
  vec2 grid = FlutterFragCoord().xy/shortSide*10.0;
  vec2 id = floor(grid), f = fract(grid);
  f = f*f*(3.0-2.0*f);
  vec3 pigment = mix(mix(nodeColor(id,extent),nodeColor(id+vec2(1,0),extent),f.x),
      mix(nodeColor(id+vec2(0,1),extent),nodeColor(id+vec2(1,1),extent),f.x),f.y);
  vec3 color = mix(uBase,pigment,.84);
  float vignette = 1.0-smoothstep(.35,1.10,distance(uv,vec2(.5,.48)));
  color *= mix(.98,1.0,vignette);
  color *= 1.0-clamp(uDim,0.0,.60)*.25;
  color += vec3((hash(FlutterFragCoord().xy)-.5)*(.70/255.0));
  fragColor = vec4(clamp(color,vec3(0),vec3(1)),1.0);
}
