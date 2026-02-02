# Python Engine — Albert Script Runner

## Overview

The **python-engine** is the backend execution layer for the **Albert Script Runner** SwiftUI application.

It provides a **single, stable command-line interface (CLI)** that the macOS app invokes to perform operations against the **Albert API** using the **Albert Python SDK**.

SwiftUI never imports the SDK directly.  
All Albert logic lives in Python and is executed via subprocess calls.

---

## High-Level Architecture

SwiftUI App  
→ PythonRunner (Swift)  
→ engine.py (CLI entrypoint)  
→ feature modules (users.py, locations.py)  
→ Albert Python SDK  
→ Albert API

---

## engine.py — CLI Entrypoint

`engine.py` is the **only file Swift ever executes**.

Responsibilities:
- Parse CLI arguments
- Resolve feature helpers safely
- Execute SDK calls
- Emit structured output for Swift

---

## Supported Commands

### download-users

```
python engine.py download-users \
  --token <JWT> \
  --base-url https://sandbox.albertinvent.com \
  --out users.xlsx
```

Downloads all users and writes an Excel file.

Output:
```
OK:WROTE:/absolute/path/users.xlsx
```

---

### list-locations

```
python engine.py list-locations \
  --token <JWT> \
  --base-url https://sandbox.albertinvent.com
```

Fetches all locations, sorted by numeric LOC ID.

Output (stdout):
```json
[
  {
    "id": "LOC1",
    "name": "Example Location",
    "address": "...",
    "country": "US",
    "latitude": 40.0,
    "longitude": -74.0
  }
]
```

Optional:
```
--out locations.json
```

---

### upload-locations

```
python engine.py upload-locations \
  --token <JWT> \
  --base-url https://sandbox.albertinvent.com \
  --in locations.json
```

Uploads multiple locations with **partial success support**.

Input JSON:
```json
[
  {
    "name": "New Site",
    "address": "123 Road",
    "country": "US",
    "latitude": 40.1,
    "longitude": -74.2
  }
]
```

Output JSON:
```json
[
  {
    "name": "New Site",
    "status": "created",
    "id": "LOC123",
    "error": null
  },
  {
    "name": "Bad Location",
    "status": "failed",
    "id": null,
    "error": "API validation error"
  }
]
```

---

## locations.py

Contains all location-related logic:

- Fetch + sort locations
- Convert UI inputs into `Location` objects
- Create / update locations
- Preserve partial success
- Handle SDK compatibility differences

### Partial Success Contract

- Each row is processed independently
- One failure does **not** abort the batch
- API errors are returned verbatim
- Swift decides how to display results

---

## Error Handling

| Condition | Behavior |
|--------|---------|
| Row-level API error | Returned in JSON |
| Invalid input | Non-zero exit + stderr |
| SDK import failure | Non-zero exit + stderr |
| Programmer error | Traceback printed |

Swift treats:
- `stdout` → success path
- `stderr` → surfaced error

---

## Design Goals

- Keep SwiftUI free of SDK logic
- Centralize all Albert API calls
- Support bulk operations safely
- Remain resilient to SDK changes
- Provide predictable machine-readable output

---

## Bundled Python Runtime

This project is designed to ship with a standalone Python runtime inside the app bundle.

Expected locations at runtime:
- `Contents/Resources/python-runtime/bin/python3` (preferred)
- `Contents/Resources/python-engine/python-runtime/bin/python3` (alternate when bundling everything under python-engine)
- `Contents/Resources/python-engine/.venv/bin/python` (fallback, not standalone)

Notes:
- A `.venv` is not a full runtime and often symlinks to a system Python. That will not be portable.
- For portability, copy a real runtime into `python-engine/python-runtime` and include it in the app bundle.
- Make sure your Xcode Run Script copies the runtime folder into `Contents/Resources`.

---

## Expected Evolution

Future commands may include:
- update-locations
- migration workflows
- validation-only dry runs
- debug / verbose modes

This engine is the **single source of truth** for all Albert automation used by the app.
