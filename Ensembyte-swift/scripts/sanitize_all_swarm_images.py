#!/usr/bin/env python3
"""
Senior Developer Production Image Sanitizer for Ensembyte:
1. Surgically replaces all residual raster pixel text of:
   - "Swarm Code" / "SwarmCode" / "Swarm" -> "Ensembyte"
   - "swarmcode.dev" -> "ensembyte.app"
   - "DroppyCode build" / "SwarmCode build" -> "Ensembyte build"
   - "Welcome to Swarm Code" -> "Welcome to Ensembyte"
   - "What should we build in Swarm Code?" -> "What should we build in Ensembyte?"
   - "SwarmCode/App/Views/Composer/ComposerView.swift" -> "Ensembyte/App/Views/Composer/ComposerView.swift"
2. Fixes all 26 theme preview captures in website/assets/app/themes/*.webp.
3. Fixes open graph banner website/assets/og/og-home.png.
4. Preserves authentic Hydra features, marks, cards, and head glyphs.
5. Regenerates video posters (1320x824 WebP).
6. Syncs in-app xcassets tour imagesets (1320x824 PNG).
7. Syncs release screenshots into Ensembyte-Release/assets/screenshots/.
8. Updates release architecture, data-flow, and hydra SVG diagrams.
"""

import os
import pathlib
from PIL import Image, ImageDraw, ImageFont
import numpy as np

WORKSPACE_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SWIFT_ROOT = WORKSPACE_ROOT / "Ensembyte-swift"
WEBSITE_ROOT = WORKSPACE_ROOT / "website"

APP_DIR = WEBSITE_ROOT / "assets" / "app"
TOUR_DIR = APP_DIR / "tour"
THEMES_DIR = APP_DIR / "themes"
OG_PATH = WEBSITE_ROOT / "assets" / "og" / "og-home.png"

XCASSETS = SWIFT_ROOT / "Ensembyte" / "Resources" / "Assets.xcassets"
RELEASE_SCREENSHOTS = SWIFT_ROOT / "Ensembyte-Release" / "assets" / "screenshots"
RELEASE_DIAGRAMS = SWIFT_ROOT / "Ensembyte-Release" / "assets" / "diagrams"

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
MONO_FONT_PATH = "/System/Library/Fonts/SFNSMono.ttf"


def inpaint_v(arr, x0, x1, y0, y1):
    """Linear vertical interpolation between y0-1 and y1 across [x0, x1]."""
    x0 = max(0, int(x0))
    x1 = min(arr.shape[1], int(x1))
    y0 = max(1, int(y0))
    y1 = min(arr.shape[0] - 2, int(y1))
    H = y1 - y0 + 1
    if H <= 0 or x1 <= x0:
        return
    top = arr[y0 - 1, x0:x1]
    bot = arr[y1 + 1, x0:x1]
    for i in range(H):
        alpha = i / float(H - 1) if H > 1 else 0.5
        arr[y0 + i, x0:x1] = (1.0 - alpha) * top + alpha * bot


def inpaint_h(arr, x0, x1, y0, y1):
    """Linear horizontal interpolation between x0-1 and x1 across [y0, y1]."""
    x0 = max(1, int(x0))
    x1 = min(arr.shape[1] - 2, int(x1))
    y0 = max(0, int(y0))
    y1 = min(arr.shape[0], int(y1))
    W = x1 - x0 + 1
    if W <= 0 or y1 <= y0:
        return
    left = arr[y0:y1, x0 - 1]
    right = arr[y0:y1, x1 + 1]
    for i in range(W):
        alpha = i / float(W - 1) if W > 1 else 0.5
        arr[y0:y1, x0 + i] = (1.0 - alpha) * left + alpha * right


# ----------------------------------------------------------------------
# 1. Tour Assets
# ----------------------------------------------------------------------

