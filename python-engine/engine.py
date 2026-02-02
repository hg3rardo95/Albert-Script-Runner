"""python-engine entrypoint

This file is the single command-line interface (CLI) that the SwiftUI app will call.
Keep Albert SDK / pandas logic inside feature modules (e.g., users.py, locations.py)

Usage example:
  python engine.py download-users --token <JWT> --base-url https://sandbox.albertinvent.com --out /path/users.xlsx
"""

from __future__ import annotations

import argparse
import json
import sys
import traceback
from pathlib import Path


def _resolve_download_users_fn():
    """Backward-compatible resolver for the users export function.

    Supports either:
      - users.download_all_users(token, base_url)
      - users.DownloadAllUsers(token, base_url)

    Returns the callable.
    """

    try:
        import users  # type: ignore
    except Exception as e:
        raise RuntimeError(
            "Unable to import users.py. Make sure you're running from the python-engine folder and your venv deps are installed. "
            f"Original error: {e}"
        )

    if hasattr(users, "download_all_users"):
        return getattr(users, "download_all_users")
    if hasattr(users, "DownloadAllUsers"):
        return getattr(users, "DownloadAllUsers")

    raise RuntimeError(
        "users.py does not define download_all_users(...) or DownloadAllUsers(...). "
        "Please add one of these functions."
    )


def _resolve_get_all_locations_fn():
    """Backward-compatible resolver for the locations list function.

    Supports either:
      - locations.get_all_locations(base_url, token)
      - locations.getAllLoc(base_url, token)

    Returns the callable.
    """

    try:
        import locations  # type: ignore
    except Exception as e:
        raise RuntimeError(
            "Unable to import locations.py. Make sure you're running from the python-engine folder and your venv deps are installed. "
            f"Original error: {e}"
        )

    if hasattr(locations, "get_all_locations"):
        return getattr(locations, "get_all_locations")
    if hasattr(locations, "getAllLoc"):
        return getattr(locations, "getAllLoc")

    raise RuntimeError(
        "locations.py does not define get_all_locations(...) or getAllLoc(...). "
        "Please add one of these functions."
    )


def _resolve_upload_new_locations_fn():
    """Resolver for the structured upload helper.

    Supports:
      - locations.upload_new_locations(base_url, token, inputs)

    Returns the callable.
    """

    try:
        import locations  # type: ignore
    except Exception as e:
        raise RuntimeError(
            "Unable to import locations.py. Make sure you're running from the python-engine folder and your venv deps are installed. "
            f"Original error: {e}"
        )

    if hasattr(locations, "upload_new_locations"):
        return getattr(locations, "upload_new_locations")

    raise RuntimeError(
        "locations.py does not define upload_new_locations(...). "
        "Please add upload_new_locations(base_url, token, inputs)."
    )


def _resolve_update_existing_locations_fn():
    """Resolver for the structured update helper.

    Supports:
      - locations.update_existing_locations(base_url, token, inputs)
      - locations.update_locations(base_url, token, inputs)  (fallback name)

    Returns the callable.
    """

    try:
        import locations  # type: ignore
    except Exception as e:
        raise RuntimeError(
            "Unable to import locations.py. Make sure you're running from the python-engine folder and your venv deps are installed. "
            f"Original error: {e}"
        )

    if hasattr(locations, "update_existing_locations"):
        return getattr(locations, "update_existing_locations")

    # Optional fallback if the function was named differently
    if hasattr(locations, "update_locations"):
        return getattr(locations, "update_locations")

    raise RuntimeError(
        "locations.py does not define update_existing_locations(...). "
        "Please add update_existing_locations(base_url, token, inputs)."
    )


def cmd_download_users(token: str, base_url: str, out_path: str) -> None:
    """Download all users and write an Excel file."""

    fn = _resolve_download_users_fn()
    df = fn(token, base_url)

    out = Path(out_path).expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    # Write Excel
    df.to_excel(out, index=False)

    # Machine-readable success message for SwiftUI
    print(f"OK:WROTE:{out}")


def cmd_list_locations(token: str, base_url: str, out_path: str | None = None) -> None:
    """Fetch all locations and output them as JSON (stdout by default, or file when --out is provided)."""

    fn = _resolve_get_all_locations_fn()
    locs = fn(base_url, token)

    # Convert to a Swift-friendly JSON structure
    out = []
    for loc in locs:
        out.append(
            {
                "id": getattr(loc, "id", None),
                "name": getattr(loc, "name", None),
                "address": getattr(loc, "address", None),
                "country": getattr(loc, "country", None),
                "latitude": getattr(loc, "latitude", None),
                "longitude": getattr(loc, "longitude", None),
            }
        )

    payload = json.dumps(out, ensure_ascii=False)

    if out_path:
        out_file = Path(out_path).expanduser().resolve()
        out_file.parent.mkdir(parents=True, exist_ok=True)
        out_file.write_text(payload, encoding="utf-8")
        print(f"OK:WROTE:{out_file}")
    else:
        print(payload)


