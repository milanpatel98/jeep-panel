#!/usr/bin/env python3
"""Renders the Forx map-button glyphs (the SVGs beside this script, a 28 pt box each) into
Forx/Assets.xcassets as template images at 2x and 3x, and a contact sheet to look at.

    python3 ios/tools/glyphs/render.py [sheet.png]
"""
import io, json, os, sys
import cairosvg
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, '..', '..', 'Forx', 'Assets.xcassets')
GLYPHS = ['jeep-views', 'lock', 'lock-open', 'globe', 'apps']
BOX = 28  # pt

def render(name, scale):
    """The glyph's alpha: the `body` group less the `cut` group (cairosvg draws no SVG masks)."""
    svg = open(os.path.join(HERE, f'{name}.svg')).read()
    def layer(hide):
        s = svg.replace('<g id="%s"' % hide, '<g id="%s" display="none"' % hide)
        data = cairosvg.svg2png(bytestring=s.encode(), output_width=BOX * scale, output_height=BOX * scale)
        return Image.open(io.BytesIO(data)).convert('RGBA').getchannel('A')
    body, cut = layer('cut'), layer('body')
    alpha = Image.eval(cut, lambda v: 255 - v)
    from PIL import ImageChops
    alpha = ImageChops.multiply(body, alpha)
    out = Image.new('RGBA', (BOX * scale, BOX * scale), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out

def write_imageset(name):
    folder = os.path.join(ASSETS, f'glyph-{name}.imageset')
    os.makedirs(folder, exist_ok=True)
    images = []
    for scale in (2, 3):
        file = f'{name}@{scale}x.png'
        render(name, scale).save(os.path.join(folder, file))
        images.append({'filename': file, 'idiom': 'universal', 'scale': f'{scale}x'})
    with open(os.path.join(folder, 'Contents.json'), 'w') as f:
        json.dump({'images': images, 'info': {'author': 'xcode', 'version': 1},
                   'properties': {'template-rendering-intent': 'template'}}, f, indent=2)
        f.write('\n')

def tint(img, rgb):
    out = Image.new('RGBA', img.size, rgb + (0,))
    out.putalpha(img.getchannel('A'))
    return out

def sheet(path):
    rows = [((0, 0, 0), (255, 255, 255), (255, 159, 10)), ((245, 245, 247), (28, 28, 30), (255, 159, 10))]
    cell, pad = 84 * 2, 24
    W = pad + (cell + pad) * len(GLYPHS)
    H = (cell + pad) * 2 + pad + 80
    out = Image.new('RGBA', (W, H), (60, 60, 64, 255))
    d = ImageDraw.Draw(out)
    y = pad
    for bg, ink, amber in rows:
        d.rectangle([0, y - pad // 2, W, y + cell + pad // 2], fill=bg + (255,))
        x = pad
        for name in GLYPHS:
            img = tint(render(name, 6), amber if name == 'lock-open' else ink)
            out.alpha_composite(img, (x, y))
            x += cell + pad
        y += cell + pad
    # true size: 26 pt at 2x and 3x, night and day
    y += pad // 2
    x = pad
    for scale in (2, 3):
        for bg, ink, amber in rows:
            for name in GLYPHS:
                s = 26 * scale
                img = tint(render(name, 6).resize((s, s), Image.LANCZOS), amber if name == 'lock-open' else ink)
                d.rectangle([x - 6, y - 6, x + s + 6, y + s + 6], fill=bg + (255,))
                out.alpha_composite(img, (x, y))
                x += s + 16
            x += 16
    out.save(path)

if __name__ == '__main__':
    for name in GLYPHS:
        write_imageset(name)
    if len(sys.argv) > 1:
        sheet(sys.argv[1])
