#!/usr/bin/env python3
"""Regenerate every app icon, tray icon and default avatar from one vector source.

The artwork lives in this file as SVG templates, so every platform gets the
same glyph drawn at the geometry that platform expects:

  iOS       full-bleed opaque square (the OS applies the squircle mask;
            App Store Connect rejects an alpha channel)
  macOS     Big Sur grid: 824/1024 rounded body + drop shadow, transparent
  Android   adaptive icon (foreground / background / monochrome layers,
            108dp canvas, glyph inside the 66dp safe circle), legacy square
            and round icons for API 23-25, white status-bar icon
  Windows   multi-resolution .ico (16..256), tray art
  Linux     hicolor theme sizes + scalable SVG, tray art

Small renders (<= 24 px) use a simplified glyph: no keyhole, thicker shackle,
less padding. Detail that is thinner than a pixel only turns into mud.

Requires `rsvg-convert` and ImageMagick `magick` (Homebrew: librsvg,
imagemagick). Run from the repo root on the Mac:

    python3 tool/branding/generate_brand_assets.py
"""

from __future__ import annotations

import os
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# Brand palette.
NAVY_TOP = '#1F4A7C'
NAVY_BOTTOM = '#112844'
TEAL_TOP = '#3FE6D2'
TEAL_BOTTOM = '#17B19F'

# ---------------------------------------------------------------------------
# Glyph: a speech bubble with a padlock knocked out of it. Drawn in a
# 1024-unit box whose optical centre is (512, 512).
# ---------------------------------------------------------------------------


def _glyph_shapes(small: bool) -> tuple[str, str]:
    """Returns (bubble, lock) SVG fragments, both filled white.

    The bubble is the solid shape; the lock is what gets cut out of it.
    """
    bubble = (
        '<rect x="232" y="236" width="560" height="460" rx="150"/>'
        '<path d="M442 684 L498 772 Q512 794 526 772 L582 684 Z"/>'
    )
    if small:
        shackle_w = 60
        lock = (
            f'<path d="M448 450 V404 A64 64 0 0 1 576 404 V450" fill="none" '
            f'stroke="#fff" stroke-width="{shackle_w}"/>'
            '<rect x="392" y="436" width="240" height="176" rx="36"/>'
        )
    else:
        lock = (
            '<path d="M450 452 V402 A62 62 0 0 1 574 402 V452" fill="none" '
            'stroke="#fff" stroke-width="44"/>'
            '<rect x="400" y="440" width="224" height="166" rx="36"/>'
        )
    return bubble, lock


def _keyhole() -> str:
    return (
        '<circle cx="512" cy="508" r="24"/>'
        '<rect x="500" y="508" width="24" height="54" rx="12"/>'
    )


def glyph_mask(mask_id: str, small: bool) -> str:
    """A <mask> that is white where the glyph is solid."""
    bubble, lock = _glyph_shapes(small)
    keyhole = '' if small else f'<g fill="#fff">{_keyhole()}</g>'
    return (
        f'<mask id="{mask_id}" maskUnits="userSpaceOnUse" x="0" y="0" '
        f'width="1024" height="1024">'
        f'<g fill="#fff">{bubble}</g>'
        f'<g fill="#000" stroke="#000">{lock.replace("#fff", "#000")}</g>'
        f'{keyhole}</mask>'
    )


def glyph(fill: str, scale: float, small: bool, mask_id: str = 'g') -> str:
    """The glyph filled with [fill], scaled about the canvas centre."""
    t = f'translate(512 512) scale({scale}) translate(-512 -512)'
    return (
        f'<defs>{glyph_mask(mask_id, small)}</defs>'
        f'<g transform="{t}"><rect width="1024" height="1024" fill="{fill}" '
        f'mask="url(#{mask_id})"/></g>'
    )


