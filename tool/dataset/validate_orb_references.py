"""Validate generated ORB shards, descriptors, and retrieval index integrity."""

import argparse
import base64
import gzip
import hashlib
import json
import math
from pathlib import Path


def validate_structure(assets):
    """Validate every generated file before a dataset can replace live assets."""
    assets = Path(assets)
    manifest = json.loads((assets / "manifest.json").read_text())
    ids = manifest["ids"]
    if manifest["shard_size"] != 8 or not ids or len(ids) != len(set(ids)):
        raise ValueError("Invalid manifest")
    if not 16 <= manifest["index_bytes"] <= 128 * 1024 * 1024 or manifest[
        "index_chunks"
    ] != (manifest["index_bytes"] + 1024 * 1024 - 1) // (1024 * 1024):
        raise ValueError("Invalid manifest index size/chunk count")
    chunks = []
    for i in range(manifest["index_chunks"]):
        chunk = (assets / f"retrieval_{i:03d}.bin").read_bytes()
        expected = min(1024 * 1024, manifest["index_bytes"] - i * 1024 * 1024)
        if not chunk or len(chunk) != expected:
            raise ValueError("Invalid index chunk size")
        chunks.append(chunk)
    data = b"".join(chunks)
    if len(data) != manifest["index_bytes"] or len(data) > 128 * 1024 * 1024:
        raise ValueError("Invalid index size")
    if hashlib.sha256(data).hexdigest()[:16] != manifest["index_id"]:
        raise ValueError("Invalid index digest")
    count = len(ids)
    if manifest.get("features_per_card") != 96:
        raise ValueError("Unsupported descriptor format")
    if len(data) != count * 96 * 32:
        raise ValueError("Invalid catalog descriptor size")
    expected_files = {"manifest.json", "back.json.gz"} | {
        f"retrieval_{i:03d}.bin" for i in range(manifest["index_chunks"])
    }
    for shard in range((count + 7) // 8):
        name = f"{shard:05d}.json.gz"
        expected_files.add(name)
        payload = (assets / name).read_bytes()
        if len(payload) > 512 * 1024:
            raise ValueError("Oversized feature shard")
        records = json.loads(gzip.decompress(payload))
        if [r["id"] for r in records["cards"]] != ids[shard * 8: (shard + 1) * 8]:
            raise ValueError("Shard does not match manifest")
        for reference in records["cards"]:
            if reference["back"]:
                raise ValueError("Front shard contains a back reference")
            validate_reference(reference, maximum_features=384)
    back = (assets / "back.json.gz").read_bytes()
    if len(back) > 128 * 1024:
        raise ValueError("Oversized back reference")
    back = json.loads(gzip.decompress(back))
    if len(back["cards"]) != 1 or not back["cards"][0]["back"]:
        raise ValueError("Invalid back reference")
    validate_reference(back["cards"][0], maximum_features=1000)
    if {p.name for p in assets.iterdir()} != expected_files:
        raise ValueError("Dataset contains unexpected or obsolete files")
    print(f"Structure validated: {count} cards", flush=True)
    return manifest, data


def validate_reference(reference, maximum_features):
    if set(reference) != {"id", "back", "points", "descriptors", "hash"}:
        raise ValueError("Invalid reference fields")
    points = reference["points"]
    descriptors = base64.b64decode(reference["descriptors"], validate=True)
    if (
            not 12 <= len(points) <= maximum_features
            or len(descriptors) != len(points) * 32
    ):
        raise ValueError("Invalid reference features")
    if reference["hash"]:
        raise ValueError("Invalid reference hash")
    if any(
            len(p) != 2
            or not all(math.isfinite(v) for v in p)
            or not 0 <= p[0] < 1000
            or not 0 <= p[1] < 1000
            for p in points
    ):
        raise ValueError("Invalid reference points")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--assets",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "assets/data/orb_references",
    )
    args = parser.parse_args(argv)
    validate_structure(args.assets)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