def cmd_upload_locations(token: str, base_url: str, in_path: str, out_path: str | None = None) -> None:
    """Upload new locations from a JSON input file.

    The input JSON must be a list of dict rows from Swift (name/address/country/latitude/longitude).

    Outputs JSON to stdout by default. If --out is provided, writes JSON to file and prints OK:WROTE:<path>.
    """

    in_file = Path(in_path).expanduser().resolve()
    if not in_file.exists():
        raise RuntimeError(f"Input file not found: {in_file}")

    raw = in_file.read_text(encoding="utf-8")
    try:
        inputs = json.loads(raw)
    except Exception as e:
        raise RuntimeError(f"Unable to parse JSON from --in file: {e}")

    if not isinstance(inputs, list):
        raise RuntimeError("Input JSON must be a list of objects")

    fn = _resolve_upload_new_locations_fn()
    results = fn(base_url, token, inputs)

    payload = json.dumps(results, ensure_ascii=False)

    if out_path:
        out_file = Path(out_path).expanduser().resolve()
        out_file.parent.mkdir(parents=True, exist_ok=True)
        out_file.write_text(payload, encoding="utf-8")
        print(f"OK:WROTE:{out_file}")
    else:
        print(payload)


def cmd_update_locations(token: str, base_url: str, in_path: str, out_path: str | None = None) -> None:
    """Update existing locations from a JSON input file.

    The input JSON must be a list of dict rows from Swift.
    Each row must include an 'id' (or 'ID') and any fields to update.

    Outputs JSON to stdout by default. If --out is provided, writes JSON to file and prints OK:WROTE:<path>.
    """

    in_file = Path(in_path).expanduser().resolve()
    if not in_file.exists():
        raise RuntimeError(f"Input file not found: {in_file}")

    raw = in_file.read_text(encoding="utf-8")
    try:
        inputs = json.loads(raw)
    except Exception as e:
        raise RuntimeError(f"Unable to parse JSON from --in file: {e}")

    if not isinstance(inputs, list):
        raise RuntimeError("Input JSON must be a list of objects")

    fn = _resolve_update_existing_locations_fn()
    results = fn(base_url, token, inputs)

    payload = json.dumps(results, ensure_ascii=False)

    if out_path:
        out_file = Path(out_path).expanduser().resolve()
        out_file.parent.mkdir(parents=True, exist_ok=True)
        out_file.write_text(payload, encoding="utf-8")
        print(f"OK:WROTE:{out_file}")
    else:
        print(payload)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="engine.py",
        description="python-engine CLI for Albert Script Runner (called by SwiftUI)",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    dl = sub.add_parser(
        "download-users",
        help="Download all users from the tenant and write an .xlsx file",
    )
    dl.add_argument("--token", required=True, help="Albert JWT token")
    dl.add_argument("--base-url", required=True, help="Albert base URL (e.g., https://sandbox.albertinvent.com)")
    dl.add_argument("--out", required=True, help="Output .xlsx file path")

    ll = sub.add_parser(
        "list-locations",
        help="List all locations in the tenant (prints JSON)",
    )
    ll.add_argument("--token", required=True, help="Albert JWT token")
    ll.add_argument(
        "--base-url",
        required=True,
        help="Albert base URL (e.g., https://sandbox.albertinvent.com)",
    )
    ll.add_argument(
        "--out",
        required=False,
        help="Optional output .json file path. If provided, writes JSON to file and prints OK:WROTE:<path>.",
    )

    ul = sub.add_parser(
        "upload-locations",
        help="Upload new locations from a JSON file (partial success; returns per-row results)",
    )
    ul.add_argument("--token", required=True, help="Albert JWT token")
    ul.add_argument(
        "--base-url",
        required=True,
        help="Albert base URL (e.g., https://sandbox.albertinvent.com)",
    )
    ul.add_argument(
        "--in",
        dest="in_path",
        required=True,
        help="Input JSON file path containing a list of location rows",
    )
    ul.add_argument(
        "--out",
        required=False,
        help="Optional output .json file path. If provided, writes results JSON to file and prints OK:WROTE:<path>.",
    )

    upd = sub.add_parser(
        "update-locations",
        help="Update existing locations from a JSON file (partial success; returns per-row results)",
    )
    upd.add_argument("--token", required=True, help="Albert JWT token")
    upd.add_argument(
        "--base-url",
        required=True,
        help="Albert base URL (e.g., https://sandbox.albertinvent.com)",
    )
    upd.add_argument(
        "--in",
        dest="in_path",
        required=True,
        help="Input JSON file path containing a list of location update rows (must include id/ID)",
    )
    upd.add_argument(
        "--out",
        required=False,
        help="Optional output .json file path. If provided, writes results JSON to file and prints OK:WROTE:<path>.",
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "download-users":
            cmd_download_users(args.token, args.base_url, args.out)
            return 0

        if args.command == "list-locations":
            cmd_list_locations(args.token, args.base_url, getattr(args, "out", None))
            return 0

        if args.command == "upload-locations":
            cmd_upload_locations(args.token, args.base_url, args.in_path, getattr(args, "out", None))
            return 0

        if args.command == "update-locations":
            cmd_update_locations(args.token, args.base_url, args.in_path, getattr(args, "out", None))
            return 0

        parser.error(f"Unknown command: {args.command}")
        return 2

    except Exception as e:
        # stderr so Swift can surface it as an error
        print(f"ERROR:{e}", file=sys.stderr)
        print(traceback.format_exc(), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
