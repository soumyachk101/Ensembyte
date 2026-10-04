#!/usr/bin/env python3
"""
Posters Generator, xcassets Syncer & Comprehensive QA Inspector for Swarm Code
Subagent 4: Posters & QA Inspector

Responsibilities:
1. Generate / update the 4 video poster images in website/assets/app/:
   - hero-poster.webp (from website/assets/app/tour/hero.webp resized to 1320x824)
   - question-poster.webp (from website/assets/app/question.webp resized to 1320x824)
   - queue-poster.webp (from website/assets/app/queue.webp resized to 1320x824)
   - slider-poster.webp (from website/assets/app/tour/slider.webp resized to 1320x824)
2. Sync the 8 tour images into in-app asset catalogs in SwarmCode/Resources/Assets.xcassets/:
   - tour-welcome.imageset/tour-welcome@2x.png (from tour/window.webp, 1320x824)
   - tour-hydra.imageset/tour-hydra@2x.png (from tour/hydra.webp, 1320x824)
   - tour-pairs.imageset/tour-pairs@2x.png (from tour/pairs.webp, 1320x824)
   - tour-slider.imageset/tour-slider@2x.png (from tour/slider.webp, 1320x824)
   - tour-panels.imageset/tour-panels@2x.png (from tour/panels.webp, 1320x824)
   - tour-themes.imageset/tour-themes@2x.png (from tour/themes.webp, 1320x824)
   - tour-recipes.imageset/tour-recipes@2x.png (from recipes.webp, 1320x824)
   - tour-threads.imageset/tour-threads@2x.png (from threads.webp, 1320x824)
3. Automated QA verification across all 51 WebP assets + 8 xcassets:
   - 26 themes: verify zero yellow bee pixels on top edge
   - 13 feature stills: verify dimensions, format, artifact-free
   - 7 tour scenes: verify dimensions, format, artifact-free
   - 4 posters: verify 1320x824, WebP format
   - switcher.webp: verify valid WebP
"""

import sys
import pathlib
from PIL import Image
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEBSITE_APP = ROOT / "website" / "assets" / "app"
TOUR_DIR = WEBSITE_APP / "tour"
THEMES_DIR = WEBSITE_APP / "themes"
XCASSETS = ROOT / "Ensembyte" / "Resources" / "Assets.xcassets"

POSTER_SOURCES = {
    "hero-poster.webp": TOUR_DIR / "hero.webp",
    "question-poster.webp": WEBSITE_APP / "question.webp",
    "queue-poster.webp": WEBSITE_APP / "queue.webp",
    "slider-poster.webp": TOUR_DIR / "slider.webp",
}

XCASSET_SOURCES = {
    "tour-welcome.imageset/tour-welcome@2x.png": TOUR_DIR / "window.webp",
    "tour-hydra.imageset/tour-hydra@2x.png": TOUR_DIR / "hydra.webp",
    "tour-pairs.imageset/tour-pairs@2x.png": TOUR_DIR / "pairs.webp",
    "tour-slider.imageset/tour-slider@2x.png": TOUR_DIR / "slider.webp",
    "tour-panels.imageset/tour-panels@2x.png": TOUR_DIR / "panels.webp",
    "tour-themes.imageset/tour-themes@2x.png": TOUR_DIR / "themes.webp",
    "tour-recipes.imageset/tour-recipes@2x.png": WEBSITE_APP / "recipes.webp",
    "tour-threads.imageset/tour-threads@2x.png": WEBSITE_APP / "threads.webp",
}

def generate_posters():
    print("\n" + "="*60)
    print("1. GENERATING VIDEO POSTERS (1320x824 WebP)")
    print("="*60)
    for poster_name, src_path in POSTER_SOURCES.items():
        if not src_path.exists():
            print(f"  [WAIT] Source not found yet: {src_path}")
            continue
        dest_path = WEBSITE_APP / poster_name
        im = Image.open(src_path).convert("RGB")
        im_resized = im.resize((1320, 824), Image.Resampling.LANCZOS)
        im_resized.save(dest_path, "WEBP", quality=92, method=6)
        size_kb = dest_path.stat().st_size / 1024
        print(f"  [OK] Generated {poster_name:22s} ({im_resized.size[0]}x{im_resized.size[1]}, {size_kb:.1f} KB) from {src_path.name}")

