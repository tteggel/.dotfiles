#!/usr/bin/env python3
"""
Independent verification of OCR results from the CRT video.

Uses a completely different approach from ocr_video.py:

  1. Extracts frames at a DIFFERENT fps offset (temporal diversity)
  2. Uses DIFFERENT preprocessing: luminance-based with Otsu + morphological
     refinement instead of green-channel + adaptive threshold
  3. OCRs each frame line-by-line (PSM 7/13) instead of full-block (PSM 6/4)
  4. Stitches with its own overlap detection
  5. Compares against the primary OCR result character-by-character

Both scripts should produce the same text if the OCR is correct.
Disagreements highlight characters that need manual review.

Usage:
    python3 verify_ocr.py [--video PATH] [--fps N] [--ocr-result PATH] [--ground-truth PATH]

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
    pattern = str(output_dir / "vframe_%04d.png")
    subprocess.run(
        ["ffmpeg", "-i", str(video_path), "-vf", f"fps={fps}", "-q:v", "1", pattern, "-y"],
        capture_output=True, timeout=120,
    )
    return sorted(output_dir.glob("vframe_*.png"))


def detect_crt_region(image: np.ndarray) -> tuple[int, int, int, int]:
    """Detect CRT screen region using edge detection (different from primary)."""
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image

    h_full, w_full = gray.shape
    roi_gray = gray[:, :int(w_full * 0.85)]

    # Threshold-based detection (same as primary, the CRT region is objective)
    _, mask = cv2.threshold(roi_gray, 15, 255, cv2.THRESH_BINARY)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return (0, 0, w_full, h_full)

    largest = max(contours, key=cv2.contourArea)
    x, y, w, h = cv2.boundingRect(largest)

    margin_x = int(w * 0.02)
    margin_y = int(h * 0.02)
    return (x + margin_x, y + margin_y, x + w - margin_x, y + h - margin_y)


def is_text_frame(image: np.ndarray, roi: tuple[int, int, int, int]) -> bool:
    x1, y1, x2, y2 = roi
    crop = image[y1:y2, x1:x2]
    if crop.size == 0:
        return False
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY) if len(crop.shape) == 3 else crop
    mean_val = np.mean(gray)
    std_val = np.std(gray)
    return 15 < mean_val < 180 and std_val > 25


def preprocess_v2(image: np.ndarray) -> np.ndarray:
    """
    DIFFERENT preprocessing from the primary script.

    Uses luminance (not green channel), Otsu threshold (not adaptive),
    and different upscale factor + smoothing parameters.
    """
    if len(image.shape) == 3:
        # Use luminance (weighted average) instead of just green channel
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image

    # CLAHE with DIFFERENT parameters than primary
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)

    # Otsu threshold (different from primary's adaptive threshold)
    _, binary = cv2.threshold(enhanced, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

    # Different morphological cleanup: close then open
    kernel = np.ones((2, 2), np.uint8)
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)

    # 5x upscale (different from primary's 4x)
    h, w = binary.shape
    upscaled = cv2.resize(binary, (w * 5, h * 5), interpolation=cv2.INTER_NEAREST)

    # Different smoothing: bilateral filter preserves edges better
    smoothed = cv2.GaussianBlur(upscaled, (3, 3), 0.8)
    _, cleaned = cv2.threshold(smoothed, 128, 255, cv2.THRESH_BINARY)

    return cleaned


def split_into_lines(binary: np.ndarray) -> list[np.ndarray]:
    """Split binary image into individual text line strips."""
    h_proj = np.sum(binary > 128, axis=1)
    if np.max(h_proj) == 0:
        return []

    threshold = np.max(h_proj) * 0.03
    in_text = h_proj > threshold

    rows = []
    start = None
    for i, active in enumerate(in_text):
        if active and start is None:
            start = i
        elif not active and start is not None:
            if i - start > 3:
                rows.append((max(0, start - 2), min(binary.shape[0], i + 2)))
            start = None
    if start is not None:
        rows.append((max(0, start - 2), binary.shape[0]))

    return [binary[y1:y2, :] for y1, y2 in rows]


def ocr_line(line_img: np.ndarray) -> str:
    """OCR a single line using PSM 7 (single text line mode)."""
    inverted = cv2.bitwise_not(line_img)
    best = ""
    best_score = -1

    for psm in [7, 13]:
        try:
            text = pytesseract.image_to_string(inverted, config=f"--psm {psm}").strip()
        except Exception:
            continue
        score = sum(1 for c in text if 32 <= ord(c) < 127)
        if score > best_score:
            best_score = score
            best = text

    return best


def ocr_frame_by_lines(image: np.ndarray) -> list[str]:
    """OCR a frame by splitting into lines and OCRing each independently."""
    processed = preprocess_v2(image)
    lines = split_into_lines(processed)

    result = []
    for line_img in lines:
        text = ocr_line(line_img).strip()
        if text:
            result.append(text)

    return result


def lines_match(a: str, b: str) -> bool:
    if not a or not b:
        return a == b
    if a == b:
        return True
    if a.startswith(b) or b.startswith(a):
        return len(min(a, b, key=len)) >= max(3, len(max(a, b, key=len)) * 0.5)
    matches = sum(1 for i in range(min(len(a), len(b))) if a[i] == b[i])
    return matches / max(len(a), len(b)) > 0.5


def find_overlap(prev: list[str], curr: list[str]) -> int:
    if not prev or not curr:
        return 0

    best = 0
    for offset in range(1, min(len(prev), len(curr)) + 1):
        matches = sum(1 for i in range(offset) if lines_match(prev[-(offset - i)], curr[i]))
        if matches >= max(1, offset * 0.4):
            best = offset
    return best


def stitch(frame_texts: list[list[str]]) -> list[str]:
    if not frame_texts:
        return []

    result = []
    for ft in frame_texts:
        if ft:
            result = list(ft)
            break

    for curr in frame_texts[1:]:
        if not curr:
            continue
        overlap = find_overlap(result, curr)
        if overlap > 0:
            result.extend(curr[overlap:])
        else:
            result.extend(curr)

    return result


def compare_texts(a_text: str, b_text: str, label_a: str, label_b: str) -> float:
    """Compare two texts line-by-line with character diff. Returns agreement %."""
    a_lines = a_text.strip().split("\n")
    b_lines = b_text.strip().split("\n")
    max_lines = max(len(a_lines), len(b_lines))

    total = 0
    matches = 0

    print(f"\n{'='*60}")
    print(f"COMPARISON: {label_a} vs {label_b}")
    print(f"{'='*60}")

    for i in range(max_lines):
        al = a_lines[i] if i < len(a_lines) else ""
        bl = b_lines[i] if i < len(b_lines) else ""
        max_len = max(len(al), len(bl))

        diffs = []
        for j in range(max_len):
            ac = al[j] if j < len(al) else " "
            bc = bl[j] if j < len(bl) else " "
            total += 1
            if ac == bc:
                matches += 1
                diffs.append(" ")
            else:
                diffs.append("^")

        print(f"  {label_a:10s}: {al}")
        print(f"  {label_b:10s}: {bl}")
        diff_str = "".join(diffs)
        if "^" in diff_str:
            print(f"  {'Diff':10s}: {diff_str}")
        print()

    pct = matches / total * 100 if total > 0 else 0
    print(f"Agreement: {matches}/{total} chars ({pct:.1f}%)")
    return pct


def main():
    parser = argparse.ArgumentParser(description="Verify CRT video OCR (independent method)")
    parser.add_argument("--video", type=Path, help="Path to video file")
    parser.add_argument("--fps", type=float, default=4.0,
                        help="Frame rate (default: 4, deliberately different from primary's 5)")
    parser.add_argument("--ocr-result", type=Path, help="Primary OCR result to compare")
    parser.add_argument("--ground-truth", type=Path, help="Ground truth text to compare")
    args = parser.parse_args()

    script_dir = Path(__file__).parent
    video_path = args.video or script_dir / "video.mp4"

    if not video_path.exists():
        sys.exit(f"Video not found: {video_path}")

    print(f"Verification OCR on: {video_path}")
    print(f"(Line-by-line OCR, luminance+Otsu preprocessing, {args.fps} fps)\n")

    with tempfile.TemporaryDirectory() as tmpdir:
        frames_dir = Path(tmpdir) / "vframes"
        frames = extract_frames(video_path, frames_dir, fps=args.fps)
        print(f"Extracted {len(frames)} frames at {args.fps} fps")

        # Detect CRT region
        roi = None
        for fp in frames[1:min(10, len(frames))]:
            img = cv2.imread(str(fp))
            if img is not None:
                roi = detect_crt_region(img)
                if roi[2] - roi[0] > 50 and roi[3] - roi[1] > 50:
                    break

        if roi is None:
            sys.exit("Could not detect CRT region")

        print(f"CRT region: x={roi[0]}-{roi[2]}, y={roi[1]}-{roi[3]}")

        frame_texts = []
        for i, fp in enumerate(frames):
            img = cv2.imread(str(fp))
            if img is None:
                continue
            if not is_text_frame(img, roi):
                print(f"  Frame {i:3d}: [skipped]")
                continue

            x1, y1, x2, y2 = roi
            cropped = img[y1:y2, x1:x2]
            lines = ocr_frame_by_lines(cropped)

            if lines:
                frame_texts.append(lines)
                print(f"  Frame {i:3d}: {len(lines)} lines - {lines[0][:40]}...")
            else:
                print(f"  Frame {i:3d}: [no text]")

        stitched = stitch(frame_texts)
        result = "\n".join(stitched)

    print(f"\n{'='*60}")
    print("VERIFICATION RESULT:")
    print(f"{'='*60}")
    print(result)
    print(f"{'='*60}")

    out_path = script_dir / "verify_result.txt"
    out_path.write_text(result + "\n")
    print(f"\nSaved to: {out_path}")

    # Compare with primary OCR
    ocr_path = args.ocr_result or script_dir / "ocr_result.txt"
    if ocr_path.exists():
        primary = ocr_path.read_text().strip()
        compare_texts(primary, result, "Primary", "Verified")

    # Compare with ground truth
    gt_path = args.ground_truth or script_dir / "ground_truth.txt"
    if gt_path.exists():
        gt = gt_path.read_text().strip()
        compare_texts(result, gt, "Verified", "Truth")
        if ocr_path.exists():
            primary = ocr_path.read_text().strip()
            compare_texts(primary, gt, "Primary", "Truth")


if __name__ == "__main__":
    main()