GRADIENTS = (
    f'<defs>'
    f'<linearGradient id="navy" x1="0" y1="0" x2="1" y2="1">'
    f'<stop offset="0" stop-color="{NAVY_TOP}"/>'
    f'<stop offset="1" stop-color="{NAVY_BOTTOM}"/></linearGradient>'
    f'<linearGradient id="teal" x1="0" y1="0" x2="0" y2="1">'
    f'<stop offset="0" stop-color="{TEAL_TOP}"/>'
    f'<stop offset="1" stop-color="{TEAL_BOTTOM}"/></linearGradient>'
    f'</defs>'
)


def svg(body: str) -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
        f'viewBox="0 0 1024 1024">{GRADIENTS}{body}</svg>'
    )


def icon_full_bleed(small: bool) -> str:
    """iOS / Android legacy source: opaque square, the OS masks it."""
    return svg('<rect width="1024" height="1024" fill="url(#navy)"/>'
               + glyph('url(#teal)', 1.0 if not small else 1.12, small))


def icon_rounded(small: bool) -> str:
    """Windows / Linux / in-app: a rounded square with transparent corners.

    Small sizes drop the margin so a 16 px tray/taskbar icon uses all 16 px.
    """
    if small:
        plate = '<rect width="1024" height="1024" rx="200" fill="url(#navy)"/>'
        return svg(plate + glyph('url(#teal)', 1.3, small))
    plate = ('<rect x="48" y="48" width="928" height="928" rx="208" '
             'fill="url(#navy)"/>')
    return svg(plate + glyph('url(#teal)', 0.92, small))


def icon_round(small: bool) -> str:
    """Android legacy round icon (API 25 launchers)."""
    plate = '<circle cx="512" cy="512" r="488" fill="url(#navy)"/>'
    return svg(plate + glyph('url(#teal)', 0.9 if not small else 1.0, small))


def icon_macos(small: bool) -> str:
    """macOS Big Sur+ grid: 824x824 body at (100,100), r=185, soft shadow."""
    shadow = (
        '<defs><filter id="sh" x="-20%" y="-20%" width="140%" height="140%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="14"/>'
        '<feOffset dy="12"/>'
        '<feComponentTransfer><feFuncA type="linear" slope="0.35"/>'
        '</feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>'
        '</filter></defs>'
    )
    plate = ('<rect x="100" y="100" width="824" height="824" rx="185" '
             'fill="url(#navy)" filter="url(#sh)"/>')
    return svg(shadow + plate + glyph('url(#teal)', 0.805, small))


def adaptive_foreground() -> str:
    # 108dp canvas; the 66dp safe circle is 61% of it. Glyph scale 0.78 keeps
    # the bubble corners and the tail inside that circle for any mask shape.
    return svg(glyph('url(#teal)', 0.78, False))


def adaptive_background() -> str:
    return svg('<rect width="1024" height="1024" fill="url(#navy)"/>')


def adaptive_monochrome() -> str:
    # Android 13 themed icons: only alpha is used; the launcher tints it.
    return svg(glyph('#fff', 0.78, False))


def status_bar_white() -> str:
    # 24dp icon with a 22dp live area; white on transparent, alpha only.
    return svg(glyph('#fff', 1.62, True))


def tray_template() -> str:
    # macOS menu-bar template: black + alpha, AppKit tints it for the
    # current appearance. Fills the square; the plugin draws it at 18pt.
    return svg(glyph('#000', 1.66, True))


# ---------------------------------------------------------------------------
# Default avatars: flat, full-bleed square art (the UIKit clips to a circle
# or rounded square). 512 px keeps the self avatar far below Tox's 64 KiB
# avatar transfer limit.
# ---------------------------------------------------------------------------

CREAM = '#F8F0DC'


