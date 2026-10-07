"""Generate, validate, and publish only the dataset files used by Flutter."""

import argparse
import csv
import json
from pathlib import Path
import shutil
import sys
import uuid

import cv2

from generate_card_catalog import build_english_pokemon_dataset, write_data_sources
from generate_orb_references import generate_index, load_catalog
from prepare_back_reference import prepare_back
from validate_orb_references import validate_structure

PROJECT_ROOT = Path(__file__).resolve().parents[2]
WORK_ROOT = PROJECT_ROOT / "tool/dataset/work"
RUNTIME_FILES = ("card_catalog.csv", "data_sources.json", "orb_references")


def validate_catalog(data):
    """Check that every indexed card has the metadata used by the app."""
    with (data / "card_catalog.csv").open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        if not {"id", "image_url", "name", "set"}.issubset(reader.fieldnames or []):
            raise ValueError(
                "Catalog must contain id, image_url, name, and set columns"
            )
        rows = list(reader)
    ids = [row["id"] for row in rows]
    if not ids or any(not card_id for card_id in ids) or len(ids) != len(set(ids)):
        raise ValueError("Catalog IDs must be nonempty and unique")
    manifest = json.loads(
        (data / "orb_references/manifest.json").read_text(encoding="utf-8")
    )
    if not set(manifest["ids"]).issubset(ids):
        raise ValueError("ORB index contains IDs absent from the catalog")
    sources = json.loads((data / "data_sources.json").read_text(encoding="utf-8"))
    if (
            not sources
            or not isinstance(sources, list)
            or not all(isinstance(s, str) for s in sources)
    ):
        raise ValueError("Data sources must be a nonempty list of citations")


def publish_dataset(data, assets):
    """Publish validated files, restoring the previous dataset if a move fails.

    Only the three runtime outputs are moved. Reports stay in the dataset working directory.
    """
    data, assets = Path(data).resolve(), Path(assets).resolve()
    if data == assets or data.is_relative_to(assets) or assets.is_relative_to(data):
        raise ValueError("Staging and assets directories must be separate")
    if {p.name for p in data.iterdir()} != set(RUNTIME_FILES):
        raise ValueError("Staging directory must contain only runtime outputs")
    backup = data.parent / "previous_assets"
    backup.mkdir()  # Never overwrite an earlier backup.
    assets.mkdir(parents=True, exist_ok=True)
    saved, published = [], []
    try:
        for name in RUNTIME_FILES:
            target = assets / name
            if target.exists():
                target.rename(backup / name)
                saved.append(name)
            (data / name).rename(target)
            published.append(name)
    except BaseException:
        # Move new files back before restoring the originals, including when a
        # user interrupts publication. Failed builds remain available to inspect.
        for name in reversed(published):
            (assets / name).rename(data / name)
        for name in reversed(saved):
            (backup / name).rename(assets / name)
        raise
    return backup


def remove_generated_backup(backup, run):
    """Recursively remove only this run's verified, workspace-local backup."""
    backup, run, work = backup.resolve(), run.resolve(), WORK_ROOT.resolve()
    if not run.is_relative_to(work) or run == work or backup != run / "previous_assets":
        raise ValueError("Refusing to remove a directory outside this build run")
    shutil.rmtree(backup)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args(argv)
    if args.workers < 1 or args.retries < 0 or args.timeout <= 0:
        parser.error(
            "workers and timeout must be positive; retries must be nonnegative"
        )
    return args


def main(argv=None):
    args = parse_args(argv)
    cv2.setNumThreads(1)
    WORK_ROOT.mkdir(parents=True, exist_ok=True)
    # Windows mkdtemp may apply an owner-only ACL.
    # A normal directory inherits workspace permissions so the published assets
    # remain readable by Flutter and by the developer's desktop account.
    run = WORK_ROOT / f"run-{uuid.uuid4().hex}"
    run.mkdir()
    data = run / "data"
    data.mkdir()
    catalog = data / "card_catalog.csv"
    print(f"Working directory: {run}", flush=True)
    try:
        print("1/5: Prepare the card catalog and source citations", flush=True)
        build_english_pokemon_dataset(catalog, workers=args.workers)
        write_data_sources(data / "data_sources.json")

        print("2/5: Build front shards and the retrieval index", flush=True)
        references = data / "orb_references"
        _, errors = generate_index(
            load_catalog(catalog),
            catalog,
            references,
            run / "reference_errors.json",
            workers=args.workers,
            retries=args.retries,
            timeout=args.timeout,
        )
        if errors:
            print(
                f'{len(errors)} front references omitted; report: {run / "reference_errors.json"}',
                flush=True,
            )

        print("3/5: Prepare the shared back reference", flush=True)
        prepare_back(references / "back.json.gz")

        print("4/5: Validate the dataset before publication", flush=True)
        validate_catalog(data)
        validate_structure(references)

        print("5/5: Publish runtime files to assets/data", flush=True)
        backup = publish_dataset(data, PROJECT_ROOT / "assets/data")
    except Exception as error:
        print(
            f"Build failed: {error}\nWorking files retained at {run}", file=sys.stderr
        )
        return 1
    try:
        remove_generated_backup(backup, run)
    except OSError as error:
        print(
            f"Dataset published; previous assets retained at {backup}: {error}",
            file=sys.stderr,
        )
    print(f'Dataset published to {PROJECT_ROOT / "assets/data"}', flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
