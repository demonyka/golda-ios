#!/usr/bin/env python3
"""Builds the App Store promo frames (1320x2868, RGB, no alpha) from the raw simulator captures.

Raw captures live in screenshots/raw/, results go to screenshots/ru/. Needs Pillow:
    python3 -m venv /tmp/promo-venv && /tmp/promo-venv/bin/pip install pillow
    /tmp/promo-venv/bin/python docs/ios/appstore/make_promo.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
RAW = HERE / "screenshots" / "raw"
OUT = HERE / "screenshots" / "ru"

W, H = 1320, 2868
SHOT_WIDTH = round(W * 0.84)
RADIUS = 110
SHOT_TOP = 640

# A warm dark gradient: graphite with a hint of gold, so the light app screens stand out.
TOP_COLOR = (44, 38, 30)
BOTTOM_COLOR = (16, 15, 14)
HEADLINE_COLOR = (250, 246, 238)
SUBLINE_COLOR = (214, 186, 120)  # the brand gold, muted

# (output name, raw capture, headline lines, subline)
FRAMES = [
    ("01-today", "home.png", ["Сколько можно", "потратить сегодня"], "Дневной бюджет до зарплаты"),
    ("02-voice", "voice.png", ["Скажи трату —", "Golda запишет"], "Одна фраза, и операции на месте"),
    ("03-accounts", "accounts.png", ["Все счета и долги", "в одном месте"], "Карты, вклады, кредиты и валюты"),
    ("04-goals", "goals.png", ["Цели и покупки,", "о которых стоит подумать"], "Отказ от покупки приближает цель"),
    ("05-insights", "insights.png", ["Куда уходят деньги"], "Категории и расходы по дням"),
    ("06-currencies", "currencies.png", ["Любые валюты", "в одном бюджете"], "Каждая сумма сразу в выбранных валютах"),
]


def font(size, bold):
    """SF Pro (the variable SFNS) when present, Helvetica Neue otherwise."""
    sf = Path("/System/Library/Fonts/SFNS.ttf")
    if sf.exists():
        f = ImageFont.truetype(str(sf), size)
        # Axes: width, optical size, grade, weight. Display optical size for the big type.
        f.set_variation_by_axes([100, 96 if size >= 60 else 28, 400, 700 if bold else 500])
        return f
    return ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", size, index=1 if bold else 0)


def gradient():
    column = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(TOP_COLOR, BOTTOM_COLOR)))
    canvas = column.resize((W, H))
    # A soft gold glow behind the headline.
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse((-200, -500, W + 200, 900), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(220))
    gold = Image.new("RGB", (W, H), (150, 115, 50))
    return Image.composite(gold, canvas, glow)


def centered(draw, y, text, f, fill):
    width = draw.textlength(text, font=f)
    draw.text(((W - width) / 2, y), text, font=f, fill=fill)


def headline_size():
    """One size for every frame: the largest at which every line keeps a 90 px margin."""
    draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    lines = [line for _, _, frame_lines, _ in FRAMES for line in frame_lines]
    size = 100
    while max(draw.textlength(line, font=font(size, True)) for line in lines) > W - 2 * 90:
        size -= 2
    return size


def frame(raw_path, lines, subline, size):
    canvas = gradient()
    draw = ImageDraw.Draw(canvas)
    headline = font(size, True)
    # The text block sits centred above the screenshot, so one- and two-line frames balance alike.
    line_height = round(size * 1.18)
    block = len(lines) * line_height + (86 if subline else 0)
    y = 70 + (SHOT_TOP - 70 - block) // 2
    for line in lines:
        centered(draw, y, line, headline, HEADLINE_COLOR)
        y += line_height
    if subline:
        centered(draw, y + 26, subline, font(50, False), SUBLINE_COLOR)

    shot = Image.open(raw_path).convert("RGB")
    height = round(shot.height * SHOT_WIDTH / shot.width)
    shot = shot.resize((SHOT_WIDTH, height), Image.LANCZOS)
    radius = round(RADIUS * SHOT_WIDTH / W)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width - 1, shot.height - 1), radius, fill=255)
    x = (W - SHOT_WIDTH) // 2

    shadow = Image.new("L", (W, H + height), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x, SHOT_TOP + 24, x + SHOT_WIDTH, SHOT_TOP + 24 + height), radius, fill=150)
    shadow = shadow.filter(ImageFilter.GaussianBlur(40)).crop((0, 0, W, H))
    canvas = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), canvas, shadow)

    # A thin light rim so the light screen reads as a device edge on the dark ground.
    rim = Image.new("L", (W, H + height), 0)
    ImageDraw.Draw(rim).rounded_rectangle((x - 4, SHOT_TOP - 4, x + SHOT_WIDTH + 4, SHOT_TOP + height + 4), radius + 4, fill=255)
    canvas = Image.composite(Image.new("RGB", (W, H), (70, 64, 56)), canvas, rim.crop((0, 0, W, H)))

    canvas.paste(shot, (x, SHOT_TOP), mask)  # the bottom bleeds off the canvas
    return canvas


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    size = headline_size()
    for name, raw, lines, subline in FRAMES:
        image = frame(RAW / raw, lines, subline, size)
        assert image.size == (W, H) and image.mode == "RGB"
        path = OUT / f"{name}.png"
        image.save(path, optimize=True)
        print(path, f"{path.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
