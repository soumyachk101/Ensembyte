#!/usr/bin/env python3
"""
Sanitizes all website images, tour assets, video posters, and release screenshots for Swarm Code:
1. Replaces all residual text occurrences of "Droppy Code", "getdroppy.app", and "DroppyCode build"
   with "Swarm Code", "swarmcode.dev", and "SwarmCode build".
2. Replaces Droppy water-droplet app icons with the official Swarm Code app icon.
3. Fixes window.webp with a seamless, unified "Welcome to Swarm Code" modal title and terminal line.
4. Preserves authentic Hydra features, marks, buttons, cards, and head glyphs.
   DOES NOT place any Swarm bee logos over Hydra marks!
5. Outputs pristine WebP files directly into website/assets/app/ and website/assets/app/tour/.
6. Generates video posters (1320x824 WebP) including slider-poster.webp.
7. Updates in-app xcassets tour imagesets (1320x824 PNG).
8. Syncs pristine screenshots into SwarmCode-Release/assets/screenshots/.
"""

import os
import pathlib
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "build.noindex" / "remote_audit"
OUT_APP = ROOT / "website" / "assets" / "app"
OUT_TOUR = OUT_APP / "tour"
OUT_THEMES = OUT_APP / "themes"
RELEASE_SCREENSHOTS = ROOT / "Quorumly-Release" / "assets" / "screenshots"
XCASSETS = ROOT / "Quorumly" / "Resources" / "Assets.xcassets"
APP_ICON_PATH = XCASSETS / "AppIcon.appiconset" / "icon_256x256.png"

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
MONO_FONT_PATH = "/System/Library/Fonts/SFNSMono.ttf"

OUT_APP.mkdir(parents=True, exist_ok=True)
OUT_TOUR.mkdir(parents=True, exist_ok=True)
OUT_THEMES.mkdir(parents=True, exist_ok=True)
RELEASE_SCREENSHOTS.mkdir(parents=True, exist_ok=True)


def inpaint_line(arr, x0, x1, y0, y1):
    """Interpolates vertically between (y0, x) and (y1, x) across all columns in [x0, x1]."""
    x0 = max(0, int(x0))
    x1 = min(arr.shape[1], int(x1))
    y0 = max(0, int(y0))
    y1 = min(arr.shape[0], int(y1))
    
    top = arr[y0, x0:x1]
    bot = arr[y1 - 1, x0:x1]
    H = y1 - y0
    if H <= 0:
        return
    for i in range(H):
        alpha = i / float(H)
        arr[y0 + i, x0:x1] = (1.0 - alpha) * top + alpha * bot


def get_swarm_app_icon(size=(102, 102)):
    """Loads and resizes the official Swarm Code squircle app icon."""
    im = Image.open(APP_ICON_PATH).convert('RGBA')
    return im.resize(size, Image.Resampling.LANCZOS)


# ----------------------------------------------------------------------
# Sanitizers
# ----------------------------------------------------------------------

