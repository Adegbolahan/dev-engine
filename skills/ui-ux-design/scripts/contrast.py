#!/usr/bin/env python3
"""WCAG 2.x contrast ratio for one or more color pairs.

Usage:
  contrast.py <fg> <bg> [<fg> <bg> ...]
Colors: #rgb, #rrggbb, or rgb(r, g, b). Alpha is not supported; flatten
translucent colors onto their background first.
"""
import re
import sys


def parse(color):
    c = color.strip().lower()
    m = re.fullmatch(r"rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)", c)
    if m:
        return tuple(int(v) for v in m.groups())
    c = c.lstrip("#")
    if len(c) == 3:
        c = "".join(ch * 2 for ch in c)
    if not re.fullmatch(r"[0-9a-f]{6}", c):
        raise ValueError(f"unsupported color: {color}")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def luminance(rgb):
    def channel(v):
        s = v / 255
        return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(fg, bg):
    hi, lo = sorted((luminance(parse(fg)), luminance(parse(bg))), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def verdict(r):
    mark = lambda ok: "pass" if ok else "FAIL"
    return (f"text AA {mark(r >= 4.5)} | large/UI AA {mark(r >= 3)} | "
            f"text AAA {mark(r >= 7)}")


def main(args):
    if len(args) < 2 or len(args) % 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    for fg, bg in zip(args[::2], args[1::2]):
        r = ratio(fg, bg)
        print(f"{fg} on {bg}: {r:.2f}:1  {verdict(r)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
