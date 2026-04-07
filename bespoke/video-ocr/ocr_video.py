#!/usr/bin/env python3
"""
OCR text from a CRT terminal video (YouTube Shorts: JJPA_iM8Hrs).

The video shows text typed character-by-character on a CRT monitor with a
pixel bit font. As text fills the screen it scrolls up. This script:

  1. Extracts frames from the video
  2. Auto-detects the CRT screen region
  3. Selects key frames at different scroll positions for maximum coverage
  4. OCRs each key frame independently with CRT-optimized preprocessing
  5. Stitches OCR results by detecting overlapping lines between frames

Usage:
    python3 ocr_video.py [--video PATH] [--fps N] [--output PATH] [--debug]

Dependencies:
    apt install tesseract-ocr ffmpeg
    pip install opencv-python-headless pytesseract numpy
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np
import pytesseract


def extract_frames(video_path: Path, output_dir: Path, fps: float) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    pattern = str(output_dir / "frame_%04d.png")
    subprocess.run(
        ["ffmpeg", "-i", str(video_path), "-vf", f"fps={fps}",
         "-q:v", "1", pattern, "-y"],
        capture_output=True, timeout=120,
    )
    return sorted(output_dir.glob("frame_*.png"))


def detect_crt_region(image: np.ndarray) -> tuple[int, int, int, int]:
    """Find the CRT screen area. Excludes right 15% (YouTube UI)."""
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
    h, w = gray.shape

    roi = gray[:, :int(w * 0.85)]
    # Low threshold to capture the full CRT including dimmer edges
    _, mask = cv2.threshold(roi, 15, 255, cv2.THRESH_BINARY)

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return (0, 0, w, h)

    largest = max(contours, key=cv2.contourArea)
    x, y, cw, ch = cv2.boundingRect(largest)

    mx, my = int(cw * 0.02), int(ch * 0.02)
    return (x + mx, y + my, x + cw - mx, y + ch - my)


def is_crt_text_frame(crop: np.ndarray) -> bool:
    """Check if a CRT crop contains text (not color bars, blank, or UI)."""
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY) if len(crop.shape) == 3 else crop

    if len(crop.shape) == 3:
        hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
        if np.mean(hsv[:, :, 1]) > 50:  # color bars have high saturation
            return False

    mean_val = np.mean(gray)
    std_val = np.std(gray)
    return 15 < mean_val < 180 and std_val > 25


def text_density(crop: np.ndarray) -> float:
    """Fraction of bright pixels in a binary CRT crop."""
    b = to_binary(crop)
    return np.mean(b > 128)


def to_binary(crop: np.ndarray) -> np.ndarray:
    """Convert CRT crop to binary."""
    gray = crop[:, :, 1] if len(crop.shape) == 3 else crop
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(4, 4))
    enhanced = clahe.apply(gray)
    binary = cv2.adaptiveThreshold(
        enhanced, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY, blockSize=21, C=-8,
    )
    kernel = np.ones((2, 2), np.uint8)
    return cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)


def preprocess_for_ocr(binary: np.ndarray) -> np.ndarray:
    """Upscale and smooth binary image for tesseract."""
    h, w = binary.shape
    upscaled = cv2.resize(binary, (w * 4, h * 4), interpolation=cv2.INTER_NEAREST)
    smoothed = cv2.GaussianBlur(upscaled, (5, 5), 1.0)
    _, cleaned = cv2.threshold(smoothed, 128, 255, cv2.THRESH_BINARY)
    return cleaned


def ocr_crop(crop: np.ndarray) -> str:
    """Full OCR pipeline on a color CRT crop."""
    binary = to_binary(crop)
    prepared = preprocess_for_ocr(binary)
    inverted = cv2.bitwise_not(prepared)

    best_text = ""
    best_score = -1
    for psm in [6, 4]:
        try:
            text = pytesseract.image_to_string(inverted, config=f"--psm {psm}").strip()
        except Exception:
            continue
        score = sum(1 for c in text if 32 <= ord(c) < 127)
        if score > best_score:
            best_score = score
            best_text = text

    return best_text


def top_line_fingerprint(crop: np.ndarray) -> np.ndarray:
    """Get a fingerprint of the top text line for scroll detection."""
    binary = to_binary(crop)
    h_proj = np.sum(binary > 128, axis=1)
    threshold = max(1, np.max(h_proj) * 0.05)

    # Find top text line
    start = None
    for i, v in enumerate(h_proj):
        if v > threshold and start is None:
            start = i
        elif v <= threshold and start is not None:
            if i - start > 3:
                # Return the row pattern of the first text line
                return binary[start:i, :].flatten()[:500]
            start = None

    return np.array([])


def select_key_frames(crops: list[np.ndarray], min_frames: int = 8) -> list[int]:
    """
    Select key frames that together cover all the text.

    Uses top-line fingerprint changes to detect scroll events, then
    ensures even spacing to cover the full video duration.
    """
    if len(crops) <= min_frames:
        return list(range(len(crops)))

    # Get fingerprint of top line for each frame
    fingerprints = [top_line_fingerprint(c) for c in crops]

    # Detect frames where the top line changes (scroll events)
    scroll_frames = [0]
    for i in range(1, len(crops)):
        fp_prev = fingerprints[scroll_frames[-1]]
        fp_curr = fingerprints[i]

        if len(fp_prev) == 0 or len(fp_curr) == 0:
            continue

        min_len = min(len(fp_prev), len(fp_curr))
        agreement = np.mean(fp_prev[:min_len] == fp_curr[:min_len])

        if agreement < 0.8:
            scroll_frames.append(i)

    # Always include the last text frame
    if scroll_frames[-1] != len(crops) - 1:
        scroll_frames.append(len(crops) - 1)

    # If fingerprint detection gave too few frames, add evenly-spaced ones
    if len(scroll_frames) < min_frames:
        step = len(crops) / min_frames
        even_frames = [int(i * step) for i in range(min_frames)]
        if even_frames[-1] != len(crops) - 1:
            even_frames[-1] = len(crops) - 1
        # Merge and deduplicate
        key_set = sorted(set(scroll_frames + even_frames))
        return key_set

    # If we have too many, subsample
    if len(scroll_frames) > min_frames * 2:
        step = len(scroll_frames) / min_frames
        scroll_frames = [scroll_frames[int(i * step)] for i in range(min_frames)]
        if scroll_frames[-1] != len(crops) - 1:
            scroll_frames[-1] = len(crops) - 1

    return scroll_frames


def stitch_ocr_texts(texts: list[str]) -> str:
    """
    Stitch OCR results from multiple frames by detecting overlapping lines.

    Each successive frame shows text that overlaps with the previous frame
    (the portion that hasn't scrolled off yet) plus new text at the bottom.
    We find the overlap and only keep new lines.
    """
    if not texts:
        return ""

    all_lines = [t.split("\n") for t in texts]

    # Start with lines from first frame
    result = [l.strip() for l in all_lines[0] if l.strip()]

    for frame_lines in all_lines[1:]:
        curr = [l.strip() for l in frame_lines if l.strip()]
        if not curr:
            continue

        # Find best overlap: last N lines of result match first N lines of curr
        best_overlap = 0
        for overlap in range(1, min(len(result), len(curr)) + 1):
            matches = 0
            for j in range(overlap):
                r_line = result[-(overlap - j)]
                c_line = curr[j]
                if _fuzzy_line_match(r_line, c_line):
                    matches += 1

            if matches >= max(1, overlap * 0.4):
                best_overlap = overlap

        # Append new lines after the overlap
        new_lines = curr[best_overlap:] if best_overlap > 0 else curr
        # Only add lines that don't duplicate the last few result lines
        for nl in new_lines:
            if not any(_fuzzy_line_match(nl, rl) for rl in result[-3:]):
                result.append(nl)

    return "\n".join(result)


def _fuzzy_line_match(a: str, b: str) -> bool:
    """Check if two OCR'd lines represent the same text."""
    if not a or not b:
        return False
    if a == b:
        return True

    # One is prefix of other (partial typing)
    shorter = min(len(a), len(b))
    if shorter >= 5 and (a[:shorter] == b[:shorter]):
        return True

    # Character agreement
    min_len = min(len(a), len(b))
    max_len = max(len(a), len(b))
    if min_len < 3:
        return False

    matches = sum(1 for i in range(min_len) if a[i] == b[i])
    return matches / max_len > 0.5


def process_video(video_path: Path, fps: float = 10.0, debug: bool = False) -> str:
    script_dir = video_path.parent

    with tempfile.TemporaryDirectory() as tmpdir:
        frames_dir = Path(tmpdir) / "frames"
        frames = extract_frames(video_path, frames_dir, fps=fps)
        print(f"Extracted {len(frames)} frames at {fps} fps")

        if not frames:
            sys.exit("No frames extracted. Is ffmpeg installed?")

        # Detect CRT region
        roi = None
        for fp in frames[1:min(15, len(frames))]:
            img = cv2.imread(str(fp))
            if img is None:
                continue
            candidate = detect_crt_region(img)
            if candidate[2] - candidate[0] > 100 and candidate[3] - candidate[1] > 100:
                roi = candidate
                break

        if roi is None:
            sys.exit("Could not detect CRT region")

        x1, y1, x2, y2 = roi
        print(f"CRT region: ({x1},{y1})-({x2},{y2}) = {x2-x1}x{y2-y1}")

        # Collect CRT text crops
        crops = []
        crop_indices = []
        for i, fp in enumerate(frames):
            img = cv2.imread(str(fp))
            if img is None:
                continue
            crop = img[y1:y2, x1:x2]
            if is_crt_text_frame(crop):
                crops.append(crop)
                crop_indices.append(i)
            elif crops:
                break  # stop after text ends

        print(f"Found {len(crops)} CRT text frames")

        # Select key frames for OCR
        key_indices = select_key_frames(crops)
        print(f"Selected {len(key_indices)} key frames: {[crop_indices[k] for k in key_indices]}")

        if debug:
            debug_dir = script_dir / "debug_frames"
            debug_dir.mkdir(exist_ok=True)

        # OCR each key frame
        ocr_texts = []
        for ki in key_indices:
            crop = crops[ki]
            text = ocr_crop(crop)

            if debug:
                binary = to_binary(crop)
                prepared = preprocess_for_ocr(binary)
                cv2.imwrite(str(debug_dir / f"key_{crop_indices[ki]:03d}.png"), prepared)

            lines = [l for l in text.split("\n") if l.strip()]
            print(f"  Frame {crop_indices[ki]:3d}: {len(lines)} lines")
            for l in lines[:3]:
                print(f"    {l[:60]}")
            if len(lines) > 3:
                print(f"    ...")

            ocr_texts.append(text)

        # Stitch
        print("\nStitching OCR results...")
        result = stitch_ocr_texts(ocr_texts)
        return result


def main():
    parser = argparse.ArgumentParser(description="OCR CRT terminal text from video")
    parser.add_argument("--video", type=Path, help="Path to video file")
    parser.add_argument("--fps", type=float, default=10.0,
                        help="Frame extraction rate (default: 10)")
    parser.add_argument("--output", type=Path, default=None, help="Output text file")
    parser.add_argument("--debug", action="store_true", help="Save debug images")
    args = parser.parse_args()

    script_dir = Path(__file__).parent
    video_path = args.video or script_dir / "video.mp4"

    if not video_path.exists():
        sys.exit(f"Video not found: {video_path}\nProvide --video or place video.mp4 here.")

    result = process_video(video_path, fps=args.fps, debug=args.debug)

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