def sanitize_window():
    print("Sanitizing tour/window.webp...")
    p = TOUR_DIR / "window.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    # 1. Terminal line: 'SwarmCode build' -> 'Ensembyte build'
    inpaint_v(arr, 835, 985, 696, 720)

    # 2. Modal title: 'Welcome to Swarm Code' -> 'Welcome to Ensembyte'
    inpaint_v(arr, 720, 1360, 895, 965)

    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)

    # Draw terminal text
    font_term = ImageFont.truetype(FONT_PATH, 14)
    font_term.set_variation_by_name('Medium')
    d.text((836, 700), "Ensembyte build", fill=(150, 160, 172, 255), font=font_term)

    # Draw unified centered modal title
    font_modal = ImageFont.truetype(FONT_PATH, 46)
    font_modal.set_variation_by_name('Bold')
    title_text = "Welcome to Ensembyte"
    bbox = font_modal.getbbox(title_text)
    tw = bbox[2] - bbox[0]
    tx = 1040 - tw // 2
    d.text((tx, 908), title_text, fill=(245, 248, 252, 255), font=font_modal)

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


def sanitize_slider():
    print("Sanitizing tour/slider.webp and app/slider.webp...")
    p = TOUR_DIR / "slider.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    # Inpaint text line
    inpaint_h(arr, 610, 1471, 645, 725)
    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)

    font = ImageFont.truetype(FONT_PATH, 56)
    font.set_variation_by_name('Regular')

    t1 = 'What should we build in '
    t2 = 'Ensembyte'
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

    text_color = (235, 240, 245, 255)
    sub_color = (160, 175, 190, 255)

    d.text((start_x, y_text), t1, fill=text_color, font=font)
    x2 = start_x + w1
    d.text((x2, y_text), t2, fill=text_color, font=font)
    x3 = x2 + w2
    d.text((x3, y_text), t3, fill=text_color, font=font)

    # Draw dotted/dashed underline under Ensembyte
    cur_x = x2 + 2
    underline_y = 717
    end_underline = x2 + w2 - 2
    while cur_x < end_underline:
        d.line([(cur_x, underline_y), (min(cur_x + 8, end_underline), underline_y)], fill=sub_color, width=3)
        cur_x += 14

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    im_out.convert('RGB').save(APP_DIR / "slider.webp", 'WEBP', quality=95, method=6)
    print(f"  Updated {p} and app/slider.webp")


def sanitize_pairs():
    print("Sanitizing tour/pairs.webp...")
    p = TOUR_DIR / "pairs.webp"
    orig_im = Image.open(p).convert('RGBA')
    arr = np.array(orig_im, dtype=np.float32)

    # Inpaint text line horizontally before popover shadow at x=1244
    inpaint_h(arr, 625, 1243, 648, 722)
    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)

    font = ImageFont.truetype(FONT_PATH, 35)
    font.set_variation_by_name('Regular')

    t1 = 'What should we build in '
    t2 = 'Ensembyte'
    bbox1 = font.getbbox(t1)
    w1 = bbox1[2] - bbox1[0]
    bbox2 = font.getbbox(t2)
    w2 = bbox2[2] - bbox2[0]

    sx = 633
    sy = 664
    d.text((sx, sy), t1, fill=(240, 246, 252, 255), font=font)
    x2 = sx + w1
    d.text((x2, sy), t2, fill=(240, 246, 252, 255), font=font)

    # Dotted underline under Ensembyte
    cur_x = x2 + 2
    end_underline = x2 + w2 - 2
    while cur_x < end_underline:
        d.line([(cur_x, 708), (min(cur_x + 8, end_underline), 708)], fill=(150, 164, 172, 220), width=2)
        cur_x += 14

    # Keep Model Picker popover on the right (x >= 1244) 100% pristine
    res_arr = np.array(im_out)
    orig_arr = np.array(orig_im)
    res_arr[:, 1244:] = orig_arr[:, 1244:]

    final_im = Image.fromarray(res_arr)
    final_im.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


