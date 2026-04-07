#!/usr/bin/env python3
"""
OCR text from a CRT terminal video (YouTube Shorts: JJPA_iM8Hrs).

The video shows text being typed character-by-character on a CRT monitor
with a green phosphor bit font. This script:
  1. Downloads the video (or uses a local file / falls back to thumbnails)
  2. Extracts frames at key intervals
  3. Preprocesses for CRT bit-font readability (green channel isolation,
     thresholding, upscaling with nearest-neighbor to preserve pixel edges)
  4. Runs OCR with tesseract configured for monospace/raw character output
  5. Deduplicates across frames to produce the final transcript

Usage:
    python3 ocr_video.py [--video PATH] [--output PATH]

Dependencies (install via apt + pip):
    apt install tesseract-ocr ffmpeg
    pip install opencv-python-headless pytesseract Pillow numpy yt-dlp
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np
import pytesseract
from PIL import Image


VIDEO_URL = "https://youtube.com/shorts/JJPA_iM8Hrs"
VIDEO_ID = "JJPA_iM8Hrs"
THUMB_URL = f"https://i.ytimg.com/vi/{VIDEO_ID}/maxresdefault.jpg"

# Region of interest for the CRT screen (proportional to frame size).
# These are approximate ratios for the center CRT monitor in the video.
# Format: (x_start, y_start, x_end, y_end) as fractions of width/height.
# Tighter ROI that excludes CRT bezel and reflections
CRT_ROI_FRAC = (0.402, 0.361, 0.594, 0.535)


def download_video(dest: Path) -> bool:
    """Attempt to download the video using yt-dlp."""
    try:
        cmd = [
            "yt-dlp",
            "--no-check-certificates",
            "--extractor-args", "youtube:player_client=web,default",
            "--remote-components", "ejs:github",
            "-f", "best[height<=720]",
            "-o", str(dest),
            VIDEO_URL,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        return dest.exists() and dest.stat().st_size > 1000
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def download_thumbnail(dest: Path) -> bool:
    """Download the highest-resolution YouTube thumbnail as fallback."""
    try:
        import requests
        for quality in ["maxresdefault", "sddefault", "hqdefault"]:
            url = f"https://i.ytimg.com/vi/{VIDEO_ID}/{quality}.jpg"
            resp = requests.get(url, verify=False, timeout=15)
            if resp.status_code == 200 and len(resp.content) > 5000:
                dest.write_bytes(resp.content)
                return True
    except Exception:
        pass
    return False


def extract_frames(video_path: Path, output_dir: Path, fps: float = 2.0) -> list[Path]:
    """Extract frames from the video at the given FPS."""
    output_dir.mkdir(parents=True, exist_ok=True)
    pattern = str(output_dir / "frame_%04d.png")
    cmd = [
        "ffmpeg", "-i", str(video_path),
        "-vf", f"fps={fps}",
        "-q:v", "1",
        pattern,
        "-y",
    ]
    subprocess.run(cmd, capture_output=True, timeout=60)
    frames = sorted(output_dir.glob("frame_*.png"))
    return frames


def crop_crt_region(image: np.ndarray) -> np.ndarray:
    """Crop to the CRT screen region of the frame."""
    h, w = image.shape[:2]
    x1 = int(w * CRT_ROI_FRAC[0])
    y1 = int(h * CRT_ROI_FRAC[1])
    x2 = int(w * CRT_ROI_FRAC[2])
    y2 = int(h * CRT_ROI_FRAC[3])
    return image[y1:y2, x1:x2]


def preprocess_crt(image: np.ndarray) -> np.ndarray:
    """
    Preprocess a CRT screen crop for OCR.

    CRT bit fonts have sharp pixel edges on a dark background with green
    phosphor glow. The CRT has uneven illumination (brighter in center,
    darker at edges, with possible glare). We:
      1. Extract the green channel (strongest signal on green phosphor CRT)
      2. Use CLAHE for local contrast normalization (handles uneven glow)
      3. Apply adaptive thresholding to handle CRT illumination gradients
      4. Upscale 4x with nearest-neighbor to preserve pixel font edges
      5. Apply morphological cleanup to remove noise and connect strokes
    """
    # If color, extract green channel (CRT phosphor)
    if len(image.shape) == 3:
        green = image[:, :, 1]  # BGR -> G channel
    else:
        green = image

    # CLAHE with small tile size for good local contrast on CRT
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(4, 4))
    enhanced = clahe.apply(green)

    # Adaptive threshold handles the uneven CRT illumination much better
    # than global Otsu - the CRT center is brighter than the edges
    binary = cv2.adaptiveThreshold(
        enhanced, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY, blockSize=21, C=-8
    )

    # Remove small noise blobs (CRT phosphor noise)
    kernel_small = np.ones((2, 2), np.uint8)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel_small)

    # Upscale 6x with nearest-neighbor to preserve pixel font edges
    h, w = binary.shape
    upscaled = cv2.resize(binary, (w * 6, h * 6), interpolation=cv2.INTER_NEAREST)

    # Smooth the blocky pixel-font edges so tesseract sees them as
    # normal glyph strokes rather than disconnected pixel blocks.
    # A Gaussian blur followed by re-threshold achieves this.
    smoothed = cv2.GaussianBlur(upscaled, (5, 5), 1.0)
    _, cleaned = cv2.threshold(smoothed, 128, 255, cv2.THRESH_BINARY)

    return cleaned


def ocr_frame(image: np.ndarray) -> str:
    """
    Run tesseract OCR on a preprocessed CRT image.

    Tries multiple page segmentation modes and picks the result with
    the most printable ASCII characters (since the CRT text is all ASCII).
    """
    # Invert: tesseract expects black text on white background
    inverted = cv2.bitwise_not(image)

    best_text = ""
    best_score = -1

    for psm in [6, 4, 3]:
        config = f"--psm {psm}"
        try:
            text = pytesseract.image_to_string(inverted, config=config).strip()
        except Exception:
            continue

        # Score: count printable ASCII chars (our text is all ASCII)
        score = sum(1 for c in text if 32 <= ord(c) < 127)
        if score > best_score:
            best_score = score
            best_text = text

    return best_text


def deduplicate_lines(all_texts: list[str]) -> list[str]:
    """
    Merge OCR results from multiple frames.

    Since text appears progressively (typed character by character),
    later frames contain all text from earlier frames plus new text.
    We take the longest/most complete version of each line.
    """
    # Collect all unique lines across all frames
    all_lines = []
    for text in all_texts:
        for line in text.split("\n"):
            line = line.strip()
            if line:
                all_lines.append(line)

    if not all_lines:
        return []

    # Group similar lines and pick the longest/most common version
    final_lines = []
    used = set()

    for i, line in enumerate(all_lines):
        if i in used:
            continue
        # Find all similar lines
        group = [line]
        for j, other in enumerate(all_lines):
            if j <= i or j in used:
                continue
            # Lines are "similar" if one is a prefix/substring of the other
            # or they share >70% of characters
            if (line in other or other in line or
                    _similarity(line, other) > 0.7):
                group.append(other)
                used.add(j)
        used.add(i)
        # Pick the longest version from the group
        best = max(group, key=len)
        final_lines.append(best)

    return final_lines


def _similarity(a: str, b: str) -> float:
    """Simple character-level Jaccard similarity."""
    if not a or not b:
        return 0.0
    set_a = set(enumerate(a))
    set_b = set(enumerate(b))
    intersection = len(set_a & set_b)
    union = len(set_a | set_b)
    return intersection / union if union else 0.0


def process_video(video_path: Path) -> str:
    """Full pipeline: extract frames -> crop -> preprocess -> OCR -> merge."""
    with tempfile.TemporaryDirectory() as tmpdir:
        frames_dir = Path(tmpdir) / "frames"
        # Extract at 2 fps for a 12-second video = ~24 frames
        frames = extract_frames(video_path, frames_dir, fps=2.0)
        print(f"Extracted {len(frames)} frames")

        all_texts = []
        debug_dir = video_path.parent / "debug_frames"
        debug_dir.mkdir(exist_ok=True)

        for i, frame_path in enumerate(frames):
            img = cv2.imread(str(frame_path))
            if img is None:
                continue

            cropped = crop_crt_region(img)
            processed = preprocess_crt(cropped)

            # Save debug images for inspection
            cv2.imwrite(str(debug_dir / f"processed_{i:03d}.png"), processed)

            text = ocr_frame(processed)
            if text:
                all_texts.append(text)
                print(f"  Frame {i:3d}: {text[:60]}...")

        final_lines = deduplicate_lines(all_texts)
        return "\n".join(final_lines)


def process_thumbnail(thumb_path: Path) -> str:
    """Process a single thumbnail image (fallback when video unavailable)."""
    img = cv2.imread(str(thumb_path))
    if img is None:
        sys.exit(f"Cannot read image: {thumb_path}")

    cropped = crop_crt_region(img)
    processed = preprocess_crt(cropped)

    # Save debug image
    debug_path = thumb_path.parent / "debug_thumbnail.png"
    cv2.imwrite(str(debug_path), processed)
    print(f"Saved preprocessed debug image: {debug_path}")

    text = ocr_frame(processed)
    return text


def main():
    parser = argparse.ArgumentParser(description="OCR CRT terminal text from video")
    parser.add_argument("--video", type=Path, help="Path to local video file")
    parser.add_argument("--thumbnail", type=Path, help="Path to thumbnail image")
    parser.add_argument("--output", type=Path, default=None, help="Output text file")
    args = parser.parse_args()

    script_dir = Path(__file__).parent
    result = ""

    if args.video and args.video.exists():
        print(f"Processing video: {args.video}")
        result = process_video(args.video)
    elif args.thumbnail and args.thumbnail.exists():
        print(f"Processing thumbnail: {args.thumbnail}")
        result = process_thumbnail(args.thumbnail)
    else:
        # Try to download video first, fall back to thumbnail
        video_path = script_dir / "video.mp4"
        thumb_path = script_dir / "thumb_maxresdefault.jpg"

        if video_path.exists():
            print(f"Using existing video: {video_path}")
            result = process_video(video_path)
        else:
            print("Attempting to download video...")
            if download_video(video_path):
                print(f"Downloaded video: {video_path}")
                result = process_video(video_path)
            else:
                print("Video download failed, trying thumbnail...")
                if not thumb_path.exists():
                    if not download_thumbnail(thumb_path):
                        sys.exit(
                            "Could not download video or thumbnail.\n"
                            "Please provide --video or --thumbnail manually."
                        )
                print(f"Using thumbnail: {thumb_path}")
                result = process_thumbnail(thumb_path)

    print("\n" + "=" * 60)
    print("OCR RESULT:")
    print("=" * 60)
    print(result)
    print("=" * 60)

    output_path = args.output or script_dir / "ocr_result.txt"
    output_path.write_text(result + "\n")
    print(f"\nSaved to: {output_path}")


if __name__ == "__main__":
    main()