def sanitize_window():
    print("Sanitizing window.webp...")
    im = Image.open(SRC_DIR / "window.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    # 1. Terminal line: replace 'DroppyCode build' with 'SwarmCode build'
    inpaint_line(arr, 834, 946, 696, 718)
    
    # 2. Modal title: replace entire 'Welcome to Droppy Code' line seamlessly
    # Bounding box is x=720..1360, y=895..965. Center is at x=1040.
    inpaint_line(arr, 720, 1360, 895, 965)
    
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    
    # Draw terminal text
    font_term = ImageFont.truetype(FONT_PATH, 14)
    font_term.set_variation_by_name('Medium')
    d.text((836, 700), "SwarmCode build", fill=(150, 160, 172, 255), font=font_term)
    
    # Draw unified centered modal title
    font_modal = ImageFont.truetype(FONT_PATH, 46)
    font_modal.set_variation_by_name('Bold')
    title_text = "Welcome to Swarm Code"
    bbox = font_modal.getbbox(title_text)
    tw = bbox[2] - bbox[0]
    tx = 1040 - tw // 2
    ty = 908
    d.text((tx, ty), title_text, fill=(245, 248, 252, 255), font=font_modal)
    
    out_tour = OUT_TOUR / "window.webp"
    im.convert('RGB').save(out_tour, 'WEBP', quality=92, method=6)
    print(f"Saved {out_tour}")


def sanitize_slider():
    print("Sanitizing slider.webp...")
    im = Image.open(SRC_DIR / "slider.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    # 1. Inpaint old squircle
    inpaint_line(arr, 985, 1097, 490, 602)
    # 2. Inpaint text line
    inpaint_line(arr, 610, 1470, 645, 725)
    
    im = Image.fromarray(arr.astype(np.uint8))
    
    # 3. Paste Swarm Code AppIcon
    appicon = get_swarm_app_icon((102, 102))
    im.paste(appicon, (990, 495), appicon)
    
    # 4. Render centered text: 'What should we build in ' + 'Swarm Code' + '?'
    font = ImageFont.truetype(FONT_PATH, 56)
    font.set_variation_by_name('Regular')
    
    t1 = 'What should we build in '
    t2 = 'Swarm Code'
    t3 = '?'
    
    bbox1 = font.getbbox(t1)
    bbox2 = font.getbbox(t2)
    bbox3 = font.getbbox(t3)
    
    w1 = bbox1[2] - bbox1[0]
    w2 = bbox2[2] - bbox2[0]
    w3 = bbox3[2] - bbox3[0]
    total_w = w1 + w2 + w3
    
    start_x = int(1040 - total_w / 2)
    y_text = 658
    
    d = ImageDraw.Draw(im)
    text_color = (235, 240, 245, 255)
    sub_color = (160, 175, 190, 255)
    
    d.text((start_x, y_text), t1, fill=text_color, font=font)
    x2 = start_x + w1
    d.text((x2, y_text), t2, fill=text_color, font=font)
    x3 = x2 + w2
    d.text((x3, y_text), t3, fill=text_color, font=font)
    
    # Draw dotted/dashed underline under Swarm Code
    cur_x = x2 + 2
    underline_y = 717
    end_underline = x2 + w2 - 2
    while cur_x < end_underline:
        d.line([(cur_x, underline_y), (min(cur_x + 8, end_underline), underline_y)], fill=sub_color, width=3)
        cur_x += 14
        
    out_tour = OUT_TOUR / "slider.webp"
    im.convert('RGB').save(out_tour, 'WEBP', quality=92, method=6)
    print(f"Saved {out_tour}")


def sanitize_pairs():
    print("Sanitizing pairs.webp...")
    im = Image.open(SRC_DIR / "pairs.webp").convert('RGBA')
    
    # 1. Inpaint old squircle
    arr = np.array(im)
    bg = arr[490, 1040].copy()
    arr[495:600, 990:1095] = bg
    im = Image.fromarray(arr)
    
    # 2. Paste Swarm Code AppIcon
    appicon = get_swarm_app_icon((102, 102))
    im.paste(appicon, (992, 496), appicon)
    
    # 3. Inpaint old text 'Drop' horizontally between x=1134 and x=1243 (before popover shadow at 1244)
    arr = np.array(im, dtype=np.float32)
    left_col = arr[650:717, 1133].copy()
    right_col = arr[650:717, 1243].copy()
    w = 1243 - 1134
    for i in range(w):
        t = i / float(w - 1)
        arr[650:717, 1134 + i] = (1.0 - t) * left_col + t * right_col
    im = Image.fromarray(arr.astype(np.uint8))
    
    # 4. Render complete word 'Swarm' cleanly before popover (ending at x=1239, 4px before popover shadow)
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT_PATH, 35)
    sx = 1137
    sy = 666
    draw.text((sx, sy), 'Swarm', fill=(240, 246, 252, 255), font=font)
    bbox = draw.textbbox((sx, sy), 'Swarm', font=font)
    
    # Crisp authentic dotted underline under 'Swarm' (ends exactly under 'm', never clipping into popover)
    cur_x = sx
    while cur_x + 9 <= bbox[2] + 2:
        draw.line([(cur_x, 708), (cur_x + 9, 708)], fill=(150, 164, 172, 220), width=2)
        cur_x += 18
        
    # Keep Model Picker popover on the right (x >= 1244) 100% pristine from original capture
    res_arr = np.array(im)
    orig_arr = np.array(Image.open(SRC_DIR / "pairs.webp").convert('RGBA'))
    res_arr[:, 1244:] = orig_arr[:, 1244:]
    im = Image.fromarray(res_arr)
    
    out_tour = OUT_TOUR / "pairs.webp"
    im.convert('RGB').save(out_tour, 'WEBP', quality=95, method=6)
    print(f"Saved {out_tour}")


def sanitize_recipes():
    print("Sanitizing recipes.webp...")
    im = Image.open(SRC_DIR / "recipes.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    # Squircle in recipes.webp is at (961, 508), size 102x102
    inpaint_line(arr, 955, 1069, 502, 616)
    im = Image.fromarray(arr.astype(np.uint8))
    
    appicon = get_swarm_app_icon((102, 102))
    im.paste(appicon, (961, 508), appicon)
    
    out_app = OUT_APP / "recipes.webp"
    im.convert('RGB').save(out_app, 'WEBP', quality=92, method=6)
    print(f"Saved {out_app}")


def sanitize_diff():
    print("Sanitizing diff.webp...")
    im = Image.open(SRC_DIR / "diff.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    # Replace diff file path at x=638..1090, y=286..312
    inpaint_line(arr, 638, 1090, 286, 312)
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    
    font = ImageFont.truetype(FONT_PATH, 19)
    font.set_variation_by_name('Regular')
    full_text = 'SwarmCode/Views/Composer/ComposerView.swift'
    d.text((640, 288), full_text, fill=(215, 225, 235, 255), font=font)
    
    out_path = OUT_APP / "diff.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_sidebar():
    print("Sanitizing sidebar.webp...")
    im = Image.open(SRC_DIR / "sidebar.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    rows = [
        (299, 'Swarm Code'),
        (446, 'Swarm Code'),
        (546, 'swarmcode.dev'),
        (644, 'Swarm Code'),
        (742, 'Swarm Code'),
        (840, 'Swarm Code'),
        (938, 'Swarm Code'),
    ]
    
    for y_top, text in rows:
        inpaint_line(arr, 93, 265, y_top - 5, y_top + 28)
        
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    
    font = ImageFont.truetype(FONT_PATH, 20)
    font.set_variation_by_name('Medium')
    color = (155, 170, 185, 255)
    
    for y_top, text in rows:
        d.text((99, y_top), text, fill=color, font=font)
        
    out_path = OUT_APP / "sidebar.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_palette():
    print("Sanitizing palette.webp...")
    im = Image.open(SRC_DIR / "palette.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    rows = [
        (368, 'Swarm Code'),
        (444, 'Swarm Code'),
        (516, 'swarmcode.dev'),
        (592, 'Swarm Code'),
        (664, 'Swarm Code'),
        (740, 'Swarm Code'),
    ]
    for y_top, text in rows:
        inpaint_line(arr, 645, 765, y_top - 4, y_top + 24)
        
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT_PATH, 16)
    font.set_variation_by_name('Regular')
    color = (145, 160, 180, 255)
    
    for y_top, text in rows:
        d.text((650, y_top), text, fill=color, font=font)
        
    out_path = OUT_APP / "palette.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_queue():
    print("Sanitizing queue.webp...")
    im = Image.open(SRC_DIR / "queue.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    inpaint_line(arr, 695, 860, 814, 838)
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    
    font = ImageFont.truetype(FONT_PATH, 14)
    font.set_variation_by_name('Regular')
    d.text((698, 818), 'SwarmCode build', fill=(150, 160, 172, 255), font=font)
    
    out_path = OUT_APP / "queue.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_quote():
    print("Sanitizing quote.webp...")
    im = Image.open(SRC_DIR / "quote.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    inpaint_line(arr, 733, 890, 915, 938)
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    
    font = ImageFont.truetype(FONT_PATH, 14)
    font.set_variation_by_name('Regular')
    d.text((736, 918), 'SwarmCode build', fill=(150, 160, 172, 255), font=font)
    
    out_path = OUT_APP / "quote.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_slash():
    print("Sanitizing slash.webp...")
    im = Image.open(SRC_DIR / "slash.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    inpaint_line(arr, 734, 890, 959, 983)
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    
    font = ImageFont.truetype(FONT_PATH, 14)
    font.set_variation_by_name('Regular')
    d.text((737, 961), 'SwarmCode build', fill=(150, 160, 172, 255), font=font)
    
    out_path = OUT_APP / "slash.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_threads():
    print("Sanitizing threads.webp...")
    im = Image.open(SRC_DIR / "threads.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    # Sidebar rows
    rows = [
        (392, 'Swarm Code'),
        (516, 'Swarm Code'),
        (598, 'swarmcode.dev'),
        (678, 'Swarm Code'),
        (764, 'Swarm Code'),
        (846, 'Swarm Code'),
        (928, 'Swarm Code'),
    ]
    for y_top, text in rows:
        inpaint_line(arr, 273, 420, y_top - 4, y_top + 26)
        
    # Terminal line
    inpaint_line(arr, 708, 890, 834, 862)
    
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    
    font_side = ImageFont.truetype(FONT_PATH, 16)
    font_side.set_variation_by_name('Regular')
    color_side = (145, 160, 180, 255)
    
    for y_top, text in rows:
        d.text((275, y_top), text, fill=color_side, font=font_side)
        
    font_term = ImageFont.truetype(FONT_PATH, 14)
    font_term.set_variation_by_name('Regular')
    d.text((711, 837), 'SwarmCode build', fill=(150, 160, 172, 255), font=font_term)
    
    out_path = OUT_APP / "threads.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_notify():
    print("Sanitizing notify.webp...")
    im = Image.open(SRC_DIR / "notify.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    rows = [
        (284, 'Swarm Code'),
        (398, 'Swarm Code'),
        (465, 'Swarm Code'),
        (568, 'Swarm Code'),
        (634, 'swarmcode.dev'),
        (704, 'Swarm Code'),
        (770, 'Swarm Code'),
        (885, 'Swarm Code'),
        (951, 'swarmcode.dev'),
        (1021, 'swarmcode.dev'),
    ]
    for y_top, text in rows:
        inpaint_line(arr, 203, 330, y_top - 4, y_top + 24)
        
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    
    font = ImageFont.truetype(FONT_PATH, 14)
    font.set_variation_by_name('Regular')
    color = (145, 160, 180, 255)
    
    for y_top, text in rows:
        d.text((205, y_top), text, fill=color, font=font)
        
    out_path = OUT_APP / "notify.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_themes():
    print("Sanitizing themes.webp...")
    im = Image.open(SRC_DIR / "themes.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    
    # 4 panels in themes.webp:
    # Top-left (dark), Top-right (dark), Bottom-left (light), Bottom-right (dark)
    panels = [
        (325, 455, 478, 500, (150, 160, 172, 255)),
        (1365, 1495, 478, 500, (150, 160, 172, 255)),
        (325, 455, 1128, 1150, (90, 95, 105, 255)),
        (1365, 1495, 1128, 1150, (150, 160, 172, 255)),
    ]
    
    for x0, x1, y0, y1, _ in panels:
        inpaint_line(arr, x0, x1, y0, y1)
        
    im = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im)
    
    font = ImageFont.truetype(FONT_PATH, 11)
    font.set_variation_by_name('Regular')
    
    for x0, _, y0, _, color in panels:
        d.text((x0 + 2, y0 + 3), 'SwarmCode build', fill=color, font=font)
        
    out_tour = OUT_TOUR / "themes.webp"
    im.convert('RGB').save(out_tour, 'WEBP', quality=92, method=6)
    print(f"Saved {out_tour}")


def sanitize_hero():
    print("Sanitizing hero.webp (preserving authentic Hydra mark)...")
    im = Image.open(SRC_DIR / "hero.webp").convert('RGB')
    out_tour = OUT_TOUR / "hero.webp"
    out_app = OUT_APP / "hero.webp"
    im.save(out_tour, 'WEBP', quality=92, method=6)
    im.save(out_app, 'WEBP', quality=92, method=6)
    print(f"Saved {out_tour} and {out_app}")


def sanitize_hydra():
    print("Sanitizing hydra.webp (preserving authentic Hydra mark)...")
    im = Image.open(SRC_DIR / "hydra.webp").convert('RGB')
    out_path = OUT_TOUR / "hydra.webp"
    im.save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_intro():
    print("Sanitizing intro.webp...")
    im = Image.open(SRC_DIR / "intro.webp").convert('RGB')
    out_path = OUT_APP / "intro.webp"
    im.save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_panels():
    print("Sanitizing panels.webp...")
    im = Image.open(SRC_DIR / "panels.webp").convert('RGB')
    out_path = OUT_TOUR / "panels.webp"
    im.save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_question():
    print("Sanitizing question.webp...")
    im = Image.open(SRC_DIR / "question.webp").convert('RGB')
    out_path = OUT_APP / "question.webp"
    im.save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_plans():
    print("Sanitizing plans.webp...")
    im = Image.open(SRC_DIR / "plans.webp").convert('RGB')
    out_path = OUT_APP / "plans.webp"
    im.save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def sanitize_limits():
    print("Sanitizing limits.webp...")
    im = Image.open(SRC_DIR / "limits.webp").convert('RGB')
    out_path = OUT_APP / "limits.webp"
    im.save(out_path, 'WEBP', quality=92, method=6)
    print(f"Saved {out_path}")


def generate_posters():
    print("\nGenerating video posters (1320x824 WebP)...")
    posters = {
        "hero-poster.webp": OUT_TOUR / "hero.webp",
        "slider-poster.webp": OUT_TOUR / "slider.webp",
        "question-poster.webp": OUT_APP / "question.webp",
        "queue-poster.webp": OUT_APP / "queue.webp",
    }
    for poster_name, src_path in posters.items():
        im = Image.open(src_path).convert('RGB')
        im_resized = im.resize((1320, 824), Image.Resampling.LANCZOS)
        out_path = OUT_APP / poster_name
        im_resized.save(out_path, 'WEBP', quality=90, method=6)
        print(f"Saved poster {out_path}")


def update_xcassets():
    print("\nUpdating in-app xcassets tour images (1320x824 PNG)...")
    tour_assets = {
        "tour-welcome.imageset/tour-welcome@2x.png": OUT_TOUR / "window.webp",
        "tour-hydra.imageset/tour-hydra@2x.png": OUT_TOUR / "hydra.webp",
        "tour-pairs.imageset/tour-pairs@2x.png": OUT_TOUR / "pairs.webp",
        "tour-slider.imageset/tour-slider@2x.png": OUT_TOUR / "slider.webp",
        "tour-panels.imageset/tour-panels@2x.png": OUT_TOUR / "panels.webp",
        "tour-themes.imageset/tour-themes@2x.png": OUT_TOUR / "themes.webp",
        "tour-recipes.imageset/tour-recipes@2x.png": OUT_APP / "recipes.webp",
        "tour-threads.imageset/tour-threads@2x.png": OUT_APP / "threads.webp",
    }
    for asset_rel, webp_src in tour_assets.items():
        target = XCASSETS / asset_rel
        target.parent.mkdir(parents=True, exist_ok=True)
        im = Image.open(webp_src).convert('RGB')
        im_resized = im.resize((1320, 824), Image.Resampling.LANCZOS)
        im_resized.save(target, 'PNG')
        print(f"Updated {target}")


def sync_release_screenshots():
    print("\nSyncing release screenshots into Quorumly-Release/assets/screenshots/...")
    mapping = {
        "hero.webp": (OUT_TOUR / "hero.webp", (1320, 824)),
        "hydra.webp": (OUT_TOUR / "hydra.webp", (1320, 824)),
        "hydra-delegation.webp": (OUT_TOUR / "hydra.webp", (1320, 824)),
        "agents.webp": (OUT_TOUR / "panels.webp", (1320, 824)),
        "themes.webp": (OUT_TOUR / "themes.webp", (1320, 824)),
        "diff.webp": (OUT_APP / "diff.webp", (1320, 824)),
        "palette.webp": (OUT_APP / "palette.webp", (1320, 824)),
        "plans.webp": (OUT_APP / "plans.webp", (1320, 824)),
        "question.webp": (OUT_APP / "question.webp", (1320, 824)),
        "switcher.webp": (OUT_TOUR / "pairs.webp", (1320, 824)),
        "sidebar.webp": (OUT_APP / "sidebar.webp", (588, 1236)),
    }
    for name, (src_file, target_size) in mapping.items():
        dst = RELEASE_SCREENSHOTS / name
        im = Image.open(src_file).convert('RGB')
        if target_size:
            im = im.resize(target_size, Image.Resampling.LANCZOS)
        im.save(dst, 'WEBP', quality=90, method=6)
        print(f"Synced {dst}")


def run():
    sanitize_window()
    sanitize_hero()
    sanitize_hydra()
    sanitize_diff()
    sanitize_palette()
    sanitize_queue()
    sanitize_quote()
    sanitize_slash()
    sanitize_slider()
    sanitize_sidebar()
    sanitize_threads()
    sanitize_notify()
    sanitize_themes()
    sanitize_intro()
    sanitize_panels()
    sanitize_pairs()
    sanitize_recipes()
    sanitize_question()
    sanitize_plans()
    sanitize_limits()
    
    generate_posters()
    update_xcassets()
    sync_release_screenshots()
    print("\nAll website images, tour assets, and screenshots sanitized successfully with authentic Hydra marks preserved!")


if __name__ == "__main__":
    run()