def sanitize_themes_tour():
    print("Sanitizing tour/themes.webp...")
    p = TOUR_DIR / "themes.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    panels = [
        (325, 455, 478, 500, (150, 160, 172, 255)),
        (1365, 1495, 478, 500, (150, 160, 172, 255)),
        (325, 455, 1128, 1150, (90, 95, 105, 255)),
        (1365, 1495, 1128, 1150, (150, 160, 172, 255)),
    ]

    for x0, x1, y0, y1, _ in panels:
        inpaint_v(arr, x0, x1, y0, y1)

    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)
    font = ImageFont.truetype(FONT_PATH, 11)
    font.set_variation_by_name('Regular')

    for x0, _, y0, _, color in panels:
        d.text((x0 + 2, y0 + 3), 'Ensembyte build', fill=color, font=font)

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


# ----------------------------------------------------------------------
# 2. Main App Assets
# ----------------------------------------------------------------------

def sanitize_diff():
    print("Sanitizing app/diff.webp...")
    p = APP_DIR / "diff.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    inpaint_v(arr, 638, 1150, 284, 314)
    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)

    font = ImageFont.truetype(FONT_PATH, 19)
    font.set_variation_by_name('Regular')
    d.text((640, 288), 'Ensembyte/App/Views/Composer/ComposerView.swift', fill=(215, 225, 235, 255), font=font)

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


def sanitize_sidebar():
    print("Sanitizing app/sidebar.webp...")
    p = APP_DIR / "sidebar.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    rows = [
        (299, 'Ensembyte'),
        (446, 'Ensembyte'),
        (546, 'ensembyte.app'),
        (644, 'Ensembyte'),
        (742, 'Ensembyte'),
        (840, 'Ensembyte'),
        (938, 'Ensembyte'),
    ]

    for y_top, _ in rows:
        inpaint_v(arr, 93, 265, y_top - 5, y_top + 28)

    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)
    font = ImageFont.truetype(FONT_PATH, 20)
    font.set_variation_by_name('Medium')
    color = (155, 170, 185, 255)

    for y_top, text in rows:
        d.text((99, y_top), text, fill=color, font=font)

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


def sanitize_palette():
    print("Sanitizing app/palette.webp...")
    p = APP_DIR / "palette.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    rows = [
        (368, 'Ensembyte'),
        (444, 'Ensembyte'),
        (516, 'ensembyte.app'),
        (592, 'Ensembyte'),
        (664, 'Ensembyte'),
        (740, 'Ensembyte'),
    ]

    for y_top, _ in rows:
        inpaint_v(arr, 645, 765, y_top - 4, y_top + 24)

    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)
    font = ImageFont.truetype(FONT_PATH, 16)
    font.set_variation_by_name('Regular')
    color = (145, 160, 180, 255)

    for y_top, text in rows:
        d.text((650, y_top), text, fill=color, font=font)

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


def sanitize_queue():
    print("Sanitizing app/queue.webp...")
    p = APP_DIR / "queue.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    inpaint_v(arr, 695, 860, 814, 838)
    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)

    font = ImageFont.truetype(FONT_PATH, 14)
    font.set_variation_by_name('Regular')
    d.text((698, 818), 'Ensembyte build', fill=(150, 160, 172, 255), font=font)

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


def sanitize_quote():
    print("Sanitizing app/quote.webp...")
    p = APP_DIR / "quote.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    inpaint_v(arr, 733, 890, 915, 938)
    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)

    font = ImageFont.truetype(FONT_PATH, 14)
    font.set_variation_by_name('Regular')
    d.text((736, 918), 'Ensembyte build', fill=(150, 160, 172, 255), font=font)

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


def sanitize_slash():
    print("Sanitizing app/slash.webp...")
    p = APP_DIR / "slash.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    inpaint_v(arr, 734, 890, 959, 983)
    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)

    font = ImageFont.truetype(FONT_PATH, 14)
    font.set_variation_by_name('Regular')
    d.text((737, 961), 'Ensembyte build', fill=(150, 160, 172, 255), font=font)

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


