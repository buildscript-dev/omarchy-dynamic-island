#version 440
// Magic-lamp warp. The window is a grid mesh; each row is pulled toward the
// island (tx, ty), the rows nearest the island first, and narrows late, so the
// window becomes a funnel. Build: qsb --qt6 -o shaders/genie.vert.qsb shaders/genie.vert
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  float p;       // 0 window in place, 1 swallowed
  float lag;     // how much later the far end lets go
  float winW;
  float winH;
  float tx;      // island centre, screen pixels
  float ty;
  float cx0;     // window centre x, screen pixels
  float y0;      // window top, screen pixels
  float narrow;  // final width as a fraction of the window
  float ox;      // item origin, screen pixels
  float oy;
};
float ease(float x) { return x < 0.5 ? 4.0 * x * x * x : 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0; }
void main() {
  qt_TexCoord0 = qt_MultiTexCoord0;
  float t = qt_MultiTexCoord0.y;
  float q = clamp(p * (1.0 + lag) - lag * t, 0.0, 1.0);
  float e = ease(q);
  float k = pow(e, 2.4);
  float yy = mix(y0 + t * winH, ty, e);
  float xc = mix(cx0, tx, e);
  float xx = xc + (qt_Vertex.x - winW * 0.5) * ((1.0 - k) + narrow * k);
  gl_Position = qt_Matrix * vec4(xx - ox, yy - oy, 0.0, 1.0);
}
