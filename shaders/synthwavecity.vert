#version 440

// Minimal passthrough vertex stage for the synthwavecity fragment shader.
// Same shape as shaders/starnest.vert (the canonical per-port copy): Qt's
// implicit default vertex stage doesn't declare an explicit-location output,
// which NVIDIA's linker refuses to match against the fragment input.

layout(location = 0) in vec4 position;
layout(location = 1) in vec2 texCoord;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
};

void main()
{
    qt_TexCoord0 = texCoord;
    gl_Position = qt_Matrix * position;
}
