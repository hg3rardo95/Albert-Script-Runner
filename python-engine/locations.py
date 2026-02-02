from __future__ import annotations

import re

from albert import Albert
from albert.resources.locations import Location


def _location_exists(client: Albert, loc: Location):
    """SDK-compat helper.

    Different Albert SDK versions expose existence checks with different names.
    We support both:
      - client.locations.exists(location=loc)
      - client.locations.location_exists(location=loc)
    """

    locations_api = client.locations

    if hasattr(locations_api, "exists"):
        return locations_api.exists(location=loc)

    if hasattr(locations_api, "location_exists"):
        return locations_api.location_exists(location=loc)

    raise AttributeError(
        "Albert SDK locations client has no 'exists' or 'location_exists' method"
    )


def getAllLoc(base_url: str, token: str):
    """Return all locations sorted by their LOC ID (numeric when possible)."""
    client = Albert(base_url=base_url, token=token)
    locs = list(client.locations.get_all())

    def _sort_key(loc):
        loc_id = getattr(loc, "id", "") or ""

        # Prefer sorting by trailing digits (e.g., LOC1, LOC10, LOC200)
        m = re.search(r"(\d+)$", loc_id)
        if m:
            return (0, int(m.group(1)), loc_id)

        # Non-standard / missing IDs go after
        return (1, loc_id)

    locs.sort(key=_sort_key)
    return locs


def get_all_locations(base_url: str, token: str):
    """Alias for getAllLoc (preferred snake_case name for python-engine)."""
    return getAllLoc(base_url, token)


def collectLocationData(inputs, locSelectedAction):
    """Build Location objects from UI inputs.

    Backward compatible:
      - Old PySide/Tk-style: inputs is list[dict] and values may have `.get()`
      - New SwiftUI: inputs is list[dict] with plain string/number values

    Expected keys per entry:
      - name, address, country, latitude, longitude
      - id or ID (required for update)
    """

    def safe_get(entry_fields, field):
        # accept both id/ID
        if field == "id":
            if "id" in entry_fields:
                field = "id"
            elif "ID" in entry_fields:
                field = "ID"

        if field not in entry_fields:
            return ""

        val = entry_fields[field]

        # Entry-like object (legacy)
        if hasattr(val, "get"):
            try:
                return (val.get() or "").strip()
            except Exception:
                return ""

        # Plain value (Swift)
        return (str(val) if val is not None else "").strip()

    def to_float(v, default=0.0):
        try:
            if v is None or v == "":
                return default
            return float(v)
        except Exception:
            return default

    locations: list[Location] = []

    for entry_fields in inputs:
        name = safe_get(entry_fields, "name")
        address = safe_get(entry_fields, "address")
        country = safe_get(entry_fields, "country")
        latitude = to_float(safe_get(entry_fields, "latitude"), 0.0)
        longitude = to_float(safe_get(entry_fields, "longitude"), 0.0)

        if locSelectedAction == "Upload New Location":
            loc = Location(
                name=name,
                address=address,
                country=country,
                latitude=latitude,
                longitude=longitude,
            )
            locations.append(loc)

        elif locSelectedAction == "Update Existing Location":
            loc_id = safe_get(entry_fields, "id")
            if not loc_id:
                # Skip updates with missing ID (matches old behavior)
                continue

            loc = Location(
                id=loc_id,
                name=name,
                address=address,
                country=country,
                latitude=latitude,
                longitude=longitude,
            )
            locations.append(loc)

        else:
            raise ValueError(
                "locSelectedAction must be 'Upload New Location' or 'Update Existing Location'"
            )

    return locations


def addNewLoc(base_url: str, token: str, locations: list[Location]):
    """Accepts a list of Location objects and submits them to the Albert API."""
    client = Albert(base_url=base_url, token=token)

    completionMessage: list[str] = []

    for loc in locations:
        try:
            existing = _location_exists(client, loc)
            if existing:
                completionMessage.append(
                    f"Location already exists: {loc.name} (ID:{existing.id})"
                )
            else:
                created = client.locations.create(location=loc)
                completionMessage.append(
                    f"✅ Created location: {loc.name} (ID: {created.id})"
                )
        except Exception as e:
            completionMessage.append(f"🚫 Failed to process location {loc.name}: {e}")

    return completionMessage


