#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  float p;
  float lag;
  float winW;
  float winH;
  float tx;
  float ty;
  float cx0;
  float y0;
  float narrow;
  float ox;
  float oy;
};
layout(binding = 1) uniform sampler2D source;
void main() { fragColor = texture(source, qt_TexCoord0) * qt_Opacity; }