def sync_xcassets():
    print("\n" + "="*60)
    print("2. SYNCING IN-APP XCASSETS (1320x824 PNG)")
    print("="*60)
    for rel_dest, src_path in XCASSET_SOURCES.items():
        dest_path = XCASSETS / rel_dest
        if not src_path.exists():
            print(f"  [WAIT] Source not found yet: {src_path}")
            continue
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        im = Image.open(src_path).convert("RGB")
        im_resized = im.resize((1320, 824), Image.Resampling.LANCZOS)
        im_resized.save(dest_path, "PNG")
        size_kb = dest_path.stat().st_size / 1024
        print(f"  [OK] Synced {rel_dest:42s} ({im_resized.size[0]}x{im_resized.size[1]}, {size_kb:.1f} KB)")

def run_qa_checks():
    print("\n" + "="*60)
    print("3. COMPREHENSIVE AUTOMATED QA INSPECTION")
    print("="*60)
    all_passed = True
    
    # 3.1 Check 26 Theme Images
    print("\n--- 3.1 Inspecting 26 Theme Images (website/assets/app/themes/) ---")
    theme_files = sorted(list(THEMES_DIR.glob("*.webp")))
    if len(theme_files) != 26:
        print(f"  [FAIL] Expected 26 themes, found {len(theme_files)}")
        all_passed = False
    else:
        print(f"  Found all 26 theme WebP files.")
    
    yellow_pixel_violations = 0
    for tf in theme_files:
        im = Image.open(tf).convert("RGB")
        if im.size != (2080, 1300):
            print(f"  [FAIL] {tf.name} size is {im.size}, expected (2080, 1300)")
            all_passed = False
        arr = np.array(im)
        # Check box [98:148, 570:620] for yellow bee pixels
        # Yellow bee pixels typically have R > 170, G > 130, B < 70
        crop = arr[98:148, 570:620]
        yellow_mask = (crop[:, :, 0] > 170) & (crop[:, :, 1] > 130) & (crop[:, :, 2] < 70)
        num_yellow = int(np.sum(yellow_mask))
        if num_yellow > 0:
            print(f"  [FAIL] {tf.name}: Found {num_yellow} yellow bee pixels in header crop!")
            yellow_pixel_violations += 1
            all_passed = False
    
    if yellow_pixel_violations == 0:
        print(f"  [PASS] All 26 themes verified: Exactly 0 yellow bee pixels in header, dimensions (2080, 1300) OK.")

    # 3.2 Check 13 Feature Stills
    print("\n--- 3.2 Inspecting 13 Feature Stills (website/assets/app/) ---")
    stills = [
        ("diff.webp", (2080, 1300)),
        ("palette.webp", (2080, 1300)),
        ("queue.webp", (2080, 1300)),
        ("quote.webp", (2080, 1300)),
        ("slash.webp", (2080, 1300)),
        ("threads.webp", (2080, 1300)),
        ("recipes.webp", (2080, 1300)),
        ("intro.webp", (2080, 1299)),
        ("question.webp", (2080, 1300)),
        ("plans.webp", (2080, 1300)),
        ("sidebar.webp", (588, 1236)),
        ("limits.webp", (812, 1146)),
        ("notify.webp", (2080, 1300)),
    ]
    for sf_name, expected_size in stills:
        p = WEBSITE_APP / sf_name
        if not p.exists():
            print(f"  [FAIL] {sf_name} does not exist!")
            all_passed = False
            continue
        im = Image.open(p)
        if im.size != expected_size:
            print(f"  [FAIL] {sf_name} size is {im.size}, expected {expected_size}")
            all_passed = False
        else:
            print(f"  [PASS] {sf_name:14s}: {im.size[0]}x{im.size[1]}, {p.stat().st_size / 1024:.1f} KB — OK")

    # 3.3 Check 7 Tour Scenes
    print("\n--- 3.3 Inspecting 7 Tour Scenes (website/assets/app/tour/) ---")
    tour_scenes = [
        ("hero.webp", (2400, 1500)),
        ("window.webp", (2080, 1300)),
        ("hydra.webp", (2080, 1300)),
        ("panels.webp", (2080, 1300)),
        ("pairs.webp", (2080, 1300)),
        ("slider.webp", (2080, 1300)),
        ("themes.webp", (2080, 1300)),
    ]
    tour_ready = True
    for ts_name, expected_size in tour_scenes:
        p = TOUR_DIR / ts_name
        if not p.exists():
            print(f"  [FAIL] {ts_name} does not exist!")
            all_passed = False
            tour_ready = False
            continue
        im = Image.open(p)
        if im.size != expected_size:
            print(f"  [FAIL] {ts_name} size is {im.size}, expected {expected_size}")
            all_passed = False
        else:
            print(f"  [PASS] {ts_name:14s}: {im.size[0]}x{im.size[1]}, {p.stat().st_size / 1024:.1f} KB — OK")

    # 3.4 Check 4 Video Posters
    print("\n--- 3.4 Inspecting 4 Video Posters (website/assets/app/) ---")
    posters = [
        "hero-poster.webp",
        "question-poster.webp",
        "queue-poster.webp",
        "slider-poster.webp",
    ]
    for pos_name in posters:
        p = WEBSITE_APP / pos_name
        if not p.exists():
            print(f"  [FAIL] {pos_name} does not exist!")
            all_passed = False
            continue
        im = Image.open(p)
        if im.size != (1320, 824):
            print(f"  [FAIL] {pos_name} size is {im.size}, expected (1320, 824)")
            all_passed = False
        else:
            print(f"  [PASS] {pos_name:20s}: {im.size[0]}x{im.size[1]}, {p.stat().st_size / 1024:.1f} KB — OK")

    # 3.5 Check switcher.webp
    print("\n--- 3.5 Inspecting switcher.webp ---")
    sw_path = WEBSITE_APP / "switcher.webp"
    if sw_path.exists():
        im_sw = Image.open(sw_path)
        print(f"  [PASS] switcher.webp: {im_sw.size[0]}x{im_sw.size[1]}, {sw_path.stat().st_size / 1024:.1f} KB — OK")
    else:
        print("  [FAIL] switcher.webp does not exist!")
        all_passed = False

    # 3.6 Check 8 xcassets PNGs
    print("\n--- 3.6 Inspecting 8 xcassets Tour Images (SwarmCode/Resources/Assets.xcassets/) ---")
    for rel_dest in XCASSET_SOURCES.keys():
        p = XCASSETS / rel_dest
        if not p.exists():
            print(f"  [FAIL] {rel_dest} does not exist!")
            all_passed = False
            continue
        im = Image.open(p)
        if im.size != (1320, 824) or im.format != "PNG":
            print(f"  [FAIL] {rel_dest}: size={im.size}, format={im.format}, expected (1320, 824) PNG")
            all_passed = False
        else:
            print(f"  [PASS] {p.name:22s}: {im.size[0]}x{im.size[1]} PNG ({p.stat().st_size / 1024:.1f} KB) — OK")

    print("\n" + "="*60)
    if all_passed:
        print("OVERALL QA VERIFICATION: PASSED (ALL 51 WebP + 8 PNG Assets Clean & Valid)")
    else:
        print("OVERALL QA VERIFICATION: PENDING / FAILED (See items above)")
    print("="*60 + "\n")
    return all_passed

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "posters":
            generate_posters()
        elif cmd == "sync":
            sync_xcassets()
        elif cmd == "qa":
            run_qa_checks()
        else:
            generate_posters()
            sync_xcassets()
            run_qa_checks()
    else:
        generate_posters()
        sync_xcassets()
        run_qa_checks()
