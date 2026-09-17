#!/usr/bin/env python3
"""
roblox_version_downloader.py

Bulk-download genuine historical Roblox place versions (.rbxl) using the
same underlying endpoints Roblox Studio itself relies on, then optionally
run them through an existing script-extraction parser.

WHAT THIS DOES NOT DO
----------------------
- It does not fabricate, guess, or reconstruct version history. Every
  version listed/downloaded comes directly from Roblox's servers.
- It does not publish, restore, or otherwise write to your place. Every
  network call this tool makes is a GET request.
- It does not alter file timestamps. Downloaded files get the filesystem
  mtime the OS assigns on write; the *authoritative* timestamp is always
  the one Roblox returned in the version-history API response, and that
  is preserved verbatim in each version's metadata.json / raw JSON dump.

ENDPOINTS USED (verified against Roblox's current Creator Hub docs)
--------------------------------------------------------------------
1. GET https://apis.roblox.com/place-version-history-api/v1/{placeId}/history
   -> Lists place versions. Roblox marks this endpoint "Experimental":
      the response schema is not formally documented and could change.
      This tool therefore parses it defensively (see `_normalize_version`)
      and always writes the raw JSON to disk so nothing is silently lost
      or misinterpreted.

2. GET https://assetdelivery.roblox.com/v2/assetId/{placeId}/version/{version}
   -> Returns {"locations": [{"location": "<CDN url>"}], ...}; fetching
      that CDN url returns the raw .rbxl bytes for that exact version.
      This is a long-standing, community-verified mechanism (the same
      family of endpoint Studio uses to fetch place content).

AUTHENTICATION
---------------
Both endpoints require your Roblox session cookie (.ROBLOSECURITY),
because there is currently no Open Cloud (API-key) endpoint that exposes
historical place versions. See get_credentials() below for how this tool
accepts that cookie without ever hardcoding or logging it.
"""

from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

try:
    import requests
except ImportError:
    print("This tool requires the 'requests' package.\n"
          "Install it with:  pip install requests", file=sys.stderr)
    sys.exit(1)


# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------

HISTORY_URL = "https://apis.roblox.com/place-version-history-api/v1/{place_id}/history"
CONTRIBUTORS_URL = "https://apis.roblox.com/place-version-history-api/v1/{place_id}/contributors"
ASSET_VERSION_URL = "https://assetdelivery.roblox.com/v2/assetId/{place_id}/version/{version}"
AUTH_CHECK_URL = "https://users.roblox.com/v1/users/authenticated"

USER_AGENT = "roblox-version-downloader/1.0 (+personal archival tool)"
COOKIE_ENV_VAR = "ROBLOX_COOKIE"

DEFAULT_DELAY_SECONDS = 1.25
MAX_RETRIES = 6
RETRYABLE_STATUS = {429, 500, 502, 503, 504}


# --------------------------------------------------------------------------
# Auth handling
# --------------------------------------------------------------------------

def get_credentials(cookie_file: Optional[str]) -> str:
    """
    Resolve the .ROBLOSECURITY cookie value without hardcoding it anywhere.

    Priority order:
      1. --cookie-file <path>   (a plain-text file containing only the cookie value)
      2. ROBLOX_COOKIE environment variable
      3. Interactive, hidden prompt (getpass) -- nothing is echoed or logged.

    The cookie is kept only in memory for the life of the process.
    """
    if cookie_file:
        path = Path(cookie_file).expanduser()
        if not path.is_file():
            raise SystemExit(f"--cookie-file points to a file that does not exist: {path}")
        value = path.read_text(encoding="utf-8").strip()
        if not value:
            raise SystemExit(f"--cookie-file {path} is empty.")
        return value

    env_value = os.environ.get(COOKIE_ENV_VAR)
    if env_value:
        return env_value.strip()

    print(
        "No cookie supplied via --cookie-file or the ROBLOX_COOKIE environment "
        "variable.\nPaste your .ROBLOSECURITY cookie value below. It will not be "
        "echoed to the screen or written to disk by this tool.",
        file=sys.stderr,
    )
    value = getpass.getpass("ROBLOSECURITY cookie: ").strip()
    if not value:
        raise SystemExit("No cookie provided. Aborting.")
    return value


def build_session(roblosecurity: str) -> requests.Session:
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT, "Accept": "application/json"})
    session.cookies.set(".ROBLOSECURITY", roblosecurity, domain=".roblox.com")
    return session