def _person(cx: float, head_cy: float, head_r: float, shoulder_w: float,
            shoulder_top: float, body: str, outline: str | None = None) -> str:
    half = shoulder_w / 2
    left, right = cx - half, cx + half
    curve = shoulder_w * 0.23
    path = (
        f'M{left} 540 V{shoulder_top + curve * 1.3} '
        f'C{left} {shoulder_top + curve * 0.25} {cx - half * 0.55} {shoulder_top} '
        f'{cx} {shoulder_top} '
        f'C{cx + half * 0.55} {shoulder_top} {right} {shoulder_top + curve * 0.25} '
        f'{right} {shoulder_top + curve * 1.3} V540 Z'
    )
    stroke = ''
    if outline:
        stroke = f' stroke="{outline}" stroke-width="16" paint-order="stroke"'
    return (
        f'<path d="{path}" fill="{body}"{stroke}/>'
        f'<circle cx="{cx}" cy="{head_cy}" r="{head_r}" fill="{CREAM}"{stroke}/>'
    )


def avatar_person(bg: str, halo: str, body: str) -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" '
        'viewBox="0 0 512 512">'
        f'<rect width="512" height="512" fill="{bg}"/>'
        f'<circle cx="256" cy="256" r="212" fill="{halo}"/>'
        + _person(256, 196, 78, 290, 302, body) +
        '</svg>'
    )


def avatar_group(bg: str, halo: str, body_front: str, body_back: str) -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" '
        'viewBox="0 0 512 512">'
        f'<rect width="512" height="512" fill="{bg}"/>'
        f'<circle cx="256" cy="256" r="212" fill="{halo}"/>'
        + _person(150, 214, 54, 196, 298, body_back)
        + _person(362, 214, 54, 196, 298, body_back)
        + _person(256, 234, 68, 250, 330, body_front, outline=halo) +
        '</svg>'
    )


# ---------------------------------------------------------------------------
# Rendering helpers.
# ---------------------------------------------------------------------------

TMP = tempfile.mkdtemp(prefix='toxee-brand-')


def _need(tool: str) -> None:
    if shutil.which(tool) is None:
        sys.exit(f'error: `{tool}` not found on PATH (brew install '
                 f'{"librsvg" if tool == "rsvg-convert" else "imagemagick"})')


def render(svg_text: str, size: int, out: str, opaque: bool = False) -> None:
    src = os.path.join(TMP, f'{abs(hash(svg_text))}.svg')
    with open(src, 'w', encoding='utf-8') as f:
        f.write(svg_text)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(['rsvg-convert', '-w', str(size), '-h', str(size), src,
                    '-o', out], check=True)
    # Strip metadata (timestamps) so re-running the generator is a no-op in
    # git; drop the alpha channel where the platform forbids it. Pin the
    # pixel format: left alone, ImageMagick writes small renders as palette
    # PNGs, and PNG entries inside a Windows .ico must be 32-bit RGBA.
    cmd = ['magick', out, '-strip']
    if opaque:
        cmd += ['-background', NAVY_BOTTOM, '-alpha', 'remove', '-alpha', 'off']
    cmd += ['-define', 'png:exclude-chunks=date,time',
            ('PNG24:' if opaque else 'PNG32:') + out]
    subprocess.run(cmd, check=True)


def write_ico(entries: list[str], out: str) -> None:
    """Pack PNG files into a .ico (PNG-compressed entries, Vista+)."""
    blobs = []
    for path in entries:
        with open(path, 'rb') as f:
            data = f.read()
        w, h = struct.unpack('>II', data[16:24])
        blobs.append((w, h, data))
    header = struct.pack('<HHH', 0, 1, len(blobs))
    offset = 6 + 16 * len(blobs)
    directory = b''
    payload = b''
    for w, h, data in blobs:
        directory += struct.pack('<BBBBHHII', w % 256, h % 256, 0, 0, 1, 32,
                                 len(data), offset + len(payload))
        payload += data
    with open(out, 'wb') as f:
        f.write(header + directory + payload)


def p(*parts: str) -> str:
    return os.path.join(ROOT, *parts)