def sanitize_threads():
    print("Sanitizing app/threads.webp...")
    p = APP_DIR / "threads.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    rows = [
        (392, 'Ensembyte'),
        (516, 'Ensembyte'),
        (598, 'ensembyte.app'),
        (678, 'Ensembyte'),
        (764, 'Ensembyte'),
        (846, 'Ensembyte'),
        (928, 'Ensembyte'),
    ]
    for y_top, _ in rows:
        inpaint_v(arr, 273, 420, y_top - 4, y_top + 26)

    # Terminal line
    inpaint_v(arr, 708, 890, 834, 862)

    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)

    font_side = ImageFont.truetype(FONT_PATH, 16)
    font_side.set_variation_by_name('Regular')
    color_side = (145, 160, 180, 255)

    for y_top, text in rows:
        d.text((275, y_top), text, fill=color_side, font=font_side)

    font_term = ImageFont.truetype(FONT_PATH, 14)
    font_term.set_variation_by_name('Regular')
    d.text((711, 837), 'Ensembyte build', fill=(150, 160, 172, 255), font=font_term)

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


def sanitize_notify():
    print("Sanitizing app/notify.webp...")
    p = APP_DIR / "notify.webp"
    im = Image.open(p).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    rows = [
        (284, 'Ensembyte'),
        (398, 'Ensembyte'),
        (465, 'Ensembyte'),
        (568, 'Ensembyte'),
        (634, 'ensembyte.app'),
        (704, 'Ensembyte'),
        (770, 'Ensembyte'),
        (885, 'Ensembyte'),
        (951, 'ensembyte.app'),
        (1021, 'ensembyte.app'),
    ]
    for y_top, _ in rows:
        inpaint_v(arr, 203, 330, y_top - 4, y_top + 24)

    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)

    font = ImageFont.truetype(FONT_PATH, 14)
    font.set_variation_by_name('Regular')
    color = (145, 160, 180, 255)

    for y_top, text in rows:
        d.text((205, y_top), text, fill=color, font=font)

    im_out.convert('RGB').save(p, 'WEBP', quality=95, method=6)
    print(f"  Updated {p}")


def sanitize_switcher():
    print("Sanitizing app/switcher.webp (from tour/pairs.webp)...")
    im = Image.open(TOUR_DIR / "pairs.webp").convert('RGB')
    im_resized = im.resize((1320, 824), Image.Resampling.LANCZOS)
    im_resized.save(APP_DIR / "switcher.webp", 'WEBP', quality=92, method=6)
    print("  Updated app/switcher.webp")


# ----------------------------------------------------------------------
# 3. All 26 Theme Screenshots
# ----------------------------------------------------------------------

def sanitize_themes_all():
    print("Sanitizing all 26 themes in website/assets/app/themes/...")
    theme_files = sorted(THEMES_DIR.glob("*.webp"))
    font_mono = ImageFont.truetype(MONO_FONT_PATH, 14)
    font_term = ImageFont.truetype(FONT_PATH, 15)
    font_term.set_variation_by_name('Medium')

    for tp in theme_files:
        im = Image.open(tp).convert('RGBA')
        arr = np.array(im, dtype=np.float32)
        im_raw = np.array(im)

        # Check if SwarmCode is present in status bar (x=780..875, y=676..694)
        sw_region = im_raw[678:693, 785:865, :3]
        sw_std = np.std(sw_region, axis=(0, 2))
        has_swarm = (np.max(sw_std) > 10.0) if len(sw_std) > 0 else False

        txt_color = None
        if has_swarm:
            crop_txt = im_raw[680:692, 785:865, :3]
            crop_bg = im_raw[674:676, 785:865, :3]
            bg_color = np.median(crop_bg, axis=(0, 1))
            diffs = np.linalg.norm(crop_txt - bg_color, axis=2)
            thresh = np.percentile(diffs, 95)
            txt_pixels = crop_txt[diffs >= thresh]
            txt_color = tuple(int(round(c)) for c in np.median(txt_pixels, axis=0)) + (255,)
            inpaint_v(arr, 780, 875, 676, 694)

        # Terminal line: DroppyCode/SwarmCode build (x=654..845, y=964..989)
        crop_term_txt = im_raw[968:984, 600:650, :3]
        crop_term_bg = im_raw[960:963, 600:650, :3]
        term_bg_color = np.median(crop_term_bg, axis=(0, 1))
        t_diffs = np.linalg.norm(crop_term_txt - term_bg_color, axis=2)
        t_thresh = np.percentile(t_diffs, 95)
        term_txt_pixels = crop_term_txt[t_diffs >= t_thresh]
        term_txt_color = tuple(int(round(c)) for c in np.median(term_txt_pixels, axis=0)) + (255,)

        inpaint_v(arr, 654, 845, 964, 989)

        im_out = Image.fromarray(arr.astype(np.uint8))
        draw = ImageDraw.Draw(im_out)

        if has_swarm and txt_color:
            draw.text((784, 678), 'Ensembyte', fill=txt_color, font=font_mono)

        draw.text((658, 968), 'Ensembyte build', fill=term_txt_color, font=font_term)
        im_out.convert('RGB').save(tp, 'WEBP', quality=95, method=6)
        print(f"  Sanitized theme: {tp.name}")