def whoami(session: requests.Session) -> dict:
    resp = session.get(AUTH_CHECK_URL, timeout=15)
    if resp.status_code == 401:
        raise SystemExit(
            "Authentication failed (401). Your ROBLOSECURITY cookie is missing, "
            "malformed, or expired. Log into roblox.com in a browser, re-extract "
            "the cookie, and try again."
        )
    resp.raise_for_status()
    return resp.json()


# --------------------------------------------------------------------------
# HTTP helper with retry / backoff / rate-limit handling
# --------------------------------------------------------------------------

def request_with_retries(
    session: requests.Session,
    method: str,
    url: str,
    *,
    params: Optional[dict] = None,
    stream: bool = False,
    delay: float = DEFAULT_DELAY_SECONDS,
    context: str = "",
) -> requests.Response:
    last_exc: Optional[Exception] = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = session.request(method, url, params=params, stream=stream, timeout=30)
        except requests.RequestException as exc:
            last_exc = exc
            wait = min(2 ** attempt, 30)
            print(f"  [warn] network error on {context or url} ({exc}); "
                  f"retrying in {wait}s (attempt {attempt}/{MAX_RETRIES})", file=sys.stderr)
            time.sleep(wait)
            continue

        if resp.status_code == 401:
            raise SystemExit(
                "Session expired mid-run (401 Unauthorized). Re-authenticate "
                "(refresh your ROBLOSECURITY cookie) and re-run. Already-downloaded "
                "versions are untouched; use --resume to continue where you left off."
            )

        if resp.status_code == 403:
            # Could be a genuine permissions issue (you don't have edit access
            # to this place) rather than a transient error -- don't blindly retry.
            raise SystemExit(
                f"403 Forbidden on {context or url}.\n"
                "This usually means either:\n"
                "  - your account does not have edit access to this place, or\n"
                "  - the experimental history endpoint has changed its auth "
                "requirements.\n"
                f"Response body (truncated): {resp.text[:500]!r}"
            )

        if resp.status_code in RETRYABLE_STATUS:
            retry_after = resp.headers.get("Retry-After")
            wait = float(retry_after) if retry_after else min(2 ** attempt, 30)
            print(f"  [warn] HTTP {resp.status_code} on {context or url}; "
                  f"waiting {wait}s (attempt {attempt}/{MAX_RETRIES})", file=sys.stderr)
            time.sleep(wait)
            continue

        # Any other non-2xx: surface it clearly instead of guessing.
        if not resp.ok:
            raise SystemExit(
                f"Unexpected HTTP {resp.status_code} on {context or url}: "
                f"{resp.text[:500]!r}"
            )

        if delay:
            time.sleep(delay)
        return resp

    raise SystemExit(
        f"Giving up on {context or url} after {MAX_RETRIES} attempts. "
        f"Last error: {last_exc}"
    )


# --------------------------------------------------------------------------
# Place ID parsing
# --------------------------------------------------------------------------

def resolve_place_id(raw: str) -> str:
    raw = raw.strip()
    if raw.isdigit():
        return raw
    match = re.search(r"roblox\.com/games/(\d+)", raw)
    if match:
        return match.group(1)
    raise SystemExit(
        f"Could not extract a place ID from {raw!r}. Pass a numeric place ID "
        "or a URL like https://www.roblox.com/games/<id>/<name>."
    )


# --------------------------------------------------------------------------
# Version listing (defensive against the "Experimental" schema)
# --------------------------------------------------------------------------

@dataclass
class VersionEntry:
    version_number: int
    created: Optional[str]          # ISO 8601 string as returned by Roblox, verbatim
    raw: dict = field(default_factory=dict)  # full original record, for audit


def _first_present(d: dict, keys: Iterable[str]) -> Any:
    for k in keys:
        if k in d and d[k] is not None:
            return d[k]
    return None


def _normalize_version(raw: dict) -> Optional[VersionEntry]:
    """
    The place-version-history-api is marked Experimental by Roblox, meaning
    field names are not contractually guaranteed. Rather than hardcode one
    exact casing, check the plausible variants seen in Roblox's other APIs.
    """
    version = _first_present(
        raw, ["versionNumber", "VersionNumber", "version", "Version", "assetVersionNumber"]
    )
    created = _first_present(
        raw, ["created", "Created", "createdTime", "CreatedTime", "publishDate", "PublishDate"]
    )
    if version is None:
        return None
    try:
        version = int(version)
    except (TypeError, ValueError):
        return None
    return VersionEntry(version_number=version, created=created, raw=raw)


def _extract_list_from_response(payload: Any) -> list:
    """
    Defensively find the list of version records inside whatever top-level
    shape the endpoint returns (it may be a bare list, or an object with a
    'data'/'versions'/'items'/'PlaceVersions' key).
    """
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in ("data", "versions", "items", "PlaceVersions", "Versions", "results"):
            value = payload.get(key)
            if isinstance(value, list):
                return value
    return []