def main() -> None:
    _need('rsvg-convert')
    _need('magick')

    # --- Flutter assets ----------------------------------------------------
    render(icon_rounded(False), 1024, p('assets', 'app_icon.png'))
    render(icon_rounded(False), 256, p('doc', 'product', 'assets', 'app_icon.png'))
    render(icon_rounded(True), 128, p('assets', 'tray', 'tray_color.png'))
    render(tray_template(), 64, p('assets', 'tray', 'tray_template.png'))

    render(avatar_person('#FF7152', '#FF8567', '#10596A'), 512,
           p('assets', 'avatars', 'default_user.png'), opaque=True)
    render(avatar_person('#86A6C6', '#96B2CF', '#243248'), 512,
           p('assets', 'avatars', 'default_contact.png'), opaque=True)
    render(avatar_group('#27A898', '#35B6A6', '#173A5E', '#3A7E98'), 512,
           p('assets', 'avatars', 'default_group.png'), opaque=True)

    # --- iOS ----------------------------------------------------------------
    ios = p('ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    ios_sizes = {
        '20x20@1x': 20, '20x20@2x': 40, '20x20@3x': 60,
        '29x29@1x': 29, '29x29@2x': 58, '29x29@3x': 87,
        '40x40@1x': 40, '40x40@2x': 80, '40x40@3x': 120,
        '50x50@1x': 50, '50x50@2x': 100,
        '57x57@1x': 57, '57x57@2x': 114,
        '60x60@2x': 120, '60x60@3x': 180,
        '72x72@1x': 72, '72x72@2x': 144,
        '76x76@1x': 76, '76x76@2x': 152,
        '83.5x83.5@2x': 167,
        '1024x1024@1x': 1024,
    }
    for name, px in ios_sizes.items():
        render(icon_full_bleed(px <= 40), px,
               os.path.join(ios, f'Icon-App-{name}.png'), opaque=True)

    # --- macOS --------------------------------------------------------------
    mac = p('macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    for px in (16, 32, 64, 128, 256, 512, 1024):
        render(icon_macos(px <= 32), px, os.path.join(mac, f'app_icon_{px}.png'))

    # --- Android ------------------------------------------------------------
    res = p('android', 'app', 'src', 'main', 'res')
    densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0,
                 'xxxhdpi': 4.0}
    for d, k in densities.items():
        mip = os.path.join(res, f'mipmap-{d}')
        legacy = round(48 * k)
        render(icon_rounded(False), legacy, os.path.join(mip, 'ic_launcher.png'))
        render(icon_round(False), legacy,
               os.path.join(mip, 'ic_launcher_round.png'))
        layer = round(108 * k)
        render(adaptive_foreground(), layer,
               os.path.join(mip, 'ic_launcher_foreground.png'))
        render(adaptive_background(), layer,
               os.path.join(mip, 'ic_launcher_background.png'))
        render(adaptive_monochrome(), layer,
               os.path.join(mip, 'ic_launcher_monochrome.png'))
        render(status_bar_white(), round(24 * k),
               os.path.join(res, f'drawable-{d}', 'ic_stat_toxee.png'))

    # --- Windows ------------------------------------------------------------
    ico_parts = []
    for px in (16, 20, 24, 32, 40, 48, 64, 256):
        out = os.path.join(TMP, f'ico_{px}.png')
        render(icon_rounded(px <= 24), px, out)
        ico_parts.append(out)
    write_ico(ico_parts, p('windows', 'runner', 'resources', 'app_icon.ico'))

    # --- Linux (hicolor theme) ----------------------------------------------
    hicolor = p('linux', 'icons', 'hicolor')
    for px in (16, 24, 32, 48, 64, 128, 256, 512):
        render(icon_rounded(px <= 24), px,
               os.path.join(hicolor, f'{px}x{px}', 'apps', 'toxee.png'))
    scalable = os.path.join(hicolor, 'scalable', 'apps', 'toxee.svg')
    os.makedirs(os.path.dirname(scalable), exist_ok=True)
    with open(scalable, 'w', encoding='utf-8') as f:
        f.write(icon_rounded(False) + '\n')

    shutil.rmtree(TMP, ignore_errors=True)
    print('brand assets regenerated')


if __name__ == '__main__':
    main()
