from __future__ import annotations

from typing import Any
from copy import copy
from urllib.parse import quote

import os
import pandas as pd
import requests
import openpyxl

from albert import Albert
from albert.resources.custom_templates import TemplateCategory


_TEMPLATE_SHEET_NAMES = {
    TemplateCategory.PROPERTY: "Property Task Templates",
    TemplateCategory.BATCH: "Batch Task Templates",
    TemplateCategory.GENERAL: "General Task Templates",
    TemplateCategory.SHEET: "Sheet Templates",
    TemplateCategory.NOTEBOOK: "Notebook Templates",
}

_EXPECTED_HEADERS = {
    "DTs": ["Data Template Name", "DT ID", "Migrate?", "Migration Complete?", "Notes (optional)"],
    "PGs": ["Parameter Group Name", "PG ID", "Migrate?", "Migration Complete?", "Notes (optional)"],
    "Batch Task Templates": ["Template Name", "Migrate?", "Migration Complete?", "Notes (optional)"],
    "Property Task Templates": ["Template Name", "Migrate?", "Migration Complete?", "Notes (optional)"],
    "Notebook Templates": ["Notebook Template Name", "Migrate?", "Migration Complete?", "Notes (optional)"],
    "General Task Templates": ["Template Name", "Migrate?", "Migration Complete?", "Notes (optional)"],
    "Sheet Templates": ["Template Name", "Migrate?", "Migration Complete?", "Notes (optional)"],
}
_ALBERT_ID_HEADER = "Albert ID"
_ALBERT_ID_OPTIONAL_SHEETS = {
    "DTs",
    "PGs",
    "Batch Task Templates",
    "Property Task Templates",
    "Notebook Templates",
    "General Task Templates",
    "Sheet Templates",
}


def _normalize_tags(tags: Any, tags_text: str | None = None) -> list[str]:
    if isinstance(tags, str):
        items = [tags]
    elif isinstance(tags, list):
        items = tags
    elif tags is None:
        items = []
    else:
        raise TypeError("Tags must be a string or list of strings")

    cleaned = [t.strip() for t in items if str(t).strip()]

    if not cleaned and tags_text:
        cleaned = [
            t.strip()
            for t in tags_text.split(",")
            if t.strip()
        ]

    return cleaned


def _require_file_exists(path: str) -> None:
    if not os.path.isfile(path):
        raise FileNotFoundError(
            f"Output file '{path}' does not exist. Provide a valid Excel template path."
        )


def _find_header_row(
    ws: openpyxl.worksheet.worksheet.Worksheet,
    max_rows: int = 10,
) -> tuple[int | None, list[str] | None]:
    for row in ws.iter_rows(min_row=1, max_row=max_rows, values_only=False):
        if any(cell.value is not None and str(cell.value).strip() != "" for cell in row):
            values = ["" if cell.value is None else str(cell.value).strip() for cell in row]
            return row[0].row, values
    return None, None


def _first_non_empty_row(ws: openpyxl.worksheet.worksheet.Worksheet) -> list[str] | None:
    _, values = _find_header_row(ws)
    return values


def _trim_trailing_blanks(values: list[str]) -> list[str]:
    trimmed = list(values)
    while trimmed and trimmed[-1] == "":
        trimmed.pop()
    return trimmed


def _last_non_empty_index(values: list[str]) -> int:
    for idx in range(len(values) - 1, -1, -1):
        if values[idx] != "":
            return idx + 1
    return 0


def _first_non_empty_index(values: list[str]) -> int:
    for idx, value in enumerate(values):
        if value != "":
            return idx + 1
    return 0


def _header_variants(sheet_name: str) -> list[list[str]]:
    base = _EXPECTED_HEADERS.get(sheet_name, [])
    if sheet_name in _ALBERT_ID_OPTIONAL_SHEETS:
        return [base, base + [_ALBERT_ID_HEADER]]
    return [base]


