"""Generate platform icons from the same 64-unit geometry as BrandMark.
Run: python3 tool/generate_brand_assets.py (requires Pillow).
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
GREEN = '#153F32'
CREAM = '#FAFAF6'
INK = '#F5F4E8'
MINT = '#B9DAC8'
SHIELD = 'M32 12L49 19V33C49 44 42 51 32 56C22 51 15 44 15 33V19Z'
A = 'M24 40L32 26L40 40'
TILE = 'M16 0H48Q64 0 64 16V48Q64 64 48 64H16Q0 64 0 48V16Q0 0 16 0Z'

def curve(p0, p1, p2, p3):
    points = []
    for step in range(65):
        t = step / 64
        points.append(tuple(
            (1-t)**3*p0[axis] + 3*(1-t)**2*t*p1[axis] +
            3*(1-t)*t*t*p2[axis] + t**3*p3[axis]
            for axis in [0, 1]
        ))
    return points

def render(size, tile=True, rounded=False):
    scale = size * 4 / 64
    im = Image.new('RGBA', (size*4, size*4), (0,0,0,0))
    d = ImageDraw.Draw(im)
    if tile:
        if rounded: d.rounded_rectangle((0,0,size*4-1,size*4-1), radius=16*scale, fill=GREEN)
        else: d.rectangle((0,0,size*4-1,size*4-1), fill=GREEN)
    def line(points, color):
        pts = [(round(x*scale), round(y*scale)) for x,y in points]
        width = round(2.5*scale)
        d.line(pts, fill=color, width=width, joint='curve')
        for x,y in [pts[0],pts[-1]]:
            r=width/2
            d.ellipse((x-r,y-r,x+r,y+r), fill=color)
    shield=[(32,12),(49,19),(49,33)] + curve((49,33),(49,44),(42,51),(32,56)) + curve((32,56),(22,51),(15,44),(15,33)) + [(15,19),(32,12)]
    line(shield,INK)
    line([(24,40),(32,26),(40,40)],INK)
    line([(28,35),(36,35)],MINT)
    return im.resize((size,size),Image.Resampling.LANCZOS)

def save(path, size, **kw):
    path=ROOT/path
    path.parent.mkdir(parents=True, exist_ok=True)
    im=render(size, **kw)
    if kw.get('tile',True) and not kw.get('rounded',False): im=im.convert('RGB')
    im.save(path)

def vector(viewport=64, size=96, transform='', tile=True):
    group=f'<group {transform}>' if transform else '<group>'
    return f'''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="{size}dp" android:height="{size}dp" android:viewportWidth="{viewport}" android:viewportHeight="{viewport}">
{group}
{f'<path android:fillColor="{GREEN}" android:pathData="{TILE}" />' if tile else ''}
<path android:fillColor="@android:color/transparent" android:strokeColor="{INK}" android:strokeWidth="2.5" android:strokeLineJoin="round" android:strokeLineCap="round" android:pathData="{SHIELD}" />
<path android:fillColor="@android:color/transparent" android:strokeColor="{INK}" android:strokeWidth="2.5" android:strokeLineJoin="round" android:strokeLineCap="round" android:pathData="{A}" />
<path android:strokeColor="{MINT}" android:strokeWidth="2.5" android:strokeLineCap="round" android:pathData="M28 35H36" />
</group></vector>
'''

for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    save(Path(f'android/app/src/main/res/mipmap-{density}/ic_launcher.png'),size)
for size in [192,512]:
    for name in ['Icon','Icon-maskable']:
        save(Path(f'web/icons/{name}-{size}.png'),size)
save(Path('web/favicon.png'),64,rounded=True)
save(Path('assets/branding/app-icon.png'),1024)
svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="16" fill="{GREEN}"/><g fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="{SHIELD}"/><path d="{A}"/><path d="M28 35H36" stroke="{MINT}"/></g></svg>'
(ROOT/'assets/branding/brand-mark.svg').write_text(svg+'\n')
res=ROOT/'android/app/src/main/res'
(res/'drawable/brand_launch.xml').write_text(vector())
(res/'drawable/brand_splash.xml').write_text(vector(viewport=192,size=288,transform='android:translateX="64" android:translateY="64"'))
(res/'drawable/ic_launcher_foreground.xml').write_text(vector(viewport=108,size=108,transform='android:translateX="2.8" android:translateY="2.8" android:scaleX="1.6" android:scaleY="1.6"',tile=False))
(res/'mipmap-anydpi-v26').mkdir(exist_ok=True)
(res/'mipmap-anydpi-v26/ic_launcher.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
<background android:drawable="@color/brand_green" />
<foreground android:drawable="@drawable/ic_launcher_foreground" />
<monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
''')
icons=ROOT/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((icons/'Contents.json').read_text())['images']:
    if 'filename' in entry:
        save((icons/entry['filename']).relative_to(ROOT),round(float(entry['size'].split('x')[0])*float(entry['scale'][:-1])))
for density,size in [('',96),('@2x',192),('@3x',288)]:
    save(Path(f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{density}.png'),size,rounded=True)
print('Generated Android adaptive/legacy icons, iOS icons, web icons/favicon and native splash marks.')
