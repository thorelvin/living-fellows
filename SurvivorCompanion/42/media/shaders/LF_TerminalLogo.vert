// SPDX-License-Identifier: MIT
#version 330
layout (location = 0) in vec2 vPos;
layout (location = 1) in vec2 vUV;
layout (location = 2) in vec4 vCol;
uniform mat4 ModelViewProjection;
out vec4 col;
out vec2 texCoord;
void main() {
    gl_Position = ModelViewProjection * vec4(vPos.xy, 0.0, 1.0);
    texCoord = vUV;
    col = vCol;
}