def _ensure_albert_id_header(filename: str, sheet_name: str) -> None:
    if sheet_name not in _ALBERT_ID_OPTIONAL_SHEETS:
        return

    wb = openpyxl.load_workbook(filename)
    if sheet_name not in wb.sheetnames:
        return

    ws = wb[sheet_name]
    row_index, header_raw = _find_header_row(ws)
    if row_index is None:
        row_index = 1
        header_raw = []

    header_raw = header_raw or []
    header_trimmed = _trim_trailing_blanks(header_raw)

    last_idx = _last_non_empty_index(header_raw)
    first_idx = _first_non_empty_index(header_raw)

    if _ALBERT_ID_HEADER in header_trimmed:
        target_col = header_trimmed.index(_ALBERT_ID_HEADER) + 1
        target_cell = ws.cell(row=row_index, column=target_col)
        source_col = None
        if last_idx > 0 and last_idx != target_col:
            source_col = last_idx
        elif first_idx > 0 and first_idx != target_col:
            source_col = first_idx
    else:
        target_col = last_idx + 1
        target_cell = ws.cell(row=row_index, column=target_col, value=_ALBERT_ID_HEADER)
        source_col = last_idx if last_idx > 0 else first_idx if first_idx > 0 else None

    if source_col:
        source_cell = ws.cell(row=row_index, column=source_col)
        target_cell.font = copy(source_cell.font)
        target_cell.fill = copy(source_cell.fill)
        target_cell.border = copy(source_cell.border)
        target_cell.alignment = copy(source_cell.alignment)
        target_cell.number_format = copy(source_cell.number_format)
        target_cell.protection = copy(source_cell.protection)
    wb.save(filename)


def validate_template(path: str, required_sheets: list[str] | None = None) -> dict:
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Template file not found: {path}")

    required = required_sheets or list(_EXPECTED_HEADERS.keys())
    wb = openpyxl.load_workbook(path)

    missing_sheets: list[str] = []
    header_mismatches: list[dict] = []

    for sheet_name in required:
        if sheet_name not in wb.sheetnames:
            missing_sheets.append(sheet_name)
            continue

        ws = wb[sheet_name]
        actual_raw = _first_non_empty_row(ws) or []
        actual = _trim_trailing_blanks(actual_raw)
        variants = _header_variants(sheet_name)

        if actual not in variants:
            expected = _EXPECTED_HEADERS.get(sheet_name, [])
            header_mismatches.append(
                {"sheet": sheet_name, "expected": expected, "actual": actual}
            )

    return {
        "ok": not missing_sheets and not header_mismatches,
        "missingSheets": missing_sheets,
        "headerMismatches": header_mismatches,
    }


def _validate_dt_pg_filters(include: bool, prefix: str, tags: list[str], label: str) -> None:
    if not include:
        return

    if prefix and tags:
        raise ValueError(f"{label}: prefix and tags cannot both be set.")
    if not prefix and not tags:
        raise ValueError(f"{label}: either prefix or tags must be provided.")


def _validate_template_filter(include: bool, prefix: str, label: str) -> None:
    if not include:
        return

    if not prefix.strip():
        raise ValueError(f"{label}: prefix is required.")


def _encoded_tags_query(tags: list[str]) -> str:
    encoded_tags = [quote(tag, safe="") for tag in tags]
    return ",".join(encoded_tags)


def _fetch_items_by_tags(
    *,
    base_url: str,
    token: str,
    endpoint: str,
    tags: list[str],
    user_id: str = "USR1",
    offset: int = 0,
    limit: int = 25,
) -> list[dict]:
    base = base_url.rstrip("/")
    search_url = f"{base}/api/v3/{endpoint}/search"
    joined_tags = _encoded_tags_query(tags)

    query = (
        f"tags={joined_tags}"
        f"&sortBy=createdAt"
        f"&order=desc"
        f"&offset={offset}"
        f"&limit={limit}"
        f"&userId={user_id}"
    )

    full_url = f"{search_url}?{query}"
    headers = {"Authorization": f"bearer {token}"}

    response = requests.get(full_url, headers=headers)
    response.raise_for_status()

    payload = response.json() or {}
    return payload.get("Items") or []


def get_data_templates_by_prefix(prefix: str, client: Albert) -> pd.DataFrame:
    """
    Returns a DataFrame with:
    - Data Template Name
    - DT ID
    - Migrate?
    - Migration Complete?
    - Notes (optional) (hyperlink)
    - Albert ID (raw DAT...)
    """
    quoted = f'"{prefix}"'
    dt_list = client.data_templates.search(name=quoted)

    if not dt_list:
        print("No DTs match the prefix, continuing...")
        return pd.DataFrame(
            columns=[
                "Data Template Name",
                "DT ID",
                "Migrate?",
                "Migration Complete?",
                "Notes (optional)",
                "Albert ID",
            ]
        )

    data = [
        {
            "Data Template Name": dt.name,
            "DT ID": dt.id.replace("DAT", "DT"),
            "Migrate?": "Yes",
            "Migration Complete?": "",
            "Notes (optional)": (
                f'=HYPERLINK("'
                f"{client.session.base_url}/#aldt/detail?query={dt.id.replace('DAT','DT')}"
                f'","Link")'
            ),
            "Albert ID": dt.id,
        }
        for dt in dt_list
        if dt.name.startswith(prefix)
    ]

    if not data:
        return pd.DataFrame(
            columns=[
                "Data Template Name",
                "DT ID",
                "Migrate?",
                "Migration Complete?",
                "Notes (optional)",
                "Albert ID",
            ]
        )

    df = pd.DataFrame(data)
    df["_dt_num"] = df["DT ID"].str.replace("DT", "", regex=False).astype(int)
    df = df.sort_values("_dt_num").drop(columns="_dt_num").reset_index(drop=True)

    return df


