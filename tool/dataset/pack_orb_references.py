"""Build bounded ORB shards and the binary index from fresh references."""

from array import array
import base64
import csv
import gzip
import hashlib
import json
from pathlib import Path
import struct
import sys

TABLES = 4
KEYS = 1 << 16
SHARD_SIZE = 8
FEATURES = 384
INDEX_FEATURES = 96


def signature(descriptor, table):
    # Same byte positions and bit order as OrbIndex in Dart.
    return descriptor[table * 8] | (descriptor[table * 8 + 5] << 8)


def pack_references(references, catalog, output):
    """Pack normalized front features in order, retaining only one shard at a time."""
    catalog, output = Path(catalog), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError(
            "ORB output directory must be empty; use a fresh staging directory"
        )
    with catalog.open(encoding="utf-8-sig", newline="") as file:
        catalog_ids = {r["id"] for r in csv.DictReader(file)}
    buckets = [array("I") for _ in range(TABLES * KEYS)]
    ids, shard, seen = [], [], set()
    bank = bytearray()

    def write_shard():
        number = (len(ids) - 1) // SHARD_SIZE
        payload = json.dumps({"cards": shard}, separators=(",", ":")).encode()
        (output / f"{number:05d}.json.gz").write_bytes(gzip.compress(payload, mtime=0))
        shard.clear()

    for reference in references:
        card_id = reference["id"]
        if card_id not in catalog_ids:
            raise ValueError(f"Reference ID absent from catalog: {card_id}")
        if card_id in seen:
            raise ValueError(f"Duplicate ID: {card_id}")
        seen.add(card_id)
        points = reference["points"]
        descriptors = base64.b64decode(reference["descriptors"], validate=True)
        if len(points) < 12 or len(descriptors) != len(points) * 32:
            raise ValueError(f"Invalid features: {card_id}")
        # Preserve uniform pyramid coverage, then reserve extra features for
        # artwork. Text alone is insufficient for safe geometric identification.
        base_count = min(256, len(points))
        chosen = [i * len(points) // base_count for i in range(base_count)]
        selected_set = set(chosen)
        artwork = [
            i
            for i, point in enumerate(points)
            if i not in selected_set
               and 0.08 < point[0] < 0.92
               and 0.1 < point[1] < 0.52
        ]
        extra_count = min(FEATURES - len(chosen), len(artwork))
        chosen.extend(
            artwork[i * len(artwork) // extra_count] for i in range(extra_count)
        )
        selected_set = set(chosen)
        remaining = [i for i in range(len(points)) if i not in selected_set]
        extra_count = min(FEATURES - len(chosen), len(remaining))
        chosen.extend(
            remaining[i * len(remaining) // extra_count] for i in range(extra_count)
        )
        selected = [descriptors[i * 32: (i + 1) * 32] for i in chosen]
        number = len(ids)
        retrieval_count = min(256, len(points))
        retrieval_positions = [
            i * retrieval_count // INDEX_FEATURES * len(points) // retrieval_count
            for i in range(INDEX_FEATURES)
        ]
        indexed = [descriptors[i * 32: (i + 1) * 32] for i in retrieval_positions]
        bank.extend(b"".join(indexed))
        for table in range(TABLES):
            for feature, descriptor in enumerate(indexed):
                buckets[table * KEYS + signature(descriptor, table)].append(
                    number * INDEX_FEATURES + feature
                )
        # Convert normalized keypoints to the fixed coordinate basis used by Dart.
        shard.append(
            {
                "id": card_id,
                "points": [[points[i][0] * 1000, points[i][1] * 1000] for i in chosen],
                "descriptors": base64.b64encode(b"".join(selected)).decode(),
                "hash": [],
                "back": reference.get("back", False),
            }
        )
        ids.append(card_id)
        if len(shard) == SHARD_SIZE:
            write_shard()
        if len(ids) % 1000 == 0:
            print(f"{len(ids)} packed", flush=True)
    if shard:
        write_shard()
    if not ids:
        raise ValueError("Empty database")
    offsets = array("I", [0])
    postings = array("I")
    for bucket in buckets:
        postings.extend(bucket)
        offsets.append(len(postings))
    if sys.byteorder != "little":
        offsets.byteswap()
        postings.byteswap()
    index = (
            b"ORBI"
            + struct.pack("<III", len(ids), SHARD_SIZE, INDEX_FEATURES)
            + offsets.tobytes()
            + postings.tobytes()
            + bank
    )
    if len(index) > 128 * 1024 * 1024:
        raise ValueError("Index exceeds the 128 MiB memory budget")
    digest = hashlib.sha256(index).hexdigest()[:16]
    for start in range(0, len(index), 1024 * 1024):
        (output / f"retrieval_{start // (1024 * 1024):03d}.bin").write_bytes(
            index[start: start + 1024 * 1024]
        )
    (output / "manifest.json").write_text(
        json.dumps(
            {
                "index_id": digest,
                "index_bytes": len(index),
                "index_chunks": (len(index) + 1024 * 1024 - 1) // (1024 * 1024),
                "shard_size": SHARD_SIZE,
                "ids": ids,
            },
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )
    print(
        f"{len(ids)} cards; index {len(index) / 1024 ** 2:.1f} MiB; "
        f"assets {sum(p.stat().st_size for p in output.iterdir()) / 1024 ** 2:.1f} MiB"
    )

    return len(ids)
