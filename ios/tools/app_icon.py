"""Builds Golda's iOS app icon, ios/Golda/Resources/AppIcon.icon, from the coin in tools/coin.py.

Usage: python3 ios/tools/app_icon.py [output.icon]

The coin's geometry and shading come from tools/coin.py, the source of the Android launcher icon, so
both platforms show the same coin and a change to it reaches iOS by re-running this script. The
result is an Icon Composer document: Xcode compiles it into the light, dark, clear and tinted icons
of iOS 26 and draws the Liquid Glass rim and the shadow itself. Preview a rendition with
    ictool AppIcon.icon --export-image --output-file out.png --platform iOS --rendition Dark \
        --width 1024 --height 1024 --scale 1
(ictool ships inside Xcode's Icon Composer.app, in Contents/Executables).
"""
import contextlib
import io
import json
import os
import pathlib
import runpy
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'ios/Golda/Resources/AppIcon.icon'

# coin.py writes the Android launcher drawables into the working directory as it runs; run it in a
# scratch directory so only its geometry and shading are taken and the Android files stay untouched.
with tempfile.TemporaryDirectory() as scratch:
    here = os.getcwd()
    os.chdir(scratch)
    try:
        with contextlib.redirect_stderr(io.StringIO()):
            coin = runpy.run_path(str(ROOT / 'tools/coin.py'))
    finally:
        os.chdir(here)

CANVAS = 1024   # Icon Composer's iOS canvas, in points
WIDTH = 0.66    # the coin's width as a share of the canvas: clear of the corners, as big as Android's
# Background: the app's page grey, light and dark (DESIGN.md), so gold stays the only colour (D34).
# The automatic gradient lights it from the top like the system's own icons.
PAGE_LIGHT, PAGE_DARK = '#F4F4F5', '#1F1F23'


def layer(body):
    # A canvas-sized SVG in coin.py's 108-unit space, cropped so the coin sits centred at WIDTH.
    side = 2 * coin['R'] / WIDTH
    o = coin['C'] - side / 2
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
            f'viewBox="{o:.4f} {o:.4f} {side:.4f} {side:.4f}">{body}</svg>\n')


def grey(level):
    v = round(255 * level)
    return f'#{v:02X}{v:02X}{v:02X}'


def srgb(hex_colour):
    r, g, b = (int(hex_colour[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f'srgb:{r:.5f},{g:.5f},{b:.5f},1.00000'


# The gold coin exactly as on Android: a plain gold decagon under the facets hides their seams.
gold = f'<path d="{coin["outline"]}" fill="{coin["gold"](0.5)}"/>' + ''.join(coin['svg'])

def facet_brightness(face):
    # coin.py's soft cut, as it applies it to the gold facets.
    b, _ = coin['shade'](face)
    return 0.55 + (b - 0.55) * coin['SOFT']


def mono_level(brightness):
    # The Android monochrome icon's opacity for a facet of this brightness.
    return 0.45 + 0.55 * brightness


# The clear and tinted icons get the coin in greys, the facets set apart by brightness as in the
# Android monochrome icon. Opaque greys over a plain decagon rather than its white-with-opacity
# facets: Liquid Glass reads every soft seam between translucent facets as an edge and lights it
# up as a bright dot.
mono = f'<path d="{coin["outline"]}" fill="{grey(mono_level(0.5))}"/>' + ''.join(
    f'<path d="{coin["path"](f)}" fill="{grey(mono_level(facet_brightness(f)))}"/>'
    for f in coin['faces'])

document = {
    'fill-specializations': [
        {'value': {'automatic-gradient': srgb(PAGE_LIGHT)}},
        {'appearance': 'dark', 'value': {'automatic-gradient': srgb(PAGE_DARK)}},
    ],
    'groups': [
        {
            'layers': [
                {
                    'name': 'Coin',
                    'image-name-specializations': [
                        {'value': 'coin.svg'},
                        {'appearance': 'tinted', 'value': 'coin-mono.svg'},
                    ],
                    # Glass gives the coin a lit rim, the edge a real coin catches.
                    'glass': True,
                },
            ],
            # A shadow tinted by the gold rather than grey; no translucency, which would let the
            # grey background through and dull the gold.
            'shadow': {'kind': 'layer-color', 'opacity': 0.5},
            'translucency': {'enabled': False, 'value': 0.5},
        },
    ],
    'supported-platforms': {'squares': ['iOS']},
}

if OUT.exists():
    shutil.rmtree(OUT)
(OUT / 'Assets').mkdir(parents=True)
(OUT / 'Assets/coin.svg').write_text(layer(gold), newline='\n')
(OUT / 'Assets/coin-mono.svg').write_text(layer(mono), newline='\n')
# In Icon Composer's own JSON style (sorted keys, " : "), so a save from Icon Composer diffs cleanly.
icon_json = json.dumps(document, indent=2, sort_keys=True, separators=(',', ' : '))
(OUT / 'icon.json').write_text(icon_json + '\n', newline='\n')
print(OUT)
