from urllib.parse import quote
from albert import Albert
from albert.resources.custom_templates import TemplateCategory
import pandas as pd
import os

import requests

#Set bearer token for environment
bearer="____"
base_url="https://sandbox.albertinvent.com"

options_list={"DT - tag":                   False,
              "DT - prefix":                False,
              "PG - tag":                   False,
              "PG - prefix":                False,
              "Property Task Templates":    False,
              "Batch Task Templates":       False,
              "General Task Templates":     False,
              "Worksheet Templates":        False,
              "Notebook Templates":         False}

tag_list=["___"]
prefix="____"

filename = "____.xlsx"
























def validate_inputs(options_list, tag_list, prefix, filename):
    """Validate configuration and input values before running the script."""
    
    # --- Mutual exclusivity checks ---
    assert not (options_list["DT - tag"] and options_list["DT - prefix"]), \
        "Error: Both DT options cannot be True."
    assert not (options_list["PG - tag"] and options_list["PG - prefix"]), \
        "Error: Both PG options cannot be True."

    # --- Tag list validation ---
    if options_list["DT - tag"] or options_list["PG - tag"]:
        assert tag_list and any(t.strip() for t in tag_list), \
            "Error: tag_list cannot be empty or contain only empty strings when a tag option is selected."

    # --- Prefix validation ---
    if (options_list["DT - prefix"] or 
        options_list["PG - prefix"] or 
        options_list["Property Task Templates"] or 
        options_list["Batch Task Templates"] or 
        options_list["General Task Templates"] or 
        options_list["Worksheet Templates"] or 
        options_list["Notebook Templates"]):
        assert prefix.strip(), \
            "Error: prefix cannot be empty or whitespace when a prefix or template option is selected."

    # --- File existence validation ---
    assert os.path.isfile(filename), \
        f"Error: File '{filename}' does not exist or is not a regular file."

    # --- Sheet name mapping validation ---
    sheet_name_map = {
        "DT - tag": "DT",
        "DT - prefix": "DT",
        "PG - tag": "PG",
        "PG - prefix": "PG",
        "Property Task Templates": "Property Task Templates",
        "Batch Task Templates": "Batch Task Templates",
        "General Task Templates": "General Task Templates",
        "Worksheet Templates": "Sheet Templates",
        "Notebook Templates": "Notebook Templates",
    }

    for option, enabled in options_list.items():
        if enabled:
            assert option in sheet_name_map and sheet_name_map[option].strip(), \
                f"Error: No valid sheet name defined for option '{option}'."

# --- Run validation ---
validate_inputs(options_list, tag_list, prefix, filename)

client = Albert.from_token(
    base_url=base_url,
    token=bearer
)

options={TemplateCategory.PROPERTY:"Property Task",
         TemplateCategory.GENERAL:"General Task",
         TemplateCategory.BATCH:"Batch Task",
         TemplateCategory.NOTEBOOK:"Notebook",
         TemplateCategory.SHEET:"Sheet"}

# DTs with common prefix
def get_data_templates_by_prefix(prefix: str, client: Albert) -> pd.DataFrame:
    """
    Returns a DataFrame with:
    - Data Template Name
    - DT ID
    - Migrate? (set to 'Yes' for all rows)
    Sorted by the numeric part of the DT ID.
    """
    quoted = f'"{prefix}"'
    dt_list = client.data_templates.search(name=quoted)

    if not dt_list:
        print("No DTs match the prefix, continuing...")
        return # exits the function, continues the rest of the program # exits the function, continues the rest of the program

    data = [
        {
            "Data Template Name": dt.name,
            "DT ID": dt.id.replace("DAT", "DT"),
            "Migrate?": "Yes",
            "Migration Complete?":"",
            "Notes": (f'=HYPERLINK("'f'{client.session.base_url}/#aldt/detail?query={dt.id.replace("DAT","DT")}'f'","{dt.id.replace("DAT","DT")}")')
        }
        for dt in dt_list
        if dt.name.startswith(prefix)
    ]
    
    df = pd.DataFrame(data)

    # Extract number after "DT" and sort by it
    df["_dt_num"] = df["DT ID"].str.replace("DT", "", regex=False).astype(int)
    df = df.sort_values("_dt_num").drop(columns="_dt_num").reset_index(drop=True)

    return df



# PGs with common prefix
def get_parameter_groups_by_prefix(prefix: str, client: Albert) -> pd.DataFrame:
    """
    Returns a DataFrame with:
    - Parameter Group Name
    - PG ID
    - Migrate? (set to 'Yes' for all rows)
    Sorted by the numeric part of the PG ID.
    """
    quoted = f'"{prefix}"'
    pg_list = client.parameter_groups.search(text=quoted)

    if not pg_list:
        print("No PGs match the prefix, continuing...")
        return # exits the function, continues the rest of the program

    data = [
        {
            "Parameter Group Name": pg.name,
            "PG ID": pg.id.replace("PRG", "PG"),
            "Migrate?": "Yes",
            "Migration Complete?":"",
            "Notes": (f'=HYPERLINK("'f'{client.session.base_url}/#alpg/detail?query={pg.id.replace("PRG","PG")}'f'","{pg.id.replace("PRG","PG")}")')
        }
        for pg in pg_list
        if pg.name.startswith(prefix)
    ]

    df = pd.DataFrame(data)

    # Sort by numeric part of PG ID
    df["_pg_num"] = df["PG ID"].str.replace("PG", "", regex=False).astype(int)
    df = df.sort_values("_pg_num").drop(columns="_pg_num").reset_index(drop=True)

    return df



