"""Generate the project's card catalog dataset."""

from pathlib import Path
import argparse
import csv
import http.client
import json
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from tempfile import NamedTemporaryFile
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

API_BASE = "https://api.tcgdex.net/v2/en"
SECONDARY_DATA_BASE = (
    "https://raw.githubusercontent.com/PokemonTCG/pokemon-tcg-data/master"
)
TCGPLAYER_IMAGE_TEMPLATE = (
    "https://tcgplayer-cdn.tcgplayer.com/product/{product_id}_in_1000x1000.jpg"
)
LIMITLESS_POCKET_IMAGE_TEMPLATE = (
    "https://limitlesstcg.nyc3.cdn.digitaloceanspaces.com/"
    "pocket/{set_id}/{set_id}_{local_id}_EN.webp"
)
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATASET_PATH = PROJECT_ROOT / "tool/dataset/work/card_catalog.csv"

DATA_SOURCES = [
    "TCGdex. (2026). TCGdex: The multilingual Pokémon TCG API.\nhttps://tcgdex.dev/",
    "TCGdex contributors. (2026). Pokémon TCG Cards Database [Data set].\nGitHub. https://github.com/tcgdex/cards-database",
    "Pokémon TCG API contributors. (2026). Pokémon TCG Data [Data set].\nGitHub. https://github.com/PokemonTCG/pokemon-tcg-data",
    "Limitless TCG. (2026). Pokémon TCG Pocket Database.\nhttps://pocket.limitlesstcg.com/cards",
    "TCGplayer. (2026). TCGplayer card images and product data.\nhttps://www.tcgplayer.com/",
]


def write_data_sources(output: Path) -> None:
    """Write the citations that ship with the generated runtime data."""
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(DATA_SOURCES, indent=2) + "\n", encoding="utf-8")


def fetch_json(url: str, retries: int = 6, timeout: int = 30):
    request = Request(url, headers={"User-Agent": "PokemonCardDatasetGenerator/1.0"})
    for attempt in range(1, retries + 1):
        try:
            with urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except (
                HTTPError,
                URLError,
                TimeoutError,
                http.client.IncompleteRead,
                json.JSONDecodeError,
        ) as exc:
            if attempt == retries:
                raise

            retry_after = 0
            if isinstance(exc, HTTPError) and exc.headers.get("Retry-After"):
                try:
                    retry_after = float(exc.headers["Retry-After"])
                except ValueError:
                    retry_after = 0

            time.sleep(max(retry_after, attempt * 1.5))


def clean_text(value) -> str:
    if value is None:
        return ""
    text = str(value)
    if text.lower() in {"none", "null"}:
        return ""
    return " ".join(text.split())


def image_url(card: dict) -> str:
    image = card.get("image")
    return f"{image}/high.webp" if image else ""


def normalized_card_number(value) -> str:
    number = clean_text(value).casefold()
    return str(int(number)) if number.isdigit() else number


def card_to_dataset_row(card: dict, set_name: str) -> dict:
    return {
        "id": clean_text(card.get("id")),
        "image_url": image_url(card),
        "name": clean_text(card.get("name")),
        "set": clean_text(set_name),
    }


def fetch_set(set_id: str) -> dict:
    return fetch_json(f"{API_BASE}/sets/{set_id}")


def fetch_card(card_id: str) -> dict:
    encoded_id = quote(card_id, safe="!-_.~")
    return fetch_json(f"{API_BASE}/cards/{encoded_id}")


def fetch_secondary_card_set(set_id: str) -> list[dict]:
    return fetch_json(f"{SECONDARY_DATA_BASE}/cards/en/{set_id}.json")


def apply_secondary_image_urls(
        rows_by_id: dict[str, dict],
        missing_cards: list[dict],
        *,
        workers: int,
) -> int:
    if not missing_cards:
        return 0

    secondary_sets = fetch_json(f"{SECONDARY_DATA_BASE}/sets/en.json")
    secondary_sets_by_name = {
        clean_text(item.get("name")).casefold(): item
        for item in secondary_sets
        if item.get("id") and item.get("name")
    }
    needed_sets = {
        clean_text(card["set"]).casefold()
        for card in missing_cards
        if clean_text(card["set"]).casefold() in secondary_sets_by_name
    }

    images_by_card = {}
    failures = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(
                fetch_secondary_card_set,
                secondary_sets_by_name[set_name]["id"],
            ): set_name
            for set_name in needed_sets
        }
        for future in as_completed(futures):
            set_name = futures[future]
            try:
                for card in future.result():
                    large_image = (card.get("images") or {}).get("large")
                    if large_image:
                        key = (set_name, normalized_card_number(card.get("number")))
                        images_by_card[key] = large_image
            except Exception as exc:  # noqa: BLE001 - fallback images are optional.
                failures.append((set_name, str(exc)))

    filled = 0
    for card in missing_cards:
        key = (
            clean_text(card["set"]).casefold(),
            normalized_card_number(card["local_id"]),
        )
        secondary_image = images_by_card.get(key)
        if secondary_image:
            rows_by_id[card["id"]]["image_url"] = secondary_image
            filled += 1

    if failures:
        print(
            f"Warning: {len(failures)} secondary image sets could not be fetched; "
            "their image URLs remain blank."
        )

    return filled


def tcgplayer_image_url(card: dict) -> str:
    for variant in card.get("variants_detailed") or []:
        product_id = (variant.get("thirdParty") or {}).get("tcgplayer")
        if product_id:
            return TCGPLAYER_IMAGE_TEMPLATE.format(product_id=product_id)
    return ""


