#!/usr/bin/env python3
"""
Independent verification of OCR results from the CRT video.

This script uses a completely different approach from ocr_video.py:
  1. Splits the CRT image into individual text lines via horizontal projection
  2. Applies multiple independent preprocessing pipelines to each line
  3. Runs tesseract with different engine modes (LSTM vs legacy) on each variant
  4. Takes a per-character majority vote across all variants
  5. Compares the consensus result against the primary OCR output

Since the text is nonsensical (random ASCII), we can't use spell-check or
dictionary correction. Instead, confidence comes from agreement across
independent preprocessing + OCR pipelines.

Usage:
    python3 verify_ocr.py [--image PATH] [--ocr-result PATH] [--ground-truth PATH]

Dependencies:
    apt install tesseract-ocr ffmpeg
    pip install opencv-python-headless numpy Pillow pytesseract
"""

import argparse
import sys
from collections import Counter
from pathlib import Path

import cv2
import numpy as np
import pytesseract


# Same CRT ROI as the main script (must match for fair comparison)
CRT_ROI_FRAC = (0.402, 0.361, 0.594, 0.535)


def crop_crt_region(image: np.ndarray) -> np.ndarray:
    h, w = image.shape[:2]
    x1 = int(w * CRT_ROI_FRAC[0])
    y1 = int(h * CRT_ROI_FRAC[1])
    x2 = int(w * CRT_ROI_FRAC[2])
    y2 = int(h * CRT_ROI_FRAC[3])
    return image[y1:y2, x1:x2]


def split_into_lines(binary: np.ndarray, min_gap: int = 2) -> list[np.ndarray]:
    """Split a binary image into text line strips using horizontal projection."""
    h_proj = np.sum(binary > 128, axis=1)
    threshold = max(1, np.max(h_proj) * 0.05) if np.max(h_proj) > 0 else 1
    in_text = h_proj > threshold

    lines = []
    start = None
    for i, active in enumerate(in_text):
        if active and start is None:
            start = i
        elif not active and start is not None:
            if i - start > min_gap:
                # Add small padding above and below
                y1 = max(0, start - 1)
                y2 = min(binary.shape[0], i + 1)
                lines.append(binary[y1:y2, :])
            start = None
    if start is not None:
        y1 = max(0, start - 1)
        lines.append(binary[y1:, :])

    return lines


def preprocess_v0(image: np.ndarray) -> np.ndarray:
    """Green channel + adaptive threshold + 6x upscale + smooth."""
    green = image[:, :, 1] if len(image.shape) == 3 else image
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(4, 4))
    enhanced = clahe.apply(green)
    binary = cv2.adaptiveThreshold(
        enhanced, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY, blockSize=21, C=-8
    )
    h, w = binary.shape
    up = cv2.resize(binary, (w * 6, h * 6), interpolation=cv2.INTER_NEAREST)
    smoothed = cv2.GaussianBlur(up, (5, 5), 1.0)
    _, out = cv2.threshold(smoothed, 128, 255, cv2.THRESH_BINARY)
    return out


def preprocess_v1(image: np.ndarray) -> np.ndarray:
    """Luminance + Otsu + 6x upscale + smooth."""
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)
    _, binary = cv2.threshold(enhanced, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    h, w = binary.shape
    up = cv2.resize(binary, (w * 6, h * 6), interpolation=cv2.INTER_NEAREST)
    smoothed = cv2.GaussianBlur(up, (3, 3), 0.8)
    _, out = cv2.threshold(smoothed, 128, 255, cv2.THRESH_BINARY)
    return out


def preprocess_v2(image: np.ndarray) -> np.ndarray:
    """Green channel + fixed threshold + 8x upscale + heavier smooth."""
    green = image[:, :, 1] if len(image.shape) == 3 else image
    _, binary = cv2.threshold(green, 100, 255, cv2.THRESH_BINARY)
    kernel = np.ones((2, 2), np.uint8)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)
    h, w = binary.shape
    up = cv2.resize(binary, (w * 8, h * 8), interpolation=cv2.INTER_NEAREST)
    smoothed = cv2.GaussianBlur(up, (7, 7), 1.5)
    _, out = cv2.threshold(smoothed, 128, 255, cv2.THRESH_BINARY)
    return out


def preprocess_v3(image: np.ndarray) -> np.ndarray:
    """Max(R,G,B) + adaptive threshold + 6x upscale + smooth."""
    if len(image.shape) == 3:
        gray = np.max(image, axis=2)
    else:
        gray = image
    binary = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_MEAN_C,
        cv2.THRESH_BINARY, blockSize=15, C=-6
    )
    kernel = np.ones((2, 2), np.uint8)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)
    h, w = binary.shape
    up = cv2.resize(binary, (w * 6, h * 6), interpolation=cv2.INTER_NEAREST)
    smoothed = cv2.GaussianBlur(up, (5, 5), 1.0)
    _, out = cv2.threshold(smoothed, 128, 255, cv2.THRESH_BINARY)
    return out


PREPROCESS_VARIANTS = [preprocess_v0, preprocess_v1, preprocess_v2, preprocess_v3]


def ocr_single(image: np.ndarray, psm: int = 7) -> str:
    """Run tesseract on a single preprocessed line image."""
    inverted = cv2.bitwise_not(image)
    config = f"--psm {psm}"
    try:
        return pytesseract.image_to_string(inverted, config=config).strip()
    except Exception:
        return ""