# ----------------------------------------------------------------------
# 4. Open Graph Image
# ----------------------------------------------------------------------

def sanitize_og():
    print("Sanitizing og-home.png...")
    im = Image.open(OG_PATH).convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    inpaint_v(arr, 673, 810, 515, 544)
    im_out = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(im_out)

    font = ImageFont.truetype(FONT_PATH, 21)
    font.set_variation_by_name('Medium')
    d.text((677, 519), "Ensembyte", fill=(235, 240, 245, 255), font=font)

    im_out.save(OG_PATH, 'PNG')
    print(f"  Updated {OG_PATH}")


# ----------------------------------------------------------------------
# 5. Video Posters
# ----------------------------------------------------------------------

def generate_posters():
    print("Generating video posters (1320x824 WebP)...")
    posters = {
        "hero-poster.webp": TOUR_DIR / "hero.webp",
        "slider-poster.webp": TOUR_DIR / "slider.webp",
        "question-poster.webp": APP_DIR / "question.webp",
        "queue-poster.webp": APP_DIR / "queue.webp",
    }
    for poster_name, src_path in posters.items():
        im = Image.open(src_path).convert('RGB')
        im_resized = im.resize((1320, 824), Image.Resampling.LANCZOS)
        out_path = APP_DIR / poster_name
        im_resized.save(out_path, 'WEBP', quality=92, method=6)
        print(f"  Saved poster {out_path.name}")


# ----------------------------------------------------------------------
# 6. xcassets Tour Images
# ----------------------------------------------------------------------

def update_xcassets():
    print("Updating in-app xcassets tour images (1320x824 PNG)...")
    tour_assets = {
        "tour-welcome.imageset/tour-welcome@2x.png": TOUR_DIR / "window.webp",
        "tour-hydra.imageset/tour-hydra@2x.png": TOUR_DIR / "hydra.webp",
        "tour-pairs.imageset/tour-pairs@2x.png": TOUR_DIR / "pairs.webp",
        "tour-slider.imageset/tour-slider@2x.png": TOUR_DIR / "slider.webp",
        "tour-panels.imageset/tour-panels@2x.png": TOUR_DIR / "panels.webp",
        "tour-themes.imageset/tour-themes@2x.png": TOUR_DIR / "themes.webp",
        "tour-recipes.imageset/tour-recipes@2x.png": APP_DIR / "recipes.webp",
        "tour-threads.imageset/tour-threads@2x.png": APP_DIR / "threads.webp",
    }
    for asset_rel, webp_src in tour_assets.items():
        target = XCASSETS / asset_rel
        target.parent.mkdir(parents=True, exist_ok=True)
        im = Image.open(webp_src).convert('RGB')
        im_resized = im.resize((1320, 824), Image.Resampling.LANCZOS)
        im_resized.save(target, 'PNG')
        print(f"  Updated xcassets: {target.parent.name}")


