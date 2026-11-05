#!/usr/bin/env python3
# Writes Design/AppIcon.svg when run from Design/. Render each PNG in Meetball/Assets.xcassets/AppIcon.appiconset
# (16-1024 px) from it with any SVG renderer, e.g. `rsvg-convert -w 512 AppIcon.svg -o icon_512.png`.
# Builds the Meetball app icon SVG: an SK-1 cream chassis with an olive LCD (seven-segment "9:30") and the orange "ball" key.
SEG = {'0':'abcdef','1':'bc','2':'abged','3':'abgcd','4':'fgbc','5':'afgcd','6':'afgedc','7':'abc','8':'abcdefg','9':'abcdfg'}
def segs(x, y, w, h, t, skew):
    # polygons for segments a..g of a digit box at x,y (top-left), width w, height h, thickness t
    hh = h/2; g = t*0.18
    def P(pts):  # apply skew (lean right toward the top)
        return [(px + (y+h-py)*skew, py) for px,py in pts]
    hor = lambda yy: P([(x+g+t/2,yy),(x+t+g,yy-t/2),(x+w-t-g,yy-t/2),(x+w-g-t/2,yy),(x+w-t-g,yy+t/2),(x+t+g,yy+t/2)])
    ver = lambda xx,y0,y1: P([(xx,y0+g+t/2),(xx+t/2,y0+t+g),(xx+t/2,y1-t-g),(xx,y1-g-t/2),(xx-t/2,y1-t-g),(xx-t/2,y0+t+g)])
    return {'a':hor(y+t/2),'g':hor(y+hh),'d':hor(y+h-t/2),
            'f':ver(x+t/2,y,y+hh),'b':ver(x+w-t/2,y,y+hh),'e':ver(x+t/2,y+hh,y+h),'c':ver(x+w-t/2,y+hh,y+h)}
def poly(pts, fill, op=1):
    return '<polygon points="%s" fill="%s" fill-opacity="%s"/>' % (' '.join('%.1f,%.1f'%p for p in pts), fill, op)

ink = '#1E2318'
dw, dh, t, skew = 96, 168, 22, 0.09
y0 = 268
out = []
cx = 312
for ch in '9:30':
    if ch == ':':
        for yy in (y0+dh*0.32, y0+dh*0.70):
            out.append('<rect x="%.1f" y="%.1f" width="%d" height="%d" rx="3" fill="%s"/>' % (cx+8+(y0+dh-yy)*skew, yy-t/2, t, t, ink))
        cx += 46
        continue
    s = segs(cx, y0, dw, dh, t, skew)
    for k, pts in s.items():
        lit = k in SEG[ch]
        out.append(poly(pts, ink, 1 if lit else 0.08))
    cx += dw + 24
seven = '\n'.join(out)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <linearGradient id="chassis" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FDFCFA"/><stop offset="1" stop-color="#E8E4DC"/></linearGradient>
  <linearGradient id="bezel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#C9C4B9"/><stop offset="1" stop-color="#E2DED6"/></linearGradient>
  <linearGradient id="glass" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#D3D9BE"/><stop offset="0.55" stop-color="#C3CAAD"/><stop offset="1" stop-color="#B9C0A2"/></linearGradient>
  <linearGradient id="sheen" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.35"/><stop offset="0.45" stop-color="#fff" stop-opacity="0"/></linearGradient>
  <linearGradient id="orange" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FF8045"/><stop offset="1" stop-color="#F2520F"/></linearGradient>
  <linearGradient id="well" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#D9D5CC"/><stop offset="1" stop-color="#E9E6DF"/></linearGradient>
  <radialGradient id="ballHi" cx="0.38" cy="0.3" r="0.6"><stop offset="0" stop-color="#fff" stop-opacity="0.55"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
  <radialGradient id="lamp" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#5FE3C8"/><stop offset="0.5" stop-color="#1F9E86"/><stop offset="1" stop-color="#1F9E86" stop-opacity="0"/></radialGradient>
  <pattern id="grid" width="8" height="8" patternUnits="userSpaceOnUse"><rect width="8" height="8" fill="none"/><path d="M8 0V8M0 8H8" stroke="#1E2318" stroke-opacity="0.05" stroke-width="1.5"/></pattern>
  <filter id="drop" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000" flood-opacity="0.28"/></filter>
  <filter id="inner" x="-10%" y="-10%" width="120%" height="120%">
    <feOffset dy="6"/><feGaussianBlur stdDeviation="6" result="b"/>
    <feComposite in="SourceGraphic" in2="b" operator="arithmetic" k2="-1" k3="1" result="s"/>
    <feFlood flood-color="#000" flood-opacity="0.35"/><feComposite in2="s" operator="in"/><feComposite in2="SourceGraphic" operator="over"/>
  </filter>
</defs>
<!-- chassis: a cream key on its skirt -->
<g filter="url(#drop)">
  <rect x="100" y="112" width="824" height="812" rx="184" fill="#C7C2B7"/>
  <rect x="100" y="100" width="824" height="800" rx="184" fill="url(#chassis)"/>
</g>
<rect x="104" y="104" width="816" height="792" rx="180" fill="none" stroke="#fff" stroke-opacity="0.9" stroke-width="4"/>
<!-- LCD in its bezel -->
<rect x="196" y="196" width="632" height="296" rx="44" fill="url(#bezel)"/>
<g filter="url(#inner)">
  <rect x="216" y="216" width="592" height="256" rx="28" fill="url(#glass)"/>
</g>
<rect x="216" y="216" width="592" height="256" rx="28" fill="url(#grid)"/>
<rect x="216" y="216" width="592" height="256" rx="28" fill="url(#sheen)"/>
<rect x="216" y="216" width="592" height="256" rx="28" fill="none" stroke="#1E2318" stroke-opacity="0.35" stroke-width="3"/>
{seven}
<!-- speaker grille -->
<g fill="#8F8A80">
''' + '\n'.join(f'<circle cx="{232+c*30}" cy="{612+r*30}" r="8"/>' for r in range(4) for c in range(4)) + f'''
</g>
<!-- the orange "ball" key, sunk in a round well -->
<circle cx="512" cy="700" r="150" fill="url(#well)"/>
<circle cx="512" cy="700" r="150" fill="none" stroke="#000" stroke-opacity="0.12" stroke-width="4"/>
<circle cx="512" cy="714" r="120" fill="#B93A07"/>
<circle cx="512" cy="700" r="120" fill="url(#orange)"/>
<circle cx="512" cy="700" r="120" fill="url(#ballHi)"/>
<circle cx="512" cy="700" r="118" fill="none" stroke="#fff" stroke-opacity="0.35" stroke-width="3"/>
<!-- ready lamp -->
<circle cx="760" cy="612" r="34" fill="url(#lamp)"/>
<circle cx="760" cy="612" r="13" fill="#1F9E86"/>
<circle cx="756" cy="608" r="5" fill="#fff" fill-opacity="0.7"/>
<rect x="716" y="700" width="88" height="22" rx="11" fill="#D3CFC5"/>
<rect x="716" y="744" width="88" height="22" rx="11" fill="#D3CFC5"/>
</svg>'''
open('AppIcon.svg','w').write(svg)
