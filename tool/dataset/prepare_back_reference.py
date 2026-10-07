"""Prepare a shared-back ORB reference from the project's card-back image."""

import argparse
import base64
import gzip
import json
from pathlib import Path
import sys

import cv2
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def prepare_back(output):
    image_path = PROJECT_ROOT / "assets/pokemon_back.png"
    if not image_path.is_file():
        raise FileNotFoundError(f"Back image does not exist: {image_path}")
    image = cv2.imdecode(
        np.frombuffer(image_path.read_bytes(), dtype=np.uint8), cv2.IMREAD_COLOR
    )
    if image is None:
        raise ValueError("Invalid back image")
    height, width = image.shape[:2]
    image = cv2.resize(
        image, (600, round(height * 600 / width)), interpolation=cv2.INTER_AREA
    )
    points, descriptors = cv2.ORB_create(
        nfeatures=1000, fastThreshold=12
    ).detectAndCompute(cv2.cvtColor(image, cv2.COLOR_BGR2GRAY), None)
    if descriptors is None or len(points) < 12:
        raise ValueError("Back image has too few ORB features")
    reference = {
        "id": "pokemon-shared-back",
        "back": True,
        # Match the fixed front-reference basis, preserving the old projected
        # corners exactly: pixel (width - 1, height - 1) maps to (999, 999).
        "points": [
            [p.pt[0] * 999 / (image.shape[1] - 1), p.pt[1] * 999 / (image.shape[0] - 1)]
            for p in points
        ],
        "descriptors": base64.b64encode(descriptors.tobytes()).decode(),
        "hash": [],
    }
    target = Path(output)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(
        gzip.compress(
            json.dumps({"cards": [reference]}, separators=(",", ":")).encode(),
            mtime=0,
        )
    )
    print(f"Back reference: {len(points)} features, {target.stat().st_size} bytes")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=PROJECT_ROOT / "tool/dataset/work/orb_references/back.json.gz",
    )
    args = parser.parse_args(argv)
    return prepare_back(args.output)


if __name__ == "__main__":
    sys.exit(main())
