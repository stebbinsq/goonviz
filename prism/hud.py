"""On-screen overlay (pygame text -> GL texture). Off by default so it never
ends up on the projector by accident; toggle with H or a mapped MIDI button."""

import numpy as np
import moderngl
import pygame

VERT = """
in vec2 in_pos;
out vec2 vUV;
uniform vec4 uRect;  // x, y, w, h in clip space
void main() {
    vUV = vec2(in_pos.x, 1.0 - in_pos.y);
    gl_Position = vec4(uRect.xy + in_pos * uRect.zw, 0.0, 1.0);
}
"""
FRAG = """
in vec2 vUV;
out vec4 fragColor;
uniform sampler2D uTex;
void main() { fragColor = texture(uTex, vUV); }
"""


class Hud:
    def __init__(self, ctx, header):
        self.ctx = ctx
        pygame.font.init()
        self.font = pygame.font.SysFont("dejavusansmono,menlo,monospace", 18)
        self.prog = ctx.program(vertex_shader=header + VERT, fragment_shader=header + FRAG)
        quad = ctx.buffer(np.array([0, 0, 1, 0, 0, 1, 1, 1], dtype="f4"))
        self.vao = ctx.vertex_array(self.prog, [(quad, "2f", "in_pos")])
        self.tex = None
        self.lines = None

    def _upload(self, lines):
        line_h = self.font.get_linesize()
        width = max(self.font.size(text)[0] for text, _ in lines) + 24
        surf = pygame.Surface((width, line_h * len(lines) + 16), pygame.SRCALPHA)
        surf.fill((0, 0, 0, 170))
        for i, (text, color) in enumerate(lines):
            surf.blit(self.font.render(text, True, color), (12, 8 + i * line_h))
        data = pygame.image.tobytes(surf, "RGBA")
        if self.tex is None or self.tex.size != surf.get_size():
            if self.tex:
                self.tex.release()
            self.tex = self.ctx.texture(surf.get_size(), 4)
        self.tex.write(data)

    def draw(self, lines, screen_size):
        if lines != self.lines:
            self._upload(lines)
            self.lines = lines
        sw, sh = screen_size
        w, h = self.tex.size
        cw, ch = 2.0 * w / sw, 2.0 * h / sh
        self.prog["uRect"].value = (-1.0 + 0.02, 1.0 - 0.02 - ch, cw, ch)
        self.tex.use(0)
        self.ctx.enable(moderngl.BLEND)
        self.ctx.blend_func = moderngl.SRC_ALPHA, moderngl.ONE_MINUS_SRC_ALPHA
        self.vao.render(moderngl.TRIANGLE_STRIP)
        self.ctx.disable(moderngl.BLEND)
