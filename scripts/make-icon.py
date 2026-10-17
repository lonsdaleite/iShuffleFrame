import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
out = sys.argv[1]

def gradient(w, h, top, bottom):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img

def photo(w, h, scene):
    border = int(w * 0.06)
    card = Image.new("RGBA", (w, h), (250, 250, 247, 255))
    iw, ih = w - 2 * border, h - 2 * border
    sky_top, sky_bottom, sun, hill1, hill2 = scene
    pic = gradient(iw, ih, sky_top, sky_bottom).convert("RGBA")
    d = ImageDraw.Draw(pic)
    r = int(ih * 0.13)
    cx, cy = int(iw * 0.72), int(ih * 0.30)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=sun)
    d.polygon([(0, ih), (0, int(ih * 0.62)), (int(iw * 0.35), int(ih * 0.42)), (int(iw * 0.7), int(ih * 0.68)), (iw, int(ih * 0.55)), (iw, ih)], fill=hill1)
    d.polygon([(0, ih), (0, int(ih * 0.82)), (int(iw * 0.45), int(ih * 0.66)), (iw, int(ih * 0.86)), (iw, ih)], fill=hill2)
    card.paste(pic, (border, border))
    return card

bg = gradient(S, S, (38, 52, 92), (10, 12, 24)).convert("RGBA")

scenes = [
    ((255, 170, 120), (255, 214, 160), (255, 245, 220), (190, 90, 110), (120, 50, 90)),   # sunset
    ((120, 200, 230), (200, 236, 245), (255, 250, 210), (80, 170, 140), (40, 120, 100)),  # summer
    ((70, 120, 220), (150, 200, 255), (255, 236, 140), (90, 170, 80), (50, 120, 60)),     # front
]
placements = [(-16, (-40, 10)), (11, (40, -20)), (-3, (0, 20))]
cw, ch = int(S * 0.62), int(S * 0.50)
for scene, (angle, (dx, dy)) in zip(scenes, placements):
    card = photo(cw, ch, scene)
    pad = 60
    layer = Image.new("RGBA", (cw + 2 * pad, ch + 2 * pad), (0, 0, 0, 0))
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rectangle([pad, pad + 14, pad + cw, pad + ch + 14], fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    layer.alpha_composite(shadow)
    layer.alpha_composite(card, (pad, pad))
    layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = (S - layer.width) // 2 + dx
    y = (S - layer.height) // 2 + dy
    bg.alpha_composite(layer, (x, y))

bg.convert("RGB").save(out)
