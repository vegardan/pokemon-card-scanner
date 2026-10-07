"""Download reference images and generate ORB shards directly.

Images and full JSON exports are never saved. Only ORB shards, index chunks,
and the manifest are produced; download failures go to a separate work report.
"""

import argparse
import base64
import concurrent.futures
import csv
import json
from pathlib import Path
import sys
import time
import urllib.request

import cv2
import numpy as np

from pack_orb_references import pack_references


def load_catalog(path):
    with Path(path).open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        if not {"id", "image_url"}.issubset(reader.fieldnames or []):
            raise ValueError("CSV must contain id and image_url columns")
        rows = [
            {"id": row["id"].strip(), "image_url": row["image_url"].strip()}
            for row in reader
        ]
    ids = [row["id"] for row in rows]
    if not ids or any(not card_id for card_id in ids) or len(set(ids)) != len(ids):
        raise ValueError("CSV must contain nonempty, unique card IDs")
    return rows


def extract_orb(card_id, image_bytes, features=1000):
    image = cv2.imdecode(
        np.frombuffer(image_bytes, dtype=np.uint8), cv2.IMREAD_GRAYSCALE
    )
    if image is None or min(image.shape) < 16:
        raise ValueError("Invalid or too small reference image")
    height, width = image.shape
    height = max(16, round(height * 600 / width))
    image = cv2.resize(image, (600, height), interpolation=cv2.INTER_AREA)
    orb = cv2.ORB_create(nfeatures=features, fastThreshold=12)
    points, descriptors = orb.detectAndCompute(image, None)
    if descriptors is None or len(points) < 12:
        raise ValueError("Reference has fewer than 12 ORB features")
    return {
        "id": card_id,
        "points": [
            [round(point.pt[0] / 600, 6), round(point.pt[1] / height, 6)]
            for point in points
        ],
        "descriptors": base64.b64encode(descriptors.tobytes()).decode("ascii"),
    }


def download_reference(row, features=1000, retries=2, timeout=30):
    if not row["image_url"]:
        return None, {"id": row["id"], "error": "Missing image URL"}
    for attempt in range(retries + 1):
        try:
            request = urllib.request.Request(
                row["image_url"],
                headers={"User-Agent": "PokemonCardReferenceBuilder/1.0"},
            )
            with urllib.request.urlopen(request, timeout=timeout) as response:
                image_bytes = response.read()
        except Exception as error:
            if attempt < retries:
                time.sleep(attempt + 1)
                continue
            return None, {"id": row["id"], "error": str(error)}
        try:
            return extract_orb(row["id"], image_bytes, features), None
        except (ValueError, cv2.error) as error:
            return None, {"id": row["id"], "error": str(error)}


def iter_downloaded_references(
        rows, errors, workers=8, features=1000, retries=2, timeout=30
):
    """Download bounded batches and yield references in deterministic CSV order."""
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        batch_size = workers * 4
        for start in range(0, len(rows), batch_size):
            tasks = [
                pool.submit(download_reference, row, features, retries, timeout)
                for row in rows[start: start + batch_size]
            ]
            for task in tasks:
                reference, error = task.result()
                if error:
                    errors.append(error)
                else:
                    yield reference
            print(
                f"{min(start + batch_size, len(rows))}/{len(rows)} images processed; "
                f"{len(errors)} failed",
                file=sys.stderr,
                flush=True,
            )


def generate_index(
        rows, catalog, output, report, workers=8, features=1000, retries=2, timeout=30
):
    """Write ORB shards directly; error reports remain outside app assets."""
    errors = []
    try:
        written = pack_references(
            iter_downloaded_references(
                rows, errors, workers, features, retries, timeout
            ),
            Path(catalog),
            Path(output),
        )
    finally:
        report = Path(report)
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(json.dumps(errors, indent=2), encoding="utf-8")
    return written, errors


def main(argv=None):
    project_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--csv", type=Path, default=project_root / "tool/dataset/work/card_catalog.csv"
    )
    parser.add_argument(
        "--output", type=Path, default=project_root / "tool/dataset/work/orb_references"
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=project_root / "tool/dataset/work/reference_errors.json",
    )
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--features", type=int, default=1000)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args(argv)
    if args.workers < 1 or args.features < 12 or args.retries < 0 or args.timeout <= 0:
        parser.error(
            "workers and timeout must be positive; features >= 12; retries >= 0"
        )
    cv2.setNumThreads(1)
    try:
        rows = load_catalog(args.csv)
        written, errors = generate_index(
            rows,
            args.csv,
            args.output,
            args.report,
            args.workers,
            args.features,
            args.retries,
            args.timeout,
        )
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print(
        json.dumps(
            {
                "catalog_cards": len(rows),
                "references": written,
                "failed": len(errors),
                "output": str(args.output),
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