# Custom Templates with common prefix
def get_custom_templates_by_prefix(prefix: str, category: str, client: Albert) -> pd.DataFrame:
    """
    Returns a DataFrame with:
    - Custom Template Name
    - Migrate? (set to 'Yes' for all rows)
    - Migration Complete?
    - CTP ID
    Sorted by the numeric part of the CTP ID.
    """
    quoted = f'"{prefix}"'
    ctp_list = client.custom_templates.search(text=quoted)
    
    if not ctp_list:
        print(f"No {category} templates match the prefix, continuing...")
        return pd.DataFrame(
            columns=["Custom Template Name", "CTP ID", "Migrate?"]
        )

    data = [
        {
            "Custom Template Name": ctp.name,
            "Migrate?": "Yes",
            "Migration Complete?":"",
            "CTP ID": ctp.id
        }
        for ctp in ctp_list
        if ctp.category == category and ctp.name.startswith(prefix)
    ]

    if not data:
        print(f"No {category} templates match the prefix, continuing...")
        return pd.DataFrame(
            columns=["Custom Template Name", "CTP ID", "Migrate?"]
        )
    
    df = pd.DataFrame(data)

    # Sort by numeric part of CT ID
    df["_ctp_num"] = (
        df["CTP ID"]
        .str.replace("CTP", "", regex=False)
        .astype(int)
    )
    df = df.sort_values("_ctp_num").drop(columns="_ctp_num").reset_index(drop=True)

    return df



def get_data_templates_by_tag(tags, client: Albert) -> pd.DataFrame:
    """
    Fetch Data Templates filtered by one or more tags and return a DataFrame with:
      - Data Template Name
      - DT ID (DAT -> DT)
      - Migrate? (Yes)
    Sorted by numeric part of DT ID (DT123 -> 123).
    """

    base_url = "https://sandbox.albertinvent.com/api/v3/datatemplates/search?"

    # Normalize tags to list
    if isinstance(tags, str):
        tags_list = [tags]
    elif isinstance(tags, list):
        tags_list = tags
    else:
        raise TypeError("Tags must be a string or list of strings")

    # Encode each tag once (handles spaces correctly), then join with commas
    joined_tags = ",".join(tags_list)
    # Encode each tag safely (spaces → %20)
    encoded_tags = [quote(tag, safe="") for tag in tags_list]
    # Join with commas (commas stay commas)
    joined_tags = ",".join(encoded_tags)

    query = (
        f"tags={joined_tags}&sortBy=createdAt&order=desc&offset=0&limit=25&userId=USR1"
    )
    full_url = f"{base_url}{query}"

    headers = {"Authorization": f"bearer {bearer}"}

    response = requests.get(full_url, headers=headers)
    response.raise_for_status()

    payload = response.json() or {}
    items = payload.get("Items") or []

    if not items:
        print(f"No DTs have these tags, continuing...")
        return 
    
    print(f"Extracting {len(items)} DTs with tags...")
    # Build rows in the same format as the prefix function
    data = []
    for item in items:
        if not item:
            continue
        name = item.get("name")
        albert_id = item.get("albertId")
        if not name or not albert_id:
            continue

        data.append({
            "Data Template Name": name,
            "DT ID": albert_id.replace("DAT", "DT"),
            "Migrate?": "Yes",
            "Migration Complete?":"",
            "Notes": (f'=HYPERLINK("'f'{client.session.base_url}/#aldt/detail?query={albert_id.replace("DAT","DT")}'f'","{albert_id.replace("DAT","DT")}")')
        })

    # Return empty DF with the same columns if nothing found
    if not data:
        return pd.DataFrame(columns=["Data Template Name", "DT ID", "Migrate?"])

    df = pd.DataFrame(data)

    # Safe sort by numeric suffix after DT (won't crash if something is weird)
    df["_dt_num"] = (
        df["DT ID"]
        .str.extract(r"(\d+)", expand=False)  # grabs digits anywhere
        .astype(float)                        # allows NaN
    )

    df = (
        df.sort_values("_dt_num", na_position="last")
          .drop(columns="_dt_num")
          .reset_index(drop=True)
    )

    return df