def _extract_cursor(payload: Any) -> Optional[str]:
    if not isinstance(payload, dict):
        return None
    for key in (
        "nextPageCursor", "NextPageCursor", "nextCursor", "cursor",
        "nextPageToken", "NextPageToken",
    ):
        value = payload.get(key)
        if value:
            return value
    return None


def list_all_versions(
    session: requests.Session, place_id: str, delay: float, raw_dump_path: Optional[Path] = None
) -> list[VersionEntry]:
    """
    Paginate through the history endpoint until exhausted. Every raw page is
    accumulated and (optionally) written to disk verbatim for auditability,
    since this endpoint's contract is not formally documented by Roblox.
    """
    versions: list[VersionEntry] = []
    seen_version_numbers: set[int] = set()
    raw_pages: list[Any] = []

    cursor: Optional[str] = None
    page = 0
    while True:
        page += 1
        params = {"maxRows": 100}
        if cursor:
            params["cursor"] = cursor

        resp = request_with_retries(
            session, "GET", HISTORY_URL.format(place_id=place_id),
            params=params, delay=delay, context=f"history page {page}",
        )
        try:
            payload = resp.json()
        except ValueError:
            raise SystemExit(
                f"History endpoint returned non-JSON on page {page}. "
                f"First 300 chars: {resp.text[:300]!r}"
            )
        raw_pages.append(payload)

        records = _extract_list_from_response(payload)
        if not records and page == 1:
            print(
                "  [warn] The history endpoint returned no recognizable version "
                "list on the first page. Dumping raw response for inspection.",
                file=sys.stderr,
            )

        new_this_page = 0
        for record in records:
            entry = _normalize_version(record)
            if entry is None:
                continue
            if entry.version_number in seen_version_numbers:
                continue
            seen_version_numbers.add(entry.version_number)
            versions.append(entry)
            new_this_page += 1

        cursor = _extract_cursor(payload)
        if not cursor or new_this_page == 0:
            break

    if raw_dump_path:
        raw_dump_path.parent.mkdir(parents=True, exist_ok=True)
        raw_dump_path.write_text(json.dumps(raw_pages, indent=2), encoding="utf-8")

    versions.sort(key=lambda v: v.version_number)

    if not versions:
        raise SystemExit(
            "No versions could be parsed from the history API response.\n"
            "This can happen if:\n"
            "  - the experimental endpoint's response schema has changed, or\n"
            "  - your account lacks edit access to this place.\n"
            f"{'Raw response saved to ' + str(raw_dump_path) if raw_dump_path else ''}\n"
            "Inspect the raw JSON and, if the schema changed, adjust "
            "_normalize_version()/_extract_list_from_response() accordingly."
        )
    return versions


# --------------------------------------------------------------------------
# Downloading a single version's .rbxl bytes
# --------------------------------------------------------------------------

def download_version_bytes(session: requests.Session, place_id: str, version: int, delay: float) -> bytes:
    meta_resp = request_with_retries(
        session, "GET", ASSET_VERSION_URL.format(place_id=place_id, version=version),
        delay=delay, context=f"asset-version metadata v{version}",
    )
    try:
        meta = meta_resp.json()
    except ValueError:
        raise SystemExit(
            f"assetdelivery did not return JSON for version {version}. "
            f"First 300 chars: {meta_resp.text[:300]!r}"
        )

    locations = meta.get("locations") or []
    location_url = None
    for loc in locations:
        if isinstance(loc, dict) and loc.get("location"):
            location_url = loc["location"]
            break
    if not location_url:
        raise SystemExit(
            f"No download location returned for version {version}. "
            f"Raw response: {json.dumps(meta)[:500]}"
        )

    content_resp = request_with_retries(
        session, "GET", location_url, stream=True, delay=delay,
        context=f"asset-version content v{version}",
    )
    return content_resp.content


# --------------------------------------------------------------------------
# Range / list parsing for --range and --versions
# --------------------------------------------------------------------------