def ocr_line_consensus(line_crop_color: np.ndarray) -> str:
    """
    OCR a single text line using multiple independent pipelines,
    then majority-vote per character.
    """
    candidates = []

    for preproc in PREPROCESS_VARIANTS:
        processed = preproc(line_crop_color)
        # Try PSM 7 (single text line) and PSM 13 (raw line)
        for psm in [7, 13]:
            text = ocr_single(processed, psm=psm)
            if text:
                candidates.append(text)

    if not candidates:
        return ""

    # Per-character majority vote across candidates
    max_len = max(len(c) for c in candidates)
    result = []
    for i in range(max_len):
        chars = [c[i] if i < len(c) else "" for c in candidates]
        chars = [c for c in chars if c]  # remove empty
        if chars:
            counter = Counter(chars)
            best, _ = counter.most_common(1)[0]
            result.append(best)

    return "".join(result)


def verify_image(image_path: Path) -> str:
    """Full verification pipeline on a single image."""
    img = cv2.imread(str(image_path))
    if img is None:
        sys.exit(f"Cannot read image: {image_path}")

    cropped = crop_crt_region(img)

    # Use one preprocessing variant to get binary for line splitting
    binary_for_split = preprocess_v0(cropped)
    lines = split_into_lines(binary_for_split)
    print(f"Detected {len(lines)} text lines")

    if not lines:
        # Fall back to full-image OCR
        print("No lines detected, falling back to full image OCR")
        return ocr_line_consensus(cropped)

    # For each detected line, crop the same region from the COLOR image
    # and run consensus OCR
    h_scale = cropped.shape[0] / binary_for_split.shape[0]
    w_scale = cropped.shape[1] / binary_for_split.shape[1]

    # Re-detect line boundaries on the binary image
    h_proj = np.sum(binary_for_split > 128, axis=1)
    threshold = max(1, np.max(h_proj) * 0.05)
    in_text = h_proj > threshold
    row_ranges = []
    start = None
    for i, active in enumerate(in_text):
        if active and start is None:
            start = i
        elif not active and start is not None:
            if i - start > 2:
                row_ranges.append((start, i))
            start = None
    if start is not None:
        row_ranges.append((start, binary_for_split.shape[0]))

    result_lines = []
    for idx, (ry1, ry2) in enumerate(row_ranges):
        # Map back to color image coordinates
        cy1 = max(0, int(ry1 * h_scale) - 1)
        cy2 = min(cropped.shape[0], int(ry2 * h_scale) + 1)
        line_color = cropped[cy1:cy2, :]

        text = ocr_line_consensus(line_color)
        print(f"  Line {idx}: {text[:60]}")
        result_lines.append(text)

    return "\n".join(result_lines)


def compare_results(primary: str, verified: str, label_a: str = "Primary",
                    label_b: str = "Verified") -> float:
    """Compare two OCR results character by character. Returns agreement %."""
    a_lines = primary.strip().split("\n")
    b_lines = verified.strip().split("\n")
    max_lines = max(len(a_lines), len(b_lines))

    total = 0
    matches = 0

    print(f"\nCHARACTER-BY-CHARACTER COMPARISON ({label_a} vs {label_b}):")
    print("-" * 60)

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
    parser = argparse.ArgumentParser(description="Verify CRT video OCR results")
    parser.add_argument("--image", type=Path, help="Input image")
    parser.add_argument("--ocr-result", type=Path, help="Primary OCR result file")
    parser.add_argument("--ground-truth", type=Path, help="Ground truth text file")
    args = parser.parse_args()

    script_dir = Path(__file__).parent

    # Find image
    image_path = args.image
    if image_path is None:
        for candidate in ["thumb_maxresdefault.jpg", "thumb_sddefault.jpg"]:
            p = script_dir / candidate
            if p.exists():
                image_path = p
                break

    if image_path is None or not image_path.exists():
        sys.exit("No image found. Provide --image or download thumbnail first.")

    print(f"Running independent verification on: {image_path}")
    print("(Line-by-line OCR with 4 preprocessing variants x 2 tesseract modes)\n")

    verified_text = verify_image(image_path)

    print("\n" + "=" * 60)
    print("VERIFICATION RESULT:")
    print("=" * 60)
    print(verified_text)
    print("=" * 60)

    out_path = script_dir / "verify_result.txt"
    out_path.write_text(verified_text + "\n")
    print(f"\nSaved to: {out_path}")

    # Compare with primary OCR result
    ocr_path = args.ocr_result or script_dir / "ocr_result.txt"
    if ocr_path.exists():
        primary = ocr_path.read_text().strip()
        compare_results(primary, verified_text, "Primary", "Verified")

    # Compare both against ground truth if available
    gt_path = args.ground_truth or script_dir / "ground_truth.txt"
    if gt_path.exists():
        gt = gt_path.read_text().strip()
        print("\n" + "=" * 60)
        if ocr_path.exists():
            primary = ocr_path.read_text().strip()
            print("\nPrimary OCR vs Ground Truth:")
            compare_results(primary, gt, "Primary", "Truth")
        print("\nVerification vs Ground Truth:")
        compare_results(verified_text, gt, "Verified", "Truth")


if __name__ == "__main__":
    main()