def apply_tcgplayer_image_urls(
        rows_by_id: dict[str, dict],
        card_ids: list[str],
        *,
        workers: int,
) -> int:
    filled = 0
    failures = []
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(fetch_card, card_id): card_id for card_id in card_ids
        }
        for future in as_completed(futures):
            card_id = futures[future]
            try:
                fallback_url = tcgplayer_image_url(future.result())
                if fallback_url:
                    rows_by_id[card_id]["image_url"] = fallback_url
                    filled += 1
            except Exception as exc:  # noqa: BLE001 - fallback images are optional.
                failures.append((card_id, str(exc)))

    if failures:
        print(
            f"Warning: {len(failures)} card details could not be fetched for "
            "TCGplayer image fallback."
        )

    return filled


def apply_limitless_pocket_image_urls(
        rows_by_id: dict[str, dict],
        missing_cards: list[dict],
) -> int:
    filled = 0
    for card in missing_cards:
        if card.get("series_id") != "tcgp":
            continue

        local_id = clean_text(card.get("local_id"))
        if not local_id.isdigit():
            continue

        set_id = clean_text(card.get("set_id"))
        rows_by_id[card["id"]]["image_url"] = LIMITLESS_POCKET_IMAGE_TEMPLATE.format(
            set_id=set_id,
            local_id=local_id.zfill(3),
        )
        filled += 1

    return filled


def build_english_pokemon_dataset(
        output: Path,
        *,
        workers: int = 8,
        limit: int | None = None,
        secondary_images: bool = True,
) -> None:
    sets = fetch_json(f"{API_BASE}/sets")
    expected_card_count = len(fetch_json(f"{API_BASE}/cards"))

    output.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["id", "image_url", "name", "set"]
    rows_by_id = {}
    missing_cards = []
    failures = []

    print(f"Fetching {len(sets)} English sets from TCGdex...")
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = {
            executor.submit(fetch_set, set_summary["id"]): set_summary["id"]
            for set_summary in sets
            if set_summary.get("id")
        }
        for idx, future in enumerate(as_completed(futures), start=1):
            set_id = futures[future]
            try:
                set_data = future.result()
                for card in set_data.get("cards") or []:
                    row = card_to_dataset_row(card, set_data.get("name"))
                    rows_by_id[row["id"]] = row
                    if not row["image_url"]:
                        missing_cards.append(
                            {
                                "id": row["id"],
                                "local_id": card.get("localId"),
                                "set": row["set"],
                                "set_id": set_data.get("id"),
                                "series_id": (set_data.get("serie") or {}).get("id"),
                            }
                        )
            except Exception as exc:  # noqa: BLE001 - keep batch generation moving.
                failures.append((set_id, str(exc)))

            if idx % 25 == 0 or idx == len(futures):
                print(
                    f" [{idx}/{len(futures)}] sets; collected {len(rows_by_id)} cards"
                )

    if failures:
        messages = "; ".join(
            f"{set_id}: {message}" for set_id, message in failures[:20]
        )
        if len(failures) > 20:
            messages += f"; ... and {len(failures) - 20} more"
        raise RuntimeError(
            f"Could not fetch {len(failures)} sets; existing output was not replaced. "
            f"{messages}"
        )

    if len(rows_by_id) != expected_card_count:
        raise RuntimeError(
            f"Expected {expected_card_count} unique cards but collected "
            f"{len(rows_by_id)}; "
            "existing output was not replaced."
        )

    if secondary_images:
        print(
            f"Looking up secondary images for {len(missing_cards)} cards "
            "without TCGdex images..."
        )
        pocket_filled = apply_limitless_pocket_image_urls(
            rows_by_id,
            missing_cards,
        )
        print(f"Filled {pocket_filled} Pokemon TCG Pocket image URLs.")

        catalog_missing_cards = [
            card for card in missing_cards if not rows_by_id[card["id"]]["image_url"]
        ]
        filled = apply_secondary_image_urls(
            rows_by_id,
            catalog_missing_cards,
            workers=workers,
        )
        print(f"Filled {filled} image URLs from the historical catalog.")

        unresolved_ids = [
            card["id"]
            for card in missing_cards
            if not rows_by_id[card["id"]]["image_url"]
        ]
        if unresolved_ids:
            print(
                f"Looking up TCGplayer images for {len(unresolved_ids)} "
                "remaining cards..."
            )
            tcgplayer_filled = apply_tcgplayer_image_urls(
                rows_by_id,
                unresolved_ids,
                workers=workers,
            )
            print(f"Filled {tcgplayer_filled} image URLs from TCGplayer.")

    sorted_rows = [rows_by_id[key] for key in sorted(rows_by_id)]
    if limit is not None:
        sorted_rows = sorted_rows[:limit]
    with NamedTemporaryFile(
            "w",
            newline="",
            encoding="utf-8",
            delete=False,
            dir=output.parent,
            suffix=".tmp",
    ) as tmp:
        writer = csv.DictWriter(tmp, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(sorted_rows)
        tmp_path = Path(tmp.name)

    tmp_path.replace(output)
    print(f"Wrote {len(sorted_rows)} cards to {output}")


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_DATASET_PATH,
        help="CSV output path; defaults to tool/dataset/work/card_catalog.csv.",
    )
    parser.add_argument(
        "--workers", type=int, default=8, help="Number of concurrent API requests."
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Write only the first N sorted cards after fetching the catalog.",
    )
    parser.add_argument(
        "--no-secondary-images",
        action="store_true",
        help="Leave missing TCGdex image URLs blank instead of using fallback sources.",
    )
    args = parser.parse_args(argv)
    if args.workers < 1 or (args.limit is not None and args.limit < 1):
        parser.error("workers and limit must be positive")
    return args


def main(argv=None):
    args = parse_args(argv)
    build_english_pokemon_dataset(
        args.output,
        workers=args.workers,
        limit=args.limit,
        secondary_images=not args.no_secondary_images,
    )


if __name__ == "__main__":
    main()
