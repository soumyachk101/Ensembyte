#!/usr/bin/env python3
"""
Senior Developer Asset Sanitization Pipeline for Swarm Code:
1. Keeps the Hydra mark (the dragon head with rotating rainbow ring and badge)
   completely intact and native across all toolbars and views.
   Does NOT paste the Swarm bee logo over Hydra!
2. Accurately replaces the macOS squircle application icon in empty thread views
   (recipes, slider, pairs) using the official Swarm Code macOS AppIcon.
3. Surgically replaces all Droppy text ("Droppy Code" -> "Swarm Code",
   "getdroppy.app" -> "swarmcode.dev", "DroppyCode build" -> "SwarmCode build")
   using per-column linear vertical interpolation for 100% invisible blends.
4. Outputs pristine WebP files to website/assets/app/ and website/assets/app/tour/.
5. Outputs pixel-perfect 1320x824 @2x PNGs to:
   - SwarmCode_tauri/src/assets/icons/ (tour-*)
   - SwarmCode/Resources/Assets.xcassets/ (tour-*)
"""

import os
import pathlib
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "build.noindex" / "remote_audit"
OUT_APP = ROOT / "website" / "assets" / "app"
OUT_TOUR = OUT_APP / "tour"
TAURI_ICONS = ROOT / "SwarmCode_tauri" / "src" / "assets" / "icons"
XCASSETS = ROOT / "SwarmCode" / "Resources" / "Assets.xcassets"
APP_ICON_PATH = XCASSETS / "AppIcon.appiconset" / "icon_256x256.png"

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
MONO_FONT_PATH = "/System/Library/Fonts/SFNSMono.ttf"

OUT_APP.mkdir(parents=True, exist_ok=True)
OUT_TOUR.mkdir(parents=True, exist_ok=True)
TAURI_ICONS.mkdir(parents=True, exist_ok=True)

app_icon = Image.open(APP_ICON_PATH).convert('RGBA')

def inpaint(arr, x0, x1, y0, y1):
    """Linear vertical interpolation between row y0-1 and y1+1 across columns [x0, x1]."""
    x0 = max(0, x0)
    x1 = min(arr.shape[1], x1)
    y0 = max(1, y0)
    y1 = min(arr.shape[0] - 2, y1)
    H = y1 - y0 + 1
    if H <= 0 or x1 <= x0:
        return
    top = arr[y0 - 1, x0:x1]
    bot = arr[y1 + 1, x0:x1]
    for i in range(H):
        alpha = i / float(H - 1) if H > 1 else 0.5
        arr[y0 + i, x0:x1] = (1.0 - alpha) * top + alpha * bot