def parse_selection(all_versions: list[int], range_arg: Optional[str], versions_arg: Optional[str],
                     select_all: bool) -> list[int]:
    if select_all:
        return all_versions
    selected: set[int] = set()
    if range_arg:
        m = re.match(r"^(\d+):(\d+)$", range_arg.strip())
        if not m:
            raise SystemExit(f"--range must look like START:END, got {range_arg!r}")
        start, end = int(m.group(1)), int(m.group(2))
        if start > end:
            start, end = end, start
        selected.update(v for v in all_versions if start <= v <= end)
    if versions_arg:
        for token in versions_arg.split(","):
            token = token.strip()
            if not token:
                continue
            if not token.isdigit():
                raise SystemExit(f"--versions must be a comma-separated list of integers, got {token!r}")
            selected.add(int(token))
    if not selected:
        raise SystemExit("No versions selected. Use --all, --range START:END, or --versions v1,v2,...")
    missing = selected - set(all_versions)
    if missing:
        print(f"  [warn] These requested versions were not found in history and will be skipped: "
              f"{sorted(missing)}", file=sys.stderr)
    return sorted(selected & set(all_versions))


# --------------------------------------------------------------------------
# Filesystem layout
# --------------------------------------------------------------------------

def safe_timestamp_for_filename(created: Optional[str]) -> str:
    if not created:
        return "unknown-timestamp"
    # Keep it filename-safe; do not reinterpret/convert timezone, just sanitize.
    return re.sub(r"[^0-9A-Za-z_+-]", "-", created)