def updateLoc(base_url: str, token: str, locations: list[Location]):
    """Iterate through a list of Location objects and update them one by one."""
    client = Albert(base_url=base_url, token=token)
    completedMessage: list[str] = []

    for loc in locations:
        try:
            if not getattr(loc, "id", None):
                completedMessage.append(
                    f"🚫 Skipping {loc.name}: Missing ID for update."
                )
                continue

            location = client.locations.get_by_id(id=loc.id)
            location.name = loc.name
            location.address = loc.address
            location.country = loc.country
            location.latitude = loc.latitude
            location.longitude = loc.longitude

            updated = client.locations.update(location=location)
            completedMessage.append(
                f"✅ Updated location: {updated.name} (ID: {updated.id})"
            )
        except Exception as e:
            completedMessage.append(f"🚫 Failed to update location {loc.name}: {e}")

    return completedMessage


# Helper for SwiftUI: upload new locations and return structured results (partial success)
def upload_new_locations(base_url: str, token: str, inputs: list[dict]):
    """Upload new locations (partial success) and return structured results.

    This is designed for the SwiftUI app. Swift sends raw input rows (dicts).
    We convert rows into Albert `Location` objects in Python, then call the SDK.

    Returns a list of dicts like:
      {"name": str, "status": "created"|"exists"|"failed", "id": str|None, "error": str|None}

    Only the "failed" entries will have a non-empty "error".
    """

    # Build Location objects using the existing conversion logic
    locations = collectLocationData(inputs, "Upload New Location")

    client = Albert(base_url=base_url, token=token)

    results: list[dict] = []

    for loc in locations:
        name = getattr(loc, "name", "") or ""
        try:
            existing = _location_exists(client, loc)
            if existing:
                results.append(
                    {
                        "name": name,
                        "status": "exists",
                        "id": getattr(existing, "id", None),
                        "error": None,
                    }
                )
            else:
                created = client.locations.create(location=loc)
                results.append(
                    {
                        "name": name,
                        "status": "created",
                        "id": getattr(created, "id", None),
                        "error": None,
                    }
                )
        except Exception as e:
            # Preserve partial success; report which location failed and the API error
            results.append(
                {
                    "name": name,
                    "status": "failed",
                    "id": getattr(loc, "id", None),
                    "error": str(e),
                }
            )

    return results


# Helper for SwiftUI: update existing locations and return structured results (partial success)
def update_existing_locations(base_url: str, token: str, inputs: list[dict]):
    """Update existing locations (partial success) and return structured results.

    Swift sends raw input rows (dicts). For updates, each row MUST include an ID.

    Expected keys per row:
      - id (or ID)
      - name, address, country, latitude, longitude (optional; blank fields are treated as "leave unchanged")

    Returns a list of dicts like:
      {
        "index": int,
        "id": str|None,
        "name": str|None,
        "status": "updated"|"failed",
        "error": str|None
      }

    Only the "failed" entries will have a non-empty "error".
    """

    client = Albert(base_url=base_url, token=token)

    def _safe_get(row: dict, key: str) -> str:
        # accept both id/ID
        if key == "id":
            if "id" in row:
                key = "id"
            elif "ID" in row:
                key = "ID"
        val = row.get(key, "")
        if val is None:
            return ""
        return str(val).strip()

    def _opt_float(s: str):
        s = (s or "").strip()
        if s == "":
            return None
        try:
            return float(s)
        except Exception:
            raise ValueError(f"Invalid number: {s}")

    results: list[dict] = []

    for i, row in enumerate(inputs):
        loc_id = _safe_get(row, "id")
        name = _safe_get(row, "name")
        address = _safe_get(row, "address")
        country = _safe_get(row, "country")
        lat_s = _safe_get(row, "latitude")
        lon_s = _safe_get(row, "longitude")

        result = {
            "index": i,
            "id": loc_id or None,
            "name": name or None,
            "status": "failed",
            "error": None,
        }

        try:
            if not loc_id:
                raise ValueError("Missing required field: id")

            # Fetch server object (also validates ID)
            server_loc = client.locations.get_by_id(id=loc_id)

            # Only overwrite fields that were actually provided (non-blank)
            if name:
                server_loc.name = name
            if address:
                server_loc.address = address
            if country:
                server_loc.country = country

            lat = _opt_float(lat_s)
            lon = _opt_float(lon_s)
            if lat is not None:
                server_loc.latitude = lat
            if lon is not None:
                server_loc.longitude = lon

            updated = client.locations.update(location=server_loc)

            result["status"] = "updated"
            result["id"] = getattr(updated, "id", loc_id)
            result["name"] = getattr(updated, "name", name) or name or None
            result["error"] = None

        except Exception as e:
            result["status"] = "failed"
            result["error"] = str(e)

        results.append(result)

    return results