def get_parameter_groups_by_prefix(prefix: str, client: Albert) -> pd.DataFrame:
    """
    Returns a DataFrame with:
    - Parameter Group Name
    - PG ID
    - Migrate?
    - Migration Complete?
    - Notes (optional) (hyperlink)
    - Albert ID (raw PRG...)
    """
    quoted = f'"{prefix}"'
    pg_list = client.parameter_groups.search(text=quoted)

    if not pg_list:
        print("No PGs match the prefix, continuing...")
        return pd.DataFrame(
            columns=[
                "Parameter Group Name",
                "PG ID",
                "Migrate?",
                "Migration Complete?",
                "Notes (optional)",
                "Albert ID",
            ]
        )

    data = [
        {
            "Parameter Group Name": pg.name,
            "PG ID": pg.id.replace("PRG", "PG"),
            "Migrate?": "Yes",
            "Migration Complete?": "",
            "Notes (optional)": (
                f'=HYPERLINK("'
                f"{client.session.base_url}/#alpg/detail?query={pg.id.replace('PRG','PG')}"
                f'","Link")'
            ),
            "Albert ID": pg.id,
        }
        for pg in pg_list
        if pg.name.startswith(prefix)
    ]

    if not data:
        return pd.DataFrame(
            columns=[
                "Parameter Group Name",
                "PG ID",
                "Migrate?",
                "Migration Complete?",
                "Notes (optional)",
                "Albert ID",
            ]
        )

    df = pd.DataFrame(data)
    df["_pg_num"] = df["PG ID"].str.replace("PG", "", regex=False).astype(int)
    df = df.sort_values("_pg_num").drop(columns="_pg_num").reset_index(drop=True)

    return df


def get_custom_templates_by_prefix(
    prefix: str,
    category: str,
    client: Albert,
    name_column: str
) -> pd.DataFrame:
    """
    Returns a DataFrame with:
    - Custom Template Name (sheet-specific label)
    - Migrate?
    - Migration Complete?
    - Notes (optional)
    - Albert ID (raw CTP...)
    """
    quoted = f'"{prefix}"'
    ctp_list = client.custom_templates.search(text=quoted)

    if not ctp_list:
        print(f"No {category} templates match the prefix, continuing...")
        return pd.DataFrame(
            columns=[name_column, "Migrate?", "Migration Complete?", "Notes (optional)", "Albert ID"]
        )

    data = [
        {
            name_column: ctp.name,
            "Migrate?": "Yes",
            "Migration Complete?": "",
            "Notes (optional)": "",
            "Albert ID": ctp.id,
        }
        for ctp in ctp_list
        if ctp.category == category and ctp.name.startswith(prefix)
    ]

    if not data:
        print(f"No {category} templates match the prefix, continuing...")
        return pd.DataFrame(
            columns=[name_column, "Migrate?", "Migration Complete?", "Notes (optional)", "Albert ID"]
        )

    df = pd.DataFrame(data)
    df = df.reset_index(drop=True)

    return df


def get_data_templates_by_tag(
    *,
    base_url: str,
    token: str,
    tags: list[str],
    client: Albert,
    user_id: str = "USR1",
    limit: int = 25
) -> pd.DataFrame:
    items = _fetch_items_by_tags(
        base_url=base_url,
        token=token,
        endpoint="datatemplates",
        tags=tags,
        user_id=user_id,
        limit=limit,
    )

    if not items:
        print("No DTs have these tags, continuing...")
        return pd.DataFrame(
            columns=[
                "Data Template Name",
                "DT ID",
                "Migrate?",
                "Migration Complete?",
                "Notes (optional)",
                "Albert ID",
            ]
        )

    data = []
    for item in items:
        if not item:
            continue
        name = item.get("name")
        albert_id = item.get("albertId")
        if not name or not albert_id:
            continue

        data.append(
            {
                "Data Template Name": name,
                "DT ID": albert_id.replace("DAT", "DT"),
                "Migrate?": "Yes",
                "Migration Complete?": "",
                "Notes (optional)": (
                    f'=HYPERLINK("'
                    f"{client.session.base_url}/#aldt/detail?query={albert_id.replace('DAT','DT')}"
                    f'","Link")'
                ),
                "Albert ID": albert_id,
            }
        )

    if not data:
        return pd.DataFrame(
            columns=[
                "Data Template Name",
                "DT ID",
                "Migrate?",
                "Migration Complete?",
                "Notes (optional)",
                "Albert ID",
            ]
        )

    df = pd.DataFrame(data)
    df["_dt_num"] = df["DT ID"].str.extract(r"(\d+)", expand=False).astype(float)
    df = df.sort_values("_dt_num", na_position="last").drop(columns="_dt_num").reset_index(drop=True)

    return df


