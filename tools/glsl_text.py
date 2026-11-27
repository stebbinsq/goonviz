#!/usr/bin/env python3
"""Bake text into a preset as a tiny 5x7 pixel font (GLSL has no strings or fonts).

A preset lists its strings in a header line:

    // @text {"SIGNS": ["AFTERS 3 KM", "SOBRIETY <- CLOSED"], "HUD": ["HYDRATION"]}

and this tool writes the glyphs it needs plus lookup and drawing helpers between the markers
`// <text>` and `// </text>` (inserted right after the @text line the first time):

    python tools/glsl_text.py presets/41_afters_highway.glsl

In the shader, each group becomes a constant (T_SIGNS, T_HUD) and you get:

    float drawText(int grp, int s, vec2 q, float fw)   // string s of a group; q in font pixels from its
                                                        // bottom-left corner, fw = font pixels per screen
                                                        // pixel (for antialiasing; far text fades to grey)
    float drawNum(float v, int digits, vec2 q, float fw) // a whole number, zero-padded to `digits`
    int textLen(int grp, int s)                         // characters (each is 6 font pixels wide, 7 high)

Characters: A-Z a-z 0-9 and  . , ! ? : - ' / % + ( ) < > _ # = & * " ← → ↑ ♥  (and space).
"""
import json
import re
import sys

G = {}


def glyph(ch, *rows):
    assert len(rows) == 7 and all(len(r) == 5 for r in rows), ch
    G[ch] = rows