def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_version(
    out_dir: Path,
    place_id: str,
    entry: VersionEntry,
    data: bytes,
    index: int,
) -> dict:
    folder = out_dir / f"{index:04d}"
    folder.mkdir(parents=True, exist_ok=True)

    ts = safe_timestamp_for_filename(entry.created)
    filename = f"version_{index:04d}_{ts}.rbxl"
    rbxl_path = folder / filename
    rbxl_path.write_bytes(data)

    metadata = {
        "place_id": place_id,
        "roblox_version_number": entry.version_number,   # authoritative Roblox version ID
        "roblox_created_timestamp": entry.created,        # verbatim from Roblox, never altered
        "sequence_index_in_this_run": index,
        "rbxl_filename": filename,
        "file_size_bytes": len(data),
        "sha256": sha256_of(data),
        "tool_downloaded_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_history_record_raw": entry.raw,
        "source_endpoints": {
            "history_list": HISTORY_URL.format(place_id=place_id),
            "content": ASSET_VERSION_URL.format(place_id=place_id, version=entry.version_number),
        },
    }
    (folder / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return {"folder": str(folder), "rbxl_path": str(rbxl_path), "metadata": metadata}


# --------------------------------------------------------------------------
# Stage 2: integration with the user's existing rbxl_script_extractor.py
# --------------------------------------------------------------------------

def preflight_check_extractor(parser_path: Path) -> None:
    """
    Fail fast, once, before looping over dozens of versions -- rather than
    having every single extraction attempt fail with the same root cause.
    """
    if not parser_path.is_file():
        raise SystemExit(f"--parser path does not exist: {parser_path}")

    dep_check = subprocess.run(
        [sys.executable, "-c", "import lz4.block"],
        capture_output=True, text=True,
    )
    if dep_check.returncode != 0:
        raise SystemExit(
            "rbxl_script_extractor.py requires the 'lz4' package, which is not "
            f"importable from {sys.executable}.\n"
            "Install it with:\n"
            "    pip install lz4\n"
            f"(underlying error: {dep_check.stderr.strip()[:300]})"
        )


def run_extractor(parser_path: Path, rbxl_path: Path, scripts_dir: Path) -> tuple[bool, str]:
    scripts_dir.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(
            [sys.executable, str(parser_path), str(rbxl_path), str(scripts_dir)],
            capture_output=True, text=True, timeout=600,
        )
    except subprocess.TimeoutExpired:
        return False, "Parser timed out after 600s."
    if result.returncode != 0:
        return False, f"Parser exited {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    return True, result.stdout


# --------------------------------------------------------------------------
# CLI subcommands
# --------------------------------------------------------------------------

def cmd_whoami(args: argparse.Namespace) -> None:
    cookie = get_credentials(args.cookie_file)
    session = build_session(cookie)
    info = whoami(session)
    print(json.dumps(info, indent=2))


def cmd_list(args: argparse.Namespace) -> None:
    place_id = resolve_place_id(args.place)
    cookie = get_credentials(args.cookie_file)
    session = build_session(cookie)
    whoami(session)  # fail fast with a clear message if auth is bad

    raw_dump = Path(args.out) / "history_raw.json" if args.out else None
    versions = list_all_versions(session, place_id, args.delay, raw_dump)

    print(f"\nFound {len(versions)} version(s) for place {place_id}:\n")
    print(f"{'VERSION':>8}  {'TIMESTAMP (as returned by Roblox)':<32}")
    print("-" * 44)
    for v in versions:
        print(f"{v.version_number:>8}  {v.created or 'unknown':<32}")

    if raw_dump:
        print(f"\nRaw API response saved to: {raw_dump}")


def cmd_download(args: argparse.Namespace) -> None:
    place_id = resolve_place_id(args.place)
    cookie = get_credentials(args.cookie_file)
    session = build_session(cookie)
    whoami(session)

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    raw_dump = out_dir / "history_raw.json"
    all_entries = list_all_versions(session, place_id, args.delay, raw_dump)
    all_numbers = [e.version_number for e in all_entries]
    by_number = {e.version_number: e for e in all_entries}

    selected = parse_selection(all_numbers, args.range, args.versions, args.all)
    print(f"\n{len(selected)} version(s) selected for download: {selected}\n")

    parser_path = Path(args.parser).expanduser() if args.parser else None
    if args.extract:
        if not parser_path:
            raise SystemExit("--extract was given but --parser path is missing.")
        preflight_check_extractor(parser_path)

    index_summary = []
    for i, version_number in enumerate(selected, start=1):
        entry = by_number[version_number]
        target_folder = out_dir / f"{i:04d}"
        marker = target_folder / "metadata.json"
        if marker.exists() and not args.overwrite:
            print(f"[{i}/{len(selected)}] version {version_number}: already downloaded, skipping "
                  f"(use --overwrite to re-fetch)")
            index_summary.append({"version": version_number, "status": "skipped-existing"})
            continue

        print(f"[{i}/{len(selected)}] Downloading version {version_number} "
              f"(created: {entry.created or 'unknown'}) ...")
        try:
            data = download_version_bytes(session, place_id, version_number, args.delay)
        except SystemExit as exc:
            print(f"  [error] {exc}", file=sys.stderr)
            index_summary.append({"version": version_number, "status": "download-failed", "error": str(exc)})
            continue

        written = write_version(out_dir, place_id, entry, data, i)
        print(f"  saved: {written['rbxl_path']}")
        record = {"version": version_number, "status": "downloaded", **written}

        if args.extract:
            scripts_dir = Path(written["folder"]) / "scripts"
            ok, output = run_extractor(parser_path, Path(written["rbxl_path"]), scripts_dir)
            if ok:
                print(f"  extracted scripts -> {scripts_dir}")
                record["extraction_status"] = "ok"
            else:
                print(f"  [error] extraction failed: {output}", file=sys.stderr)
                record["extraction_status"] = "failed"
                record["extraction_error"] = output

        index_summary.append(record)

    (out_dir / "index.json").write_text(json.dumps(index_summary, indent=2), encoding="utf-8")
    print(f"\nDone. Summary written to {out_dir / 'index.json'}")


# --------------------------------------------------------------------------
# Argument parser
# --------------------------------------------------------------------------

def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Bulk-download genuine historical Roblox place versions."
    )
    p.add_argument("--cookie-file", help="Path to a file containing only your .ROBLOSECURITY cookie value.")

    sub = p.add_subparsers(dest="command", required=True)

    p_who = sub.add_parser("whoami", help="Verify authentication works.")
    p_who.set_defaults(func=cmd_whoami)

    p_list = sub.add_parser("list", help="List available historical versions for a place.")
    p_list.add_argument("--place", required=True, help="Place ID or full roblox.com/games/... URL.")
    p_list.add_argument("--out", help="If set, also writes history_raw.json here for audit.")
    p_list.add_argument("--delay", type=float, default=DEFAULT_DELAY_SECONDS,
                         help="Seconds to sleep between requests (politeness/rate-limit avoidance).")
    p_list.set_defaults(func=cmd_list)

    p_dl = sub.add_parser("download", help="Download one, several, or all historical versions.")
    p_dl.add_argument("--place", required=True, help="Place ID or full roblox.com/games/... URL.")
    p_dl.add_argument("--out", required=True, help="Output directory (created if missing).")
    sel = p_dl.add_mutually_exclusive_group(required=True)
    sel.add_argument("--all", action="store_true", help="Download every version in history.")
    sel.add_argument("--range", help="Inclusive version range, e.g. 10:20")
    sel.add_argument("--versions", help="Comma-separated version numbers, e.g. 5,7,9")
    p_dl.add_argument("--delay", type=float, default=DEFAULT_DELAY_SECONDS,
                       help="Seconds to sleep between requests.")
    p_dl.add_argument("--overwrite", action="store_true", help="Re-download versions already present.")
    p_dl.add_argument("--extract", action="store_true",
                       help="After downloading, run the script extractor on each .rbxl.")
    p_dl.add_argument("--parser", help="Path to rbxl_script_extractor.py (required with --extract).")
    p_dl.set_defaults(func=cmd_download)

    return p


def main() -> None:
    parser = build_arg_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