def get_parameter_groups_by_tag(
    *,
    base_url: str,
    token: str,
    tags: list[str],
    client: Albert,
    user_id: str = "USR1",
    limit: int = 25
) -> pd.DataFrame:
    items = _fetch_items_by_tags(
        base_url=base_url,
        token=token,
        endpoint="parametergroups",
        tags=tags,
        user_id=user_id,
        limit=limit,
    )

    if not items:
        print("No PGs have these tags, continuing...")
        return pd.DataFrame(
            columns=[
                "Parameter Group Name",
                "PG ID",
                "Migrate?",
                "Migration Complete?",
                "Notes (optional)",
                "Albert ID",
            ]
        )

    data = []
    for item in items:
        if not item:
            continue
        name = item.get("name")
        albert_id = item.get("albertId")
        if not name or not albert_id:
            continue

        data.append(
            {
                "Parameter Group Name": name,
                "PG ID": albert_id.replace("PRG", "PG"),
                "Migrate?": "Yes",
                "Migration Complete?": "",
                "Notes (optional)": (
                    f'=HYPERLINK("'
                    f"{client.session.base_url}/#alpg/detail?query={albert_id.replace('PRG','PG')}"
                    f'","Link")'
                ),
                "Albert ID": albert_id,
            }
        )

    if not data:
        return pd.DataFrame(
            columns=[
                "Parameter Group Name",
                "PG ID",
                "Migrate?",
                "Migration Complete?",
                "Notes (optional)",
                "Albert ID",
            ]
        )

    df = pd.DataFrame(data)
    df["_pg_num"] = df["PG ID"].str.extract(r"(\d+)", expand=False).astype(float)
    df = df.sort_values("_pg_num", na_position="last").drop(columns="_pg_num").reset_index(drop=True)

    return df


def write_to_excel(output: pd.DataFrame, filename: str, sheet_name: str) -> None:
    """Append a DataFrame to an Excel sheet, starting at row 1, col 0."""
    row_count = len(output.index)
    object_word = "object" if row_count == 1 else "objects"
    print(f"{row_count} {object_word} found, writing to {sheet_name} sheet in {filename}")

    if sheet_name in _ALBERT_ID_OPTIONAL_SHEETS and _ALBERT_ID_HEADER in output.columns:
        _ensure_albert_id_header(filename, sheet_name)

    with pd.ExcelWriter(
        filename,
        engine="openpyxl",
        mode="a",
        if_sheet_exists="overlay",
    ) as writer:
        output.to_excel(
            writer,
            sheet_name=sheet_name,
            startrow=1,
            startcol=0,
            index=False,
            header=False,
        )