# digits come first in every generated font, so drawNum can index them directly
glyph("0", ".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###.")
glyph("1", "..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###.")
glyph("2", ".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####")
glyph("3", "#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###.")
glyph("4", "...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#.")
glyph("5", "#####", "#....", "####.", "....#", "....#", "#...#", ".###.")
glyph("6", "..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###.")
glyph("7", "#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#...")
glyph("8", ".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###.")
glyph("9", ".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##..")
glyph(" ", ".....", ".....", ".....", ".....", ".....", ".....", ".....")
glyph("A", ".###.", "#...#", "#...#", "#...#", "#####", "#...#", "#...#")
glyph("B", "####.", "#...#", "#...#", "####.", "#...#", "#...#", "####.")
glyph("C", ".###.", "#...#", "#....", "#....", "#....", "#...#", ".###.")
glyph("D", "###..", "#..#.", "#...#", "#...#", "#...#", "#..#.", "###..")
glyph("E", "#####", "#....", "#....", "####.", "#....", "#....", "#####")
glyph("F", "#####", "#....", "#....", "####.", "#....", "#....", "#....")
glyph("G", ".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####")
glyph("H", "#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#")
glyph("I", ".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###.")
glyph("J", "..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##..")
glyph("K", "#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#")
glyph("L", "#....", "#....", "#....", "#....", "#....", "#....", "#####")
glyph("M", "#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#")
glyph("N", "#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#")
glyph("O", ".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.")
glyph("P", "####.", "#...#", "#...#", "####.", "#....", "#....", "#....")
glyph("Q", ".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#")
glyph("R", "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#")
glyph("S", ".####", "#....", "#....", ".###.", "....#", "....#", "####.")
glyph("T", "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..")
glyph("U", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###.")
glyph("V", "#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#..")
glyph("W", "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#.")
glyph("X", "#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#")
glyph("Y", "#...#", "#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..")
glyph("Z", "#####", "....#", "...#.", "..#..", ".#...", "#....", "#####")
glyph("a", ".....", ".....", ".###.", "....#", ".####", "#...#", ".####")
glyph("b", "#....", "#....", "#.##.", "##..#", "#...#", "#...#", "####.")
glyph("c", ".....", ".....", ".###.", "#....", "#....", "#...#", ".###.")
glyph("d", "....#", "....#", ".##.#", "#..##", "#...#", "#...#", ".####")
glyph("e", ".....", ".....", ".###.", "#...#", "#####", "#....", ".###.")
glyph("f", "..##.", ".#..#", ".#...", "###..", ".#...", ".#...", ".#...")
glyph("g", ".....", ".####", "#...#", "#...#", ".####", "....#", ".###.")
glyph("h", "#....", "#....", "#.##.", "##..#", "#...#", "#...#", "#...#")
glyph("i", "..#..", ".....", ".##..", "..#..", "..#..", "..#..", ".###.")
glyph("j", "...#.", ".....", "..##.", "...#.", "...#.", "#..#.", ".##..")
glyph("k", "#....", "#....", "#..#.", "#.#..", "##...", "#.#..", "#..#.")
glyph("l", ".##..", "..#..", "..#..", "..#..", "..#..", "..#..", ".###.")
glyph("m", ".....", ".....", "##.#.", "#.#.#", "#.#.#", "#...#", "#...#")
glyph("n", ".....", ".....", "#.##.", "##..#", "#...#", "#...#", "#...#")
glyph("o", ".....", ".....", ".###.", "#...#", "#...#", "#...#", ".###.")
glyph("p", ".....", ".....", "####.", "#...#", "####.", "#....", "#....")
glyph("q", ".....", ".....", ".##.#", "#..##", ".####", "....#", "....#")
glyph("r", ".....", ".....", "#.##.", "##..#", "#....", "#....", "#....")
glyph("s", ".....", ".....", ".###.", "#....", ".###.", "....#", "####.")
glyph("t", ".#...", ".#...", "###..", ".#...", ".#...", ".#..#", "..##.")
glyph("u", ".....", ".....", "#...#", "#...#", "#...#", "#..##", ".##.#")
glyph("v", ".....", ".....", "#...#", "#...#", "#...#", ".#.#.", "..#..")
glyph("w", ".....", ".....", "#...#", "#...#", "#.#.#", "#.#.#", ".#.#.")
glyph("x", ".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#")
glyph("y", ".....", ".....", "#...#", "#...#", ".####", "....#", ".###.")
glyph("z", ".....", ".....", "#####", "...#.", "..#..", ".#...", "#####")
glyph(".", ".....", ".....", ".....", ".....", ".....", ".##..", ".##..")
glyph(",", ".....", ".....", ".....", ".....", ".##..", "..#..", ".#...")
glyph("!", "..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#..")
glyph("?", ".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#..")
glyph(":", ".....", ".##..", ".##..", ".....", ".##..", ".##..", ".....")
glyph("-", ".....", ".....", ".....", "#####", ".....", ".....", ".....")
glyph("'", ".##..", "..#..", ".#...", ".....", ".....", ".....", ".....")
glyph("/", ".....", "....#", "...#.", "..#..", ".#...", "#....", ".....")
glyph("%", "##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##")
glyph("+", ".....", "..#..", "..#..", "#####", "..#..", "..#..", ".....")
glyph("(", "...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#.")
glyph(")", ".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#...")
glyph("<", "...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#.")
glyph(">", ".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#...")
glyph("_", ".....", ".....", ".....", ".....", ".....", ".....", "#####")
glyph("#", ".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#.")
glyph("=", ".....", ".....", "#####", ".....", "#####", ".....", ".....")
glyph("&", ".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#")
glyph("*", ".....", "..#..", "#.#.#", ".###.", "#.#.#", "..#..", ".....")
glyph('"', ".#.#.", ".#.#.", ".#.#.", ".....", ".....", ".....", ".....")
glyph("←", ".....", "..#..", ".#...", "#####", ".#...", "..#..", ".....")
glyph("→", ".....", "..#..", "...#.", "#####", "...#.", "..#..", ".....")
glyph("↑", "..#..", ".###.", "#.#.#", "..#..", "..#..", "..#..", "..#..")
glyph("♥", ".....", ".#.#.", "#####", "#####", ".###.", "..#..", ".....")


def pack(rows):
    lo = hi = 0
    for r, row in enumerate(rows):
        bits = int(row.replace("#", "1").replace(".", "0"), 2)
        if r < 4:
            lo |= bits << (r * 5)
        else:
            hi |= bits << ((r - 4) * 5)
    return lo, hi


def generate(groups):
    order = [str(d) for d in range(10)]
    for strings in groups.values():
        for s in strings:
            for ch in s:
                if ch not in G:
                    raise SystemExit(f"no glyph for {ch!r} in {s!r}")
                if ch not in order:
                    order.append(ch)
    idx = {ch: i for i, ch in enumerate(order)}
    out = ["// <text>  generated by tools/glsl_text.py from the @text line above: edit that line and rerun the tool"]
    font = ", ".join("ivec2(%d, %d)" % pack(G[ch]) for ch in order)
    out.append(f"const ivec2 FONT[{len(order)}] = ivec2[{len(order)}]({font});  // {''.join(order)}")
    names = list(groups)
    for gi, name in enumerate(names):
        strings = groups[name]
        chars, offs = [], [0]
        for s in strings:
            chars += [idx[c] for c in s]
            offs.append(len(chars))
        out.append(f"const int T_{name} = {gi};")
        out.append(f"const int {name}_OFF[{len(offs)}] = int[{len(offs)}]({', '.join(map(str, offs))});")
        out.append(f"const int {name}_CH[{max(1, len(chars))}] = int[{max(1, len(chars))}]({', '.join(map(str, chars or [10]))});")
        for i, s in enumerate(strings):
            out.append(f"//   {name} {i}: {s}")
    out.append("int textLen(int grp, int s) {")
    for gi, name in enumerate(names):
        out.append(f"    if (grp == {gi}) return {name}_OFF[s + 1] - {name}_OFF[s];")
    out.append("    return 0;\n}")
    out.append("int textChar(int grp, int s, int i) {")
    for gi, name in enumerate(names):
        out.append(f"    if (grp == {gi}) return {name}_CH[{name}_OFF[s] + i];")
    out.append("    return 10;\n}")
    out.append("""float glyphBit(int g, ivec2 c) {
    if (c.x < 0 || c.x > 4 || c.y < 0 || c.y > 6) return 0.0;
    int row = 6 - c.y;
    ivec2 f = FONT[g];
    int bits = row < 4 ? (f.x >> (row * 5)) : (f.y >> ((row - 4) * 5));
    return float((bits >> (4 - c.x)) & 1);
}
// 4-tap rotated-grid coverage of the glyph pixels; text smaller than about a screen pixel per font pixel
// fades to its average grey instead of shimmering
float drawText(int grp, int s, vec2 q, float fw) {
    int n = textLen(grp, s);
    if (q.x < -1.0 || q.y < -1.0 || q.y > 8.0 || q.x > float(n) * 6.0) return 0.0;
    float cov = 0.0;
    for (int k = 0; k < 4; k++) {
        vec2 o = (k == 0 ? vec2(0.125, 0.375) : k == 1 ? vec2(0.375, -0.125) : k == 2 ? vec2(-0.125, -0.375) : vec2(-0.375, 0.125)) * min(fw, 1.5);
        vec2 qq = q + o;
        int i = int(floor(qq.x / 6.0));
        if (i < 0 || i >= n) continue;
        cov += glyphBit(textChar(grp, s, i), ivec2(floor(qq.x - float(i) * 6.0), floor(qq.y)));
    }
    float box = step(0.0, q.x) * step(q.x, float(n) * 6.0 - 1.0) * step(0.0, q.y) * step(q.y, 7.0);
    return mix(cov * 0.25, box * 0.3, smoothstep(1.0, 2.5, fw));
}
float drawNum(float v, int digits, vec2 q, float fw) {
    if (q.x < -1.0 || q.y < -1.0 || q.y > 8.0 || q.x > float(digits) * 6.0) return 0.0;
    float cov = 0.0;
    for (int k = 0; k < 4; k++) {
        vec2 o = (k == 0 ? vec2(0.125, 0.375) : k == 1 ? vec2(0.375, -0.125) : k == 2 ? vec2(-0.125, -0.375) : vec2(-0.375, 0.125)) * min(fw, 1.5);
        vec2 qq = q + o;
        int i = int(floor(qq.x / 6.0));
        if (i < 0 || i >= digits) continue;
        int d = int(mod(floor(max(v, 0.0) / pow(10.0, float(digits - 1 - i))), 10.0));
        cov += glyphBit(d, ivec2(floor(qq.x - float(i) * 6.0), floor(qq.y)));
    }
    float box = step(0.0, q.x) * step(q.x, float(digits) * 6.0 - 1.0) * step(0.0, q.y) * step(q.y, 7.0);
    return mix(cov * 0.25, box * 0.3, smoothstep(1.0, 2.5, fw));
}
// </text>""")
    return "\n".join(out)


def main(path):
    src = open(path, encoding="utf-8").read()
    m = re.search(r"^// @text (\{.*\})\s*$", src, re.M)
    if not m:
        raise SystemExit(f"{path}: no '// @text {{...}}' line")
    groups = json.loads(m.group(1))
    block = generate(groups)
    if "// <text>" in src:
        src = re.sub(r"// <text>.*?// </text>", lambda _: block, src, flags=re.S)
    else:
        src = src[:m.end()] + "\n" + block + src[m.end():]
    open(path, "w", encoding="utf-8").write(src)
    print(f"{path}: {sum(len(v) for v in groups.values())} strings in {len(groups)} groups")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
