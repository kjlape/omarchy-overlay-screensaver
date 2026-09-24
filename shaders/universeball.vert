#version 440

// Minimal passthrough vertex stage (see starnest.vert for why every
// ShaderEffect fragment shader ships its own: Qt's implicit default vertex
// stage has no explicit-location output, which the NVIDIA linker refuses to
// match against the fragment input). All shaders in shaders/ share this
// shape; the only difference is the comment header.

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
