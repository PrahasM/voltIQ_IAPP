"""Render the favicon bolt on an opaque green gradient; requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
SIZE = 2048
image = Image.new("RGB", (SIZE, SIZE))
pixels = image.load()
for y in range(SIZE):
    for x in range(SIZE):
        blend = (x + y) / (2 * (SIZE - 1))
        pixels[x, y] = tuple(round(a + (b - a) * blend) for a, b in zip((34, 197, 94), (21, 128, 61)))
points = [(36, 8), (16, 36), (30, 36), (28, 56), (48, 28), (34, 28)]
points = [(x / 64 * SIZE, y / 64 * SIZE) for x, y in points]
shadow = Image.new("RGBA", (SIZE, SIZE))
ImageDraw.Draw(shadow).polygon([(x, y + 24) for x, y in points], fill=(5, 46, 22, 75))
shadow = shadow.filter(ImageFilter.GaussianBlur(28))
image = Image.alpha_composite(image.convert("RGBA"), shadow)
ImageDraw.Draw(image).polygon(points, fill="white")
image.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS).save(ROOT / "VoltIQ/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