# Parameter Groups by Tag(s)
def get_parameter_groups_by_tag(tags, client: Albert) -> pd.DataFrame:
    """
    Fetch Parameter Groups filtered by one or more tags and return a DataFrame with:
      - Parameter Group Name
      - PG ID (PRG -> PG)
      - Migrate? (Yes)
    Sorted by numeric part of PG ID.
    """

    base_url = "https://sandbox.albertinvent.com/api/v3/parametergroups/search?"

    # Normalize input to list
    if isinstance(tags, str):
        tags_list = [tags]
    elif isinstance(tags, list):
        tags_list = tags
    else:
        raise TypeError("Tags must be a string or list of strings")

    # ✅ FIX #1: encode each tag ONCE (handles spaces correctly), then join with commas
    encoded_tags = [quote(tag, safe="") for tag in tags_list]
    joined_tags = ",".join(encoded_tags)

    query = f"tags={joined_tags}&sortBy=createdAt&order=desc&offset=0&limit=25&userId=USR1"
    full_url = f"{base_url}{query}"

    headers = {"Authorization": f"bearer {bearer}"}

    response = requests.get(full_url, headers=headers)
    response.raise_for_status()

    payload = response.json() or {}
    items = payload.get("Items") or []

    if not items:
        print(f"No PGs have these tags, continuing...")
        return 

    # ✅ FIX #2: build the same DF structure you used before
    data = []
    for item in items:
        if not item:
            continue
        name = item.get("name")
        albert_id = item.get("albertId")
        if not name or not albert_id:
            continue

        data.append({
            "Parameter Group Name": name,
            "PG ID": albert_id.replace("PRG", "PG"),
            "Migrate?": "Yes",
            "Migration Complete?":"",
            "Notes": (f'=HYPERLINK("'f'{client.session.base_url}/#alpg/detail?query={albert_id.replace("PRG","PG")}'f'","{albert_id.replace("PRG","PG")}")')
        })

    if not data:
        return pd.DataFrame(columns=["Parameter Group Name", "PG ID", "Migrate?"])

    df = pd.DataFrame(data)

    # Sort by numeric part of PG ID safely
    df["_pg_num"] = df["PG ID"].str.extract(r"(\d+)", expand=False).astype(float)
    df = df.sort_values("_pg_num", na_position="last").drop(columns="_pg_num").reset_index(drop=True)

    return df


# Write output to Excel
def write_to_excel(output, filename, sheet_name):
    """Appends a DataFrame to an Excel sheet, starting at row 1, col 0."""
    row_count = len(output)
    object_word = "object" if row_count == 1 else "objects"
    print(f"{row_count} {object_word} found, writing to {sheet_name} sheet in {filename}")
    
    with pd.ExcelWriter(
        filename,
        engine="openpyxl",
        mode="a",
        if_sheet_exists="overlay",  # or "replace"
    ) as writer:
        output.to_excel(
            writer,
            sheet_name=sheet_name,
            startrow=1,
            startcol=0,
            index=False,
            header=False,
        )



if options_list["DT - tag"]:
    output=get_data_templates_by_tag(tags=tag_list,client=client)
    if not output.empty:
        write_to_excel(output=output,filename=filename,sheet_name="DT")

if options_list["DT - prefix"]:
    output=get_data_templates_by_prefix(prefix=prefix,client=client)
    if not output.empty:
        write_to_excel(output=output,filename=filename,sheet_name="DT")

if options_list["PG - tag"]:
    output=get_parameter_groups_by_tag(tags=tag_list,client=client)
    if not output.empty:
        write_to_excel(output=output,filename=filename,sheet_name="PG")

if options_list["PG - prefix"]:
    output=get_parameter_groups_by_prefix(prefix=prefix,client=client)
    if not output.empty:
        write_to_excel(output=output,filename=filename,sheet_name="PG")

if options_list["Property Task Templates"]:
    output=get_custom_templates_by_prefix(prefix=prefix,client=client,category=options[TemplateCategory.PROPERTY])
    if not output.empty:
        write_to_excel(output=output,filename=filename,sheet_name="Property Task Templates")

if options_list["Batch Task Templates"]:
    output=get_custom_templates_by_prefix(prefix=prefix,client=client,category=options[TemplateCategory.BATCH])
    if not output.empty:
        write_to_excel(output=output,filename=filename,sheet_name="Batch Task Templates")

if options_list["General Task Templates"]:
    output=get_custom_templates_by_prefix(prefix=prefix,client=client,category=options[TemplateCategory.GENERAL])
    if not output.empty:
        write_to_excel(output=output,filename=filename,sheet_name="General Task Templates")

if options_list["Worksheet Templates"]:
    output=get_custom_templates_by_prefix(prefix=prefix,client=client,category=options[TemplateCategory.SHEET])
    if not output.empty:
        write_to_excel(output=output,filename=filename,sheet_name="Sheet Templates")

if options_list["Notebook Templates"]:
    output=get_custom_templates_by_prefix(prefix=prefix,client=client,category=options[TemplateCategory.NOTEBOOK])
    if not output.empty:
        write_to_excel(output=output,filename=filename,sheet_name="Notebook Templates")