# ----------------------------------------------------------------------
# 7. Release Screenshots
# ----------------------------------------------------------------------

def sync_release_screenshots():
    print("Syncing release screenshots into Ensembyte-Release/assets/screenshots/...")
    RELEASE_SCREENSHOTS.mkdir(parents=True, exist_ok=True)
    mapping = {
        "hero.webp": (TOUR_DIR / "hero.webp", (1320, 824)),
        "hydra.webp": (TOUR_DIR / "hydra.webp", (1320, 824)),
        "hydra-delegation.webp": (TOUR_DIR / "hydra.webp", (1320, 824)),
        "agents.webp": (TOUR_DIR / "panels.webp", (1320, 824)),
        "themes.webp": (TOUR_DIR / "themes.webp", (1320, 824)),
        "diff.webp": (APP_DIR / "diff.webp", (1320, 824)),
        "palette.webp": (APP_DIR / "palette.webp", (1320, 824)),
        "plans.webp": (APP_DIR / "plans.webp", (1320, 824)),
        "question.webp": (APP_DIR / "question.webp", (1320, 824)),
        "queue.webp": (APP_DIR / "queue.webp", (1320, 824)),
        "recipes.webp": (APP_DIR / "recipes.webp", (1320, 824)),
        "switcher.webp": (TOUR_DIR / "pairs.webp", (1320, 824)),
        "sidebar.webp": (APP_DIR / "sidebar.webp", (588, 1236)),
    }
    for name, (src_file, target_size) in mapping.items():
        dst = RELEASE_SCREENSHOTS / name
        im = Image.open(src_file).convert('RGB')
        if target_size:
            im = im.resize(target_size, Image.Resampling.LANCZOS)
        im.save(dst, 'WEBP', quality=92, method=6)
        print(f"  Synced release screenshot: {name}")


# ----------------------------------------------------------------------
# 8. Diagrams
# ----------------------------------------------------------------------

def sanitize_diagrams():
    print("Sanitizing diagrams in Ensembyte-Release/assets/diagrams/...")
    arch_path = RELEASE_DIAGRAMS / "architecture.svg"
    if arch_path.exists():
        content = arch_path.read_text(encoding="utf-8")
        content = content.replace("SWARMCODE ARCHITECTURE", "ENSEMBYTE ARCHITECTURE")
        content = content.replace("SwarmCodeApp.swift", "EnsembyteApp.swift")
        arch_path.write_text(content, encoding="utf-8")
        print(f"  Updated {arch_path.name}")

    flow_path = RELEASE_DIAGRAMS / "data-flow.svg"
    if flow_path.exists():
        content = flow_path.read_text(encoding="utf-8")
        content = content.replace("Swarm-run heads", "Ensembyte-run heads")
        flow_path.write_text(content, encoding="utf-8")
        print(f"  Updated {flow_path.name}")

    hydra_path = RELEASE_DIAGRAMS / "hydra.svg"
    if hydra_path.exists():
        content = hydra_path.read_text(encoding="utf-8")
        content = content.replace(".swarm-code/hank/", ".ensembyte/hank/")
        content = content.replace(".swarm-code/walter/", ".ensembyte/walter/")
        content = content.replace(".swarm-code/ada/", ".ensembyte/ada/")
        hydra_path.write_text(content, encoding="utf-8")
        print(f"  Updated {hydra_path.name}")


def main():
    print("=== Starting Ensembyte Image Sanitization Pipeline ===")
    sanitize_window()
    sanitize_slider()
    sanitize_pairs()
    sanitize_themes_tour()

    sanitize_diff()
    sanitize_sidebar()
    sanitize_palette()
    sanitize_queue()
    sanitize_quote()
    sanitize_slash()
    sanitize_threads()
    sanitize_notify()
    sanitize_switcher()

    sanitize_themes_all()
    sanitize_og()

    generate_posters()
    update_xcassets()
    sync_release_screenshots()
    sanitize_diagrams()

    print("=== Sanitization Pipeline Complete! ===")


if __name__ == "__main__":
    main()