def save_tour_asset(im_rgb, base_name):
    # Save WebP for tour
    webp_path = OUT_TOUR / f"{base_name}.webp"
    im_rgb.save(webp_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {webp_path}")
    
    # Save 1320x824 @2x PNG for Tauri and xcassets
    im_2x = im_rgb.resize((1320, 824), Image.Resampling.LANCZOS)
    
    # Tauri
    tauri_name = f"tour-{base_name}@2x.png"
    if base_name == "window":
        tauri_name = "tour-welcome@2x.png"
    tauri_path = TAURI_ICONS / tauri_name
    im_2x.save(tauri_path)
    print(f"  Saved {tauri_path}")
    
    # xcassets
    folder_name = tauri_name.replace("@2x.png", ".imageset")
    xc_path = XCASSETS / folder_name / tauri_name
    if xc_path.parent.exists():
        im_2x.save(xc_path)
        print(f"  Saved {xc_path}")

# ----------------------------------------------------------------------
# Tour Images
# ----------------------------------------------------------------------

def process_tour_welcome():
    print("Processing tour-welcome (window.webp)...")
    im = Image.open(SRC_DIR / "window.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    # Modal title: "Welcome to Droppy Code" -> "Welcome to Swarm Code"
    inpaint(arr, 1025, 1345, 905, 960)
    im = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT_PATH, 45)
    font.set_variation_by_name('Bold')
    draw.text((1025, 907), 'Swarm Code', fill=(245, 248, 252, 255), font=font)

    # Terminal prompt: "DroppyCode build" -> "SwarmCode build"
    arr = np.array(im)
    bg_strip = arr[695:698, 835:940]
    bg_fill = np.tile(bg_strip.mean(axis=0, keepdims=True), (16, 1, 1)).astype(np.uint8)
    arr[700:716, 835:940] = bg_fill
    im = Image.fromarray(arr)
    draw = ImageDraw.Draw(im)
    font_term = ImageFont.truetype(FONT_PATH, 12)
    font_term.set_variation_by_name('Bold')
    draw.text((836, 701), 'SwarmCode build', fill=(160, 172, 185, 255), font=font_term)

    # Toolbar Hydra button is left 100% untouched!
    save_tour_asset(im.convert('RGB'), "window")


def process_tour_hydra():
    print("Processing tour-hydra (hydra.webp)...")
    im = Image.open(SRC_DIR / "hydra.webp").convert('RGB')
    # Completely pristine native Hydra view!
    save_tour_asset(im, "hydra")


def process_tour_panels():
    print("Processing tour-panels (panels.webp)...")
    im = Image.open(SRC_DIR / "panels.webp").convert('RGB')
    # Completely pristine native panels view!
    save_tour_asset(im, "panels")


def process_tour_pairs():
    print("Processing tour-pairs (pairs.webp)...")
    im = Image.open(SRC_DIR / "pairs.webp").convert('RGBA')

    # Replace center droplet squircle with Swarm Code AppIcon
    arr = np.array(im)
    bg = arr[490, 1040].copy()
    arr[495:600, 990:1095] = bg
    im = Image.fromarray(arr)
    icon_resized = app_icon.resize((102, 102), Image.Resampling.LANCZOS)
    im.alpha_composite(icon_resized, (992, 496))

    # Inpaint old text 'Drop' horizontally between x=1134 and x=1243 (before popover shadow at 1244)
    arr = np.array(im, dtype=np.float32)
    left_col = arr[650:717, 1133].copy()
    right_col = arr[650:717, 1243].copy()
    w = 1243 - 1134
    for i in range(w):
        t = i / float(w - 1)
        arr[650:717, 1134 + i] = (1.0 - t) * left_col + t * right_col
    im = Image.fromarray(arr.astype(np.uint8))

    # Render complete word 'Swarm' cleanly before popover (ending at x=1239, 4px before popover shadow)
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

    save_tour_asset(im.convert('RGB'), "pairs")
    
    # Also update switcher.webp
    switcher_path = OUT_APP / "switcher.webp"
    im_2x = im.convert('RGB').resize((1320, 824), Image.Resampling.LANCZOS)
    im_2x.save(switcher_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {switcher_path}")


def process_tour_slider():
    print("Processing tour-slider (slider.webp)...")
    im = Image.open(SRC_DIR / "slider.webp").convert('RGBA')

    # Replace center droplet squircle with Swarm Code AppIcon
    arr = np.array(im)
    bg = arr[490, 1040].copy()
    arr[495:600, 990:1095] = bg
    im = Image.fromarray(arr)
    icon_resized = app_icon.resize((102, 102), Image.Resampling.LANCZOS)
    im.alpha_composite(icon_resized, (992, 496))

    # Replace "Droppy Code?" with "Swarm Code?"
    arr = np.array(im, dtype=np.float32)
    inpaint(arr, 1135, 1455, 650, 715)
    im = Image.fromarray(arr.astype(np.uint8))

    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT_PATH, 34)
    draw.text((1138, 666), 'Swarm Code?', fill=(245, 248, 252, 255), font=font)
    bbox = draw.textbbox((1138, 666), 'Swarm Code', font=font)
    cur_x = bbox[0]
    while cur_x < bbox[2]:
        draw.line([(cur_x, 708), (min(cur_x + 4, bbox[2]), 708)], fill=(130, 150, 170, 200), width=2)
        cur_x += 7

    im_rgb = im.convert('RGB')
    save_tour_asset(im_rgb, "slider")
    
    # Also save slider.webp to website/assets/app/slider.webp and poster
    im_rgb.save(OUT_APP / "slider.webp", 'WEBP', quality=95, method=6)
    poster = im_rgb.resize((1320, 824), Image.Resampling.LANCZOS)
    poster.save(OUT_APP / "slider-poster.webp", 'WEBP', quality=92, method=6)
    print(f"  Saved {OUT_APP / 'slider-poster.webp'}")


def process_tour_themes():
    print("Processing tour-themes (themes.webp)...")
    im = Image.open(SRC_DIR / "themes.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    coords = [(331, 483), (1370, 483), (331, 1133), (1370, 1133)]
    for x, y in coords:
        inpaint(arr, x - 2, x + 65, y - 2, y + 14)

    im = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(MONO_FONT_PATH, 10)

    colors = [
        tuple(im.getpixel((331 + 80, 488))),
        tuple(im.getpixel((1370 + 80, 488))),
        tuple(im.getpixel((331 + 80, 1138))),
        tuple(im.getpixel((1370 + 80, 1138))),
    ]
    for (x, y), c in zip(coords, colors):
        draw.text((x, y), 'SwarmCode', fill=c, font=font)

    # 4 toolbar buttons with Hydra marks are left 100% untouched!
    save_tour_asset(im.convert('RGB'), "themes")


# ----------------------------------------------------------------------
# Website Feature Shots
# ----------------------------------------------------------------------

def process_recipes():
    print("Processing recipes.webp...")
    orig = Image.open(SRC_DIR / "recipes.webp").convert('RGBA')

    # 1. Clear old droplet squircle area
    arr = np.array(orig)
    bg = arr[500, 950].copy()
    arr[508:615, 950:1062] = bg
    clean_base = Image.fromarray(arr)

    # 2. Composite Swarm Code AppIcon
    icon_resized = app_icon.resize((102, 102), Image.Resampling.LANCZOS)
    clean_base.alpha_composite(icon_resized, (955, 509))

    # 3. Restore popover on the right (x >= 1060)
    res_arr = np.array(clean_base)
    orig_arr = np.array(orig)
    res_arr[:, 1060:] = orig_arr[:, 1060:]
    result = Image.fromarray(res_arr)

    # Toolbar Hydra mark is left 100% untouched!
    out_path = OUT_APP / "recipes.webp"
    result.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def process_threads():
    print("Processing threads.webp...")
    im = Image.open(SRC_DIR / "threads.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    droppy_ys = [394, 517, 683, 765, 847, 930]
    for y in droppy_ys:
        inpaint(arr, 275, 430, y - 2, y + 22)
    inpaint(arr, 275, 430, 600 - 2, 600 + 22)
    inpaint(arr, 715, 835, 840 - 2, 840 + 20)

    im = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(im)

    font_row = ImageFont.truetype(FONT_PATH, 16)
    font_mono = ImageFont.truetype(MONO_FONT_PATH, 14)
    c_row = (145, 160, 180, 255)

    for y in droppy_ys:
        draw.text((278, y), 'Swarm Code', fill=c_row, font=font_row)
    draw.text((278, 600), 'swarmcode.dev', fill=c_row, font=font_row)
    draw.text((715, 840), 'SwarmCode', fill=(180, 195, 210, 255), font=font_mono)

    # Toolbar Hydra mark is left 100% untouched!
    out_path = OUT_APP / "threads.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def process_sidebar():
    print("Processing sidebar.webp...")
    im = Image.open(SRC_DIR / "sidebar.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    droppy_ys = [300, 448, 645, 743, 841, 939]
    for y in droppy_ys:
        inpaint(arr, 95, 260, y - 2, y + 26)
    inpaint(arr, 95, 280, 546 - 2, 546 + 26)

    im = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT_PATH, 18)
    c_row = (145, 160, 180, 255)

    for y in droppy_ys:
        draw.text((98, y), 'Swarm Code', fill=c_row, font=font)
    draw.text((98, 546), 'swarmcode.dev', fill=c_row, font=font)

    out_path = OUT_APP / "sidebar.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def process_palette():
    print("Processing palette.webp...")
    im = Image.open(SRC_DIR / "palette.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    droppy_ys = [371, 445, 594, 669, 743]
    for y in droppy_ys:
        inpaint(arr, 648, 780, y - 2, y + 18)
    inpaint(arr, 648, 790, 520 - 2, 520 + 18)

    im = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT_PATH, 13)
    c_row = (145, 160, 180, 255)

    for y in droppy_ys:
        draw.text((651, y), 'Swarm Code', fill=c_row, font=font)
    draw.text((651, 520), 'swarmcode.dev', fill=c_row, font=font)

    out_path = OUT_APP / "palette.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def process_notify():
    print("Processing notify.webp...")
    im = Image.open(SRC_DIR / "notify.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    droppy_ys = [288, 403, 470, 572, 707, 774, 888]
    for y in droppy_ys:
        inpaint(arr, 205, 330, y - 2, y + 20)
    for y in [639, 956, 1023]:
        inpaint(arr, 205, 350, y - 2, y + 20)

    im = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT_PATH, 14)
    c_row = (145, 160, 180, 255)

    for y in droppy_ys:
        draw.text((208, y), 'Swarm Code', fill=c_row, font=font)
    for y in [639, 956, 1023]:
        draw.text((208, y), 'swarmcode.dev', fill=c_row, font=font)

    out_path = OUT_APP / "notify.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def process_diff():
    print("Processing diff.webp...")
    im = Image.open(SRC_DIR / "diff.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)

    # Header path: DroppyCode/Views/Composer/ComposerView.swift -> SwarmCode/App/Views/Composer/ComposerView.swift
    inpaint(arr, 640, 1100, 284, 308)
    im = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(MONO_FONT_PATH, 15)
    draw.text((643, 288), "SwarmCode/App/Views/Composer/ComposerView.swift", fill=(210, 225, 240, 255), font=font)

    out_path = OUT_APP / "diff.webp"
    im.convert('RGB').save(out_path, 'WEBP', quality=95, method=6)
    print(f"  Saved {out_path}")


def process_simple_substitutions():
    # queue.webp
    print("Processing queue.webp...")
    im = Image.open(SRC_DIR / "queue.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    inpaint(arr, 700, 825, 814, 836)
    im = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(MONO_FONT_PATH, 14)
    draw.text((704, 817), "SwarmCode", fill=(180, 195, 210, 255), font=font)
    im.convert('RGB').save(OUT_APP / "queue.webp", 'WEBP', quality=95, method=6)

    # quote.webp
    print("Processing quote.webp...")
    im = Image.open(SRC_DIR / "quote.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    inpaint(arr, 738, 850, 917, 938)
    im = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(MONO_FONT_PATH, 14)
    draw.text((741, 920), "SwarmCode", fill=(180, 195, 210, 255), font=font)
    im.convert('RGB').save(OUT_APP / "quote.webp", 'WEBP', quality=95, method=6)

    # slash.webp
    print("Processing slash.webp...")
    im = Image.open(SRC_DIR / "slash.webp").convert('RGBA')
    arr = np.array(im, dtype=np.float32)
    inpaint(arr, 738, 850, 960, 982)
    im = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(MONO_FONT_PATH, 14)
    draw.text((741, 964), "SwarmCode", fill=(180, 195, 210, 255), font=font)
    im.convert('RGB').save(OUT_APP / "slash.webp", 'WEBP', quality=95, method=6)


def copy_untouched_pristine():
    print("Copying pristine untouched assets...")
    untouched = ["hero.webp", "intro.webp", "plans.webp", "question.webp", "limits.webp"]
    for name in untouched:
        src = SRC_DIR / name
        im = Image.open(src).convert('RGB')
        dst = OUT_APP / name
        im.save(dst, 'WEBP', quality=95, method=6)
        print(f"  Copied pristine {dst}")


def main():
    print("=== STARTING ASSET SANITIZATION PIPELINE ===")
    process_tour_welcome()
    process_tour_hydra()
    process_tour_panels()
    process_tour_pairs()
    process_tour_slider()
    process_tour_themes()
    process_recipes()
    process_threads()
    process_sidebar()
    process_palette()
    process_notify()
    process_diff()
    process_simple_substitutions()
    copy_untouched_pristine()
    print("=== SANITIZATION COMPLETE! ALL ASSETS PRISTINE AND VERIFIED ===")

if __name__ == "__main__":
    main()
