#!/usr/bin/env python3
"""
Roblox historical place-version downloader (cookie-rotation aware).

Workflow:
  1. Authenticate with a locally supplied .ROBLOSECURITY cookie.
  2. Force Roblox to rotate/refresh the session cookie when possible.
  3. Verify the authenticated account.
  4. List historical place versions from Roblox's experimental history API.
  5. Download each selected historical version through Asset Delivery.
  6. Optionally run rbxl_script_extractor.py on every downloaded place.

The script never publishes/restores/modifies a Roblox place. Download operations
are GETs, while the session-refresh endpoint is an authentication/session action.
The cookie is never printed or written to disk.
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
    print("This tool requires requests. Install with: python -m pip install requests", file=sys.stderr)
    raise SystemExit(1)

HISTORY_URL = "https://apis.roblox.com/place-version-history-api/v1/{place_id}/history"
ASSET_VERSION_URL = "https://assetdelivery.roblox.com/v2/assetId/{place_id}/version/{version}"
WHOAMI_URL = "https://users.roblox.com/v1/users/authenticated"
REFRESH_URLS = [
    "https://auth.roblox.com/v2/session/refresh",  # current documented endpoint
    "https://auth.roblox.com/v1/session/refresh",  # older/legacy endpoint mentioned by Roblox staff
]
USER_AGENT = "roblox-version-downloader/2.0 (+personal archival tool)"
COOKIE_ENV_VAR = "ROBLOX_COOKIE"
DEFAULT_DELAY_SECONDS = 1.25
MAX_RETRIES = 6
RETRYABLE_STATUS = {429, 500, 502, 503, 504}


def get_credentials(cookie_file: Optional[str]) -> str:
    if cookie_file:
        path = Path(cookie_file).expanduser()
        if not path.is_file():
            raise SystemExit(f"Cookie file does not exist: {path}")
        value = path.read_text(encoding="utf-8").strip()
        if not value:
            raise SystemExit(f"Cookie file is empty: {path}")
        return value
    env_value = os.environ.get(COOKIE_ENV_VAR)
    if env_value:
        return env_value.strip()
    value = getpass.getpass("ROBLOSECURITY cookie (hidden input): ").strip()
    if not value:
        raise SystemExit("No cookie provided. Aborting.")
    return value


def build_session(cookie: str) -> requests.Session:
    s = requests.Session()
    s.headers.update({"User-Agent": USER_AGENT, "Accept": "application/json"})
    # Host-only cookie is safest here; Roblox will receive it on roblox.com subdomains
    # only if the server/domain rules allow it. Also add .roblox.com explicitly below.
    s.cookies.set(".ROBLOSECURITY", cookie, domain=".roblox.com", path="/")
    return s


def cookie_present(session: requests.Session) -> bool:
    return any(c.name == ".ROBLOSECURITY" and bool(c.value) for c in session.cookies)


def cookie_length(session: requests.Session) -> int:
    for c in session.cookies:
        if c.name == ".ROBLOSECURITY":
            return len(c.value)
    return 0


def request_with_retries(
    session: requests.Session,
    method: str,
    url: str,
    *,
    params: Optional[dict] = None,
    headers: Optional[dict] = None,
    data: Any = None,
    stream: bool = False,
    delay: float = 0,
    context: str = "",
) -> requests.Response:
    last_exc: Optional[Exception] = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = session.request(
                method, url, params=params, headers=headers, data=data,
                stream=stream, timeout=60
            )
        except requests.RequestException as exc:
            last_exc = exc
            wait = min(2 ** attempt, 30)
            print(f"[warn] network error on {context or url}; retrying in {wait}s "
                  f"(attempt {attempt}/{MAX_RETRIES})", file=sys.stderr)
            time.sleep(wait)
            continue

        if resp.status_code in RETRYABLE_STATUS:
            retry_after = resp.headers.get("Retry-After")
            try:
                wait = float(retry_after) if retry_after else min(2 ** attempt, 30)
            except ValueError:
                wait = min(2 ** attempt, 30)
            print(f"[warn] HTTP {resp.status_code} on {context or url}; waiting {wait}s "
                  f"(attempt {attempt}/{MAX_RETRIES})", file=sys.stderr)
            time.sleep(wait)
            continue

        if delay:
            time.sleep(delay)
        return resp
    raise SystemExit(f"Giving up on {context or url} after {MAX_RETRIES} attempts. Last error: {last_exc}")


def extract_cookie_from_set_cookie(response: requests.Response) -> Optional[str]:
    """Return a new .ROBLOSECURITY value if this response explicitly set one."""
    # Requests usually updates response/session cookie jars automatically.
    for cookie in response.cookies:
        if cookie.name == ".ROBLOSECURITY" and cookie.value:
            return cookie.value
    return None


def csrf_token_from_response(response: requests.Response) -> Optional[str]:
    return response.headers.get("x-csrf-token") or response.headers.get("X-CSRF-TOKEN")


def refresh_session(session: requests.Session) -> bool:
    """
    Ask Roblox to rotate the current session cookie.

    Roblox's current Creator Hub docs list /v2/session/refresh. Roblox staff
    previously described /v1/session/refresh as the cookie-rotation workaround,
    so /v2 is tried first with /v1 as a fallback.

    The endpoint can respond 403 with an X-CSRF-TOKEN challenge. We retry once
    with that token, without ever printing it.
    """
    for url in REFRESH_URLS:
        try:
            resp = session.post(url, json=None, timeout=30)
        except requests.RequestException:
            continue

        new_cookie = extract_cookie_from_set_cookie(resp)
        if new_cookie:
            session.cookies.set(".ROBLOSECURITY", new_cookie, domain=".roblox.com", path="/")

        if resp.status_code in (200, 204):
            return cookie_present(session)

        if resp.status_code == 403:
            token = csrf_token_from_response(resp)
            if token:
                try:
                    resp2 = session.post(url, headers={"X-CSRF-TOKEN": token}, json=None, timeout=30)
                except requests.RequestException:
                    resp2 = None
                if resp2 is not None:
                    new_cookie = extract_cookie_from_set_cookie(resp2)
                    if new_cookie:
                        session.cookies.set(".ROBLOSECURITY", new_cookie, domain=".roblox.com", path="/")
                    if resp2.status_code in (200, 204):
                        return cookie_present(session)
        # A different 4xx may mean this version of the endpoint isn't usable.
    return False


def whoami(session: requests.Session) -> dict:
    resp = request_with_retries(session, "GET", WHOAMI_URL, context="authentication check")
    if resp.status_code == 401:
        # Try to rotate the cookie once, then retry authentication.
        if refresh_session(session):
            resp = request_with_retries(session, "GET", WHOAMI_URL, context="authentication check after refresh")
    if resp.status_code == 401:
        raise SystemExit(
            "Authentication failed (401). Roblox rejected the supplied .ROBLOSECURITY "
            "cookie even after the session-refresh attempt. Re-copy a fresh cookie from "
            "your currently logged-in Roblox browser session and try again."
        )
    resp.raise_for_status()
    return resp.json()


def resolve_place_id(raw: str) -> str:
    raw = raw.strip()
    if raw.isdigit():
        return raw
    match = re.search(r"roblox\.com/(?:games|game-pass)/?(\d+)", raw)
    if match:
        return match.group(1)
    match = re.search(r"roblox\.com/games/(\d+)", raw)
    if match:
        return match.group(1)
    raise SystemExit(
        f"Could not extract a place ID from {raw!r}. Pass a numeric place ID or a Roblox game URL."
    )


@dataclass
class VersionEntry:
    version_number: int
    created: Optional[str]
    raw: dict = field(default_factory=dict)


def _first_present(d: dict, keys: Iterable[str]) -> Any:
    for k in keys:
        if k in d and d[k] is not None:
            return d[k]
    return None


def _normalize_version(raw: dict) -> Optional[VersionEntry]:
    version = _first_present(raw, [
        "versionNumber", "VersionNumber", "version", "Version", "assetVersionNumber",
    ])
    created = _first_present(raw, [
        "created", "Created", "createdTime", "CreatedTime", "publishDate", "PublishDate",
        "createdAt", "CreatedAt", "timestamp", "Timestamp",
    ])
    if version is None:
        return None
    try:
        v = int(version)
    except (TypeError, ValueError):
        return None
    return VersionEntry(v, None if created is None else str(created), raw)


def _extract_list(payload: Any) -> list:
    """Extract version records from the actual history response shape.

    Roblox currently returns an outer JSON array whose elements are page objects,
    and each page object contains a ``placeVersions`` array. We also retain
    compatibility with the alternative object/list shapes used by earlier
    revisions of this script.
    """
    if isinstance(payload, list):
        # Current shape: [ {"nextCursor": ..., "placeVersions": [...] } ]
        combined: list = []
        for item in payload:
            if isinstance(item, dict):
                for key in (
                    "placeVersions", "PlaceVersions", "versions", "Versions",
                    "data", "items", "results"
                ):
                    value = item.get(key)
                    if isinstance(value, list):
                        combined.extend(value)
        # Fallback: bare list of version records.
        return combined if combined else payload

    if isinstance(payload, dict):
        for key in (
            "placeVersions", "PlaceVersions", "data", "versions", "Versions",
            "items", "results"
        ):
            value = payload.get(key)
            if isinstance(value, list):
                return value
    return []


def _extract_cursor(payload: Any) -> Optional[str]:
    """Extract pagination cursor from either the current array-wrapped response
    or an object response.
    """
    candidates = payload if isinstance(payload, list) else [payload]
    for item in candidates:
        if not isinstance(item, dict):
            continue
        for key in (
            "nextCursor", "NextCursor", "nextPageCursor", "NextPageCursor",
            "nextCursorToken", "nextPageToken", "NextPageToken", "cursor"
        ):
            value = item.get(key)
            if value:
                return str(value)
    return None


def list_all_versions(session: requests.Session, place_id: str, delay: float, raw_path: Optional[Path]) -> list[VersionEntry]:
    versions: list[VersionEntry] = []
    seen: set[int] = set()
    raw_pages: list[Any] = []
    cursor = None
    page = 0

    while True:
        page += 1
        params = {"maxRows": 100}
        if cursor:
            params["cursor"] = cursor
        resp = request_with_retries(
            session, "GET", HISTORY_URL.format(place_id=place_id),
            params=params, delay=delay, context=f"history page {page}"
        )
        if resp.status_code == 401:
            # Refresh once if the session rotates/ages during a long run.
            if refresh_session(session):
                resp = request_with_retries(
                    session, "GET", HISTORY_URL.format(place_id=place_id),
                    params=params, delay=delay, context=f"history page {page} after refresh"
                )
        if resp.status_code == 403:
            raise SystemExit(
                f"403 Forbidden on history page {page}. The authenticated account may not have "
                "edit access to this place, or Roblox may have changed the experimental endpoint."
            )
        if not resp.ok:
            raise SystemExit(f"HTTP {resp.status_code} on history page {page}: {resp.text[:500]!r}")
        try:
            payload = resp.json()
        except ValueError:
            raise SystemExit(f"History endpoint returned non-JSON. First 500 chars: {resp.text[:500]!r}")

        raw_pages.append(payload)
        records = _extract_list(payload)
        new_count = 0
        for record in records:
            if not isinstance(record, dict):
                continue
            entry = _normalize_version(record)
            if entry and entry.version_number not in seen:
                seen.add(entry.version_number)
                versions.append(entry)
                new_count += 1
        cursor = _extract_cursor(payload)
        if not cursor or new_count == 0:
            break

    if raw_path:
        raw_path.parent.mkdir(parents=True, exist_ok=True)
        raw_path.write_text(json.dumps(raw_pages, indent=2, ensure_ascii=False), encoding="utf-8")

    versions.sort(key=lambda x: x.version_number)
    if not versions:
        raise SystemExit(
            "No versions could be parsed. The raw API response has been saved; inspect it for a schema change."
        )
    return versions


def download_version_bytes(session: requests.Session, place_id: str, version: int, delay: float) -> tuple[bytes, dict]:
    meta_resp = request_with_retries(
        session, "GET", ASSET_VERSION_URL.format(place_id=place_id, version=version),
        delay=delay, context=f"asset metadata v{version}"
    )
    if meta_resp.status_code == 401 and refresh_session(session):
        meta_resp = request_with_retries(
            session, "GET", ASSET_VERSION_URL.format(place_id=place_id, version=version),
            delay=delay, context=f"asset metadata v{version} after refresh"
        )
    if not meta_resp.ok:
        raise SystemExit(f"HTTP {meta_resp.status_code} getting asset metadata v{version}: {meta_resp.text[:500]!r}")
    try:
        meta = meta_resp.json()
    except ValueError:
        raise SystemExit(f"Asset Delivery returned non-JSON for v{version}: {meta_resp.text[:500]!r}")
    locations = meta.get("locations") or []
    location_url = next((x.get("location") for x in locations if isinstance(x, dict) and x.get("location")), None)
    if not location_url:
        raise SystemExit(f"No download location returned for version {version}. Raw: {json.dumps(meta)[:500]}")
    content_resp = request_with_retries(
        session, "GET", location_url, stream=True, delay=delay, context=f"asset content v{version}"
    )
    if not content_resp.ok:
        raise SystemExit(f"HTTP {content_resp.status_code} downloading v{version}: {content_resp.text[:500]!r}")
    return content_resp.content, meta


def parse_selection(all_versions: list[int], range_arg: Optional[str], versions_arg: Optional[str], select_all: bool) -> list[int]:
    if select_all:
        return all_versions
    selected: set[int] = set()
    if range_arg:
        m = re.fullmatch(r"(\d+):(\d+)", range_arg.strip())
        if not m:
            raise SystemExit("--range must be START:END")
        a, b = map(int, m.groups())
        if a > b:
            a, b = b, a
        selected.update(v for v in all_versions if a <= v <= b)
    if versions_arg:
        for token in versions_arg.split(","):
            token = token.strip()
            if token:
                if not token.isdigit():
                    raise SystemExit("--versions must be a comma-separated list of integers")
                selected.add(int(token))
    if not selected:
        raise SystemExit("No versions selected. Use --all, --range START:END, or --versions v1,v2,...")
    missing = selected - set(all_versions)
    if missing:
        print(f"[warn] Requested versions not found and skipped: {sorted(missing)}", file=sys.stderr)
    return sorted(selected & set(all_versions))


def safe_timestamp(created: Optional[str]) -> str:
    return re.sub(r"[^0-9A-Za-z_+-]", "-", created) if created else "unknown-timestamp"


def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run_extractor(parser_path: Path, rbxl_path: Path, scripts_dir: Path) -> tuple[bool, str]:
    scripts_dir.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(
            [sys.executable, str(parser_path), str(rbxl_path), str(scripts_dir)],
            capture_output=True, text=True, timeout=600,
        )
    except subprocess.TimeoutExpired:
        return False, "Parser timed out after 600 seconds."
    if result.returncode != 0:
        return False, f"Parser exited {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    return True, result.stdout


def write_version(out_dir: Path, place_id: str, entry: VersionEntry, data: bytes, index: int, asset_meta: dict) -> dict:
    folder = out_dir / f"{index:04d}"
    folder.mkdir(parents=True, exist_ok=True)
    filename = f"version_{index:04d}_{safe_timestamp(entry.created)}.rbxl"
    path = folder / filename
    path.write_bytes(data)
    metadata = {
        "place_id": place_id,
        "roblox_version_number": entry.version_number,
        "roblox_created_timestamp": entry.created,
        "sequence_index_in_this_run": index,
        "rbxl_filename": filename,
        "file_size_bytes": len(data),
        "sha256": sha256_of(data),
        "tool_downloaded_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_history_record_raw": entry.raw,
        "asset_delivery_response_raw": asset_meta,
        "source_endpoints": {
            "history_list": HISTORY_URL.format(place_id=place_id),
            "content": ASSET_VERSION_URL.format(place_id=place_id, version=entry.version_number),
        },
    }
    (folder / "metadata.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    return {"folder": str(folder), "rbxl_path": str(path), "metadata": metadata}


def cmd_whoami(args: argparse.Namespace) -> None:
    cookie = get_credentials(args.cookie_file)
    session = build_session(cookie)
    print(f"Cookie present: {cookie_present(session)}")
    print(f"Cookie length: {len(cookie)}")
    if args.refresh:
        ok = refresh_session(session)
        print(f"Session refresh: {'success' if ok else 'not confirmed'}")
    info = whoami(session)
    print(json.dumps({k: info.get(k) for k in ("id", "name", "displayName") if k in info}, indent=2))


def cmd_list(args: argparse.Namespace) -> None:
    place_id = resolve_place_id(args.place)
    cookie = get_credentials(args.cookie_file)
    session = build_session(cookie)
    info = whoami(session)
    print(f"Authenticated as: {info.get('name') or info.get('displayName') or info.get('id', '?')}")
    raw_dump = Path(args.out) / "history_raw.json" if args.out else None
    versions = list_all_versions(session, place_id, args.delay, raw_dump)
    print(f"\nFound {len(versions)} version(s) for place {place_id}:\n")
    print(f"{'VERSION':>8}  {'TIMESTAMP (Roblox)':<32}")
    print("-" * 44)
    for v in versions:
        print(f"{v.version_number:>8}  {(v.created or 'unknown'):<32}")
    if raw_dump:
        print(f"\nRaw API response saved to: {raw_dump}")


def cmd_download(args: argparse.Namespace) -> None:
    place_id = resolve_place_id(args.place)
    cookie = get_credentials(args.cookie_file)
    session = build_session(cookie)
    info = whoami(session)
    print(f"Authenticated as: {info.get('name') or info.get('displayName') or info.get('id', '?')}")
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    all_entries = list_all_versions(session, place_id, args.delay, out_dir / "history_raw.json")
    by_number = {e.version_number: e for e in all_entries}
    selected = parse_selection(sorted(by_number), args.range, args.versions, args.all)
    print(f"\n{len(selected)} version(s) selected: {selected}\n")

    parser_path = Path(args.parser).expanduser() if args.parser else None
    if args.extract and (not parser_path or not parser_path.is_file()):
        raise SystemExit(f"--extract requires a valid --parser path; got {parser_path}")

    summary = []
    for i, version_number in enumerate(selected, 1):
        entry = by_number[version_number]
        target_folder = out_dir / f"{i:04d}"
        marker = target_folder / "metadata.json"
        if marker.exists() and not args.overwrite:
            print(f"[{i}/{len(selected)}] v{version_number}: already exists, skipping")
            summary.append({"version": version_number, "status": "skipped-existing"})
            continue
        print(f"[{i}/{len(selected)}] Downloading v{version_number} ({entry.created or 'unknown timestamp'})...")
        try:
            data, asset_meta = download_version_bytes(session, place_id, version_number, args.delay)
            written = write_version(out_dir, place_id, entry, data, i, asset_meta)
            print(f"  saved: {written['rbxl_path']}")
            record = {"version": version_number, "status": "downloaded", **written}
            if args.extract:
                scripts_dir = Path(written["folder"]) / "scripts"
                ok, output = run_extractor(parser_path, Path(written["rbxl_path"]), scripts_dir)
                record["extraction_status"] = "ok" if ok else "failed"
                if ok:
                    print(f"  extracted scripts -> {scripts_dir}")
                else:
                    print(f"  [error] extraction failed: {output}", file=sys.stderr)
                    record["extraction_error"] = output
            summary.append(record)
        except SystemExit as exc:
            print(f"  [error] {exc}", file=sys.stderr)
            summary.append({"version": version_number, "status": "download-failed", "error": str(exc)})

    (out_dir / "index.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nDone. Summary: {out_dir / 'index.json'}")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Bulk-download genuine Roblox historical place versions.")
    p.add_argument("--cookie-file", help="Path to a file containing only the .ROBLOSECURITY value.")
    sub = p.add_subparsers(dest="command", required=True)

    pw = sub.add_parser("whoami", help="Verify authentication")
    pw.add_argument("--refresh", action="store_true", help="Force a Roblox session refresh before auth check")
    pw.set_defaults(func=cmd_whoami)

    pl = sub.add_parser("list", help="List historical versions")
    pl.add_argument("--place", required=True)
    pl.add_argument("--out")
    pl.add_argument("--delay", type=float, default=DEFAULT_DELAY_SECONDS)
    pl.set_defaults(func=cmd_list)

    pd = sub.add_parser("download", help="Download historical versions")
    pd.add_argument("--place", required=True)
    pd.add_argument("--out", required=True)
    sel = pd.add_mutually_exclusive_group(required=True)
    sel.add_argument("--all", action="store_true")
    sel.add_argument("--range")
    sel.add_argument("--versions")
    pd.add_argument("--delay", type=float, default=DEFAULT_DELAY_SECONDS)
    pd.add_argument("--overwrite", action="store_true")
    pd.add_argument("--extract", action="store_true")
    pd.add_argument("--parser")
    pd.set_defaults(func=cmd_download)
    return p


def main() -> None:
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