def run_template_tracker(
    *,
    base_url: str,
    token: str,
    config: dict,
) -> str:
    include = config.get("include", {}) or {}
    filters = config.get("filters", {}) or {}
    output_path = config.get("outputPath") or ""

    if not output_path:
        raise ValueError("Missing outputPath in config.")

    _require_file_exists(output_path)

    client = Albert(base_url=base_url, token=token)

    # Extract filters
    pg_filters = filters.get("parameterGroups", {}) or {}
    dt_filters = filters.get("dataTemplates", {}) or {}
    ct_filters = filters.get("customTemplates", {}) or {}

    pg_prefix = (pg_filters.get("prefix") or "").strip()
    dt_prefix = (dt_filters.get("prefix") or "").strip()

    pg_tags = _normalize_tags(pg_filters.get("tags"), pg_filters.get("tagsText"))
    dt_tags = _normalize_tags(dt_filters.get("tags"), dt_filters.get("tagsText"))

    include_pgs = bool(include.get("parameterGroups"))
    include_dts = bool(include.get("dataTemplates"))

    _validate_dt_pg_filters(include_pgs, pg_prefix, pg_tags, "Parameter Groups")
    _validate_dt_pg_filters(include_dts, dt_prefix, dt_tags, "Data Templates")

    # Custom templates toggles
    ct_include = include.get("customTemplates", {}) or {}
    include_batch = bool(ct_include.get("batch"))
    include_property = bool(ct_include.get("property"))
    include_notebook = bool(ct_include.get("notebook"))
    include_general = bool(ct_include.get("general"))
    include_sheet = bool(ct_include.get("sheet"))

    batch_prefix = (ct_filters.get("batch", {}) or {}).get("prefix", "").strip()
    property_prefix = (ct_filters.get("property", {}) or {}).get("prefix", "").strip()
    notebook_prefix = (ct_filters.get("notebook", {}) or {}).get("prefix", "").strip()
    general_prefix = (ct_filters.get("general", {}) or {}).get("prefix", "").strip()
    sheet_prefix = (ct_filters.get("sheet", {}) or {}).get("prefix", "").strip()

    _validate_template_filter(include_batch, batch_prefix, "Batch Task Templates")
    _validate_template_filter(include_property, property_prefix, "Property Task Templates")
    _validate_template_filter(include_notebook, notebook_prefix, "Notebook Templates")
    _validate_template_filter(include_general, general_prefix, "General Task Templates")
    _validate_template_filter(include_sheet, sheet_prefix, "Sheet Templates")

    # DTs
    if include_dts:
        if dt_tags:
            output = get_data_templates_by_tag(
                base_url=client.session.base_url,
                token=token,
                tags=dt_tags,
                client=client,
            )
        else:
            output = get_data_templates_by_prefix(prefix=dt_prefix, client=client)

        if not output.empty:
            write_to_excel(output=output, filename=output_path, sheet_name="DTs")

    # PGs
    if include_pgs:
        if pg_tags:
            output = get_parameter_groups_by_tag(
                base_url=client.session.base_url,
                token=token,
                tags=pg_tags,
                client=client,
            )
        else:
            output = get_parameter_groups_by_prefix(prefix=pg_prefix, client=client)

        if not output.empty:
            write_to_excel(output=output, filename=output_path, sheet_name="PGs")

    # Custom templates
    if include_property:
        output = get_custom_templates_by_prefix(
            prefix=property_prefix,
            client=client,
            category=_TEMPLATE_SHEET_NAMES[TemplateCategory.PROPERTY].replace(" Templates", ""),
            name_column="Template Name",
        )
        if not output.empty:
            write_to_excel(
                output=output,
                filename=output_path,
                sheet_name=_TEMPLATE_SHEET_NAMES[TemplateCategory.PROPERTY],
            )

    if include_batch:
        output = get_custom_templates_by_prefix(
            prefix=batch_prefix,
            client=client,
            category=_TEMPLATE_SHEET_NAMES[TemplateCategory.BATCH].replace(" Templates", ""),
            name_column="Template Name",
        )
        if not output.empty:
            write_to_excel(
                output=output,
                filename=output_path,
                sheet_name=_TEMPLATE_SHEET_NAMES[TemplateCategory.BATCH],
            )

    if include_general:
        output = get_custom_templates_by_prefix(
            prefix=general_prefix,
            client=client,
            category=_TEMPLATE_SHEET_NAMES[TemplateCategory.GENERAL].replace(" Templates", ""),
            name_column="Template Name",
        )
        if not output.empty:
            write_to_excel(
                output=output,
                filename=output_path,
                sheet_name=_TEMPLATE_SHEET_NAMES[TemplateCategory.GENERAL],
            )

    if include_sheet:
        output = get_custom_templates_by_prefix(
            prefix=sheet_prefix,
            client=client,
            category=_TEMPLATE_SHEET_NAMES[TemplateCategory.SHEET].replace(" Templates", ""),
            name_column="Template Name",
        )
        if not output.empty:
            write_to_excel(
                output=output,
                filename=output_path,
                sheet_name=_TEMPLATE_SHEET_NAMES[TemplateCategory.SHEET],
            )

    if include_notebook:
        output = get_custom_templates_by_prefix(
            prefix=notebook_prefix,
            client=client,
            category=_TEMPLATE_SHEET_NAMES[TemplateCategory.NOTEBOOK].replace(" Templates", ""),
            name_column="Notebook Template Name",
        )
        if not output.empty:
            write_to_excel(
                output=output,
                filename=output_path,
                sheet_name=_TEMPLATE_SHEET_NAMES[TemplateCategory.NOTEBOOK],
            )

    return output_path
