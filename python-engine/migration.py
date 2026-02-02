from albert import Albert
from albert.resources.custom_templates import TemplateCategory

from urllib.parse import quote
import requests

#Set bearer token for environment
prefix="SP FT"
tag="SP Fast Track"

options={TemplateCategory.PROPERTY:"Property Task",
         TemplateCategory.GENERAL:"General Task",
         TemplateCategory.BATCH:"Batch Task",
         TemplateCategory.NOTEBOOK:"Notebook",
         TemplateCategory.SHEET:"Sheet"}

client = Albert.from_token(
    base_url="https://sandbox.albertinvent.com",
    token=""
)

# DTs with common prefix
def get_data_templates_by_prefix(prefix: str, client: Albert):
    """
    Returns a list of tuples (formatted_id, name) for Data Templates
    whose names start with the given prefix.
    """
    quoted=f'"{prefix}"'
    DT_list = client.data_templates.search(name=quoted)
    DT_list_filtered = [
        (dt.id.replace("DAT", "DT"), dt.name)
        for dt in DT_list
        if dt.name.startswith(prefix)
    ]
    return DT_list_filtered



# PGs with common prefix
def get_parameter_groups_by_prefix(prefix: str, client: Albert):
    """
    Returns a list of tuples (formatted_id, name) for Parameter Groups
    whose names start with the given prefix.
    """
    quoted=f'"{prefix}"'
    PG_list = client.parameter_groups.search(text=quoted)
    PG_list_filtered = [
        (pg.id.replace("PRG", "PG"), pg.name)
        for pg in PG_list
        if pg.name.startswith(prefix)
    ]
    return PG_list_filtered



# Custom Templates with common prefix
def get_custom_templates_by_prefix(prefix: str, category: str, client: Albert):
    """
    Returns a list of tuples (id, name) for Custom Templates
    that belong to a given category and whose names start with the given prefix.
    """
    quoted = f'"{prefix}"'
    CTP_list = client.custom_templates.search(text=quoted)
    CTP_list_filtered = [
        (ctp.id, ctp.name)
        for ctp in CTP_list
        if ctp.category == category and ctp.name.startswith(prefix)
    ]
    return CTP_list_filtered



# Data Templates by Tag(s)
def get_data_templates_by_tag(tags: str, client: Albert):
    """
    Fetch Data Templates from the Albert API filtered by one or more tags.
    'tags' can be a string or a list of strings.

    Returns a list of tuples (formatted_id, name),
    where 'DAT' in the ID is replaced with 'DT'.
    """
    base_url = "https://sandbox.albertinvent.com/api/v3/datatemplates/search?"

    # Normalize input to list
    if isinstance(tags, str):
        tags_list = [tags]
    elif isinstance(tags, list):
        tags_list = tags
    else:
        raise TypeError("Tags must be a string or list of strings")

    # Join and double-encode tags
    joined_tags = ",".join(tags_list)
    encoded_once = quote(joined_tags)
    encoded_twice = quote(encoded_once)

    query = f"tags={encoded_twice}&sortBy=createdAt&order=desc&offset=0&limit=25&userId=USR1"
    full_url = f"{base_url}{query}"

    headers = {
        "Authorization": f"bearer {bearer}"
    }

    response = requests.get(full_url, headers=headers)
    response.raise_for_status()

    data = response.json()
    items = data.get("Items", [])

    return [
        (item["albertId"].replace("DAT", "DT"), item["name"])
        for item in items
    ]



# Parameter Groups by Tag(s)
def get_parameter_groups_by_tag(tags: str, client: Albert):
    """
    Fetch Parameter Groups from the Albert API filtered by one or more tags.
    'tags' can be a string or a list of strings.

    Returns a list of tuples (formatted_id, name),
    where 'PRG' in the ID is replaced with 'PG'.
    """
    base_url = "https://sandbox.albertinvent.com/api/v3/parametergroups/search?"

    # Normalize input to list
    if isinstance(tags, str):
        tags_list = [tags]
    elif isinstance(tags, list):
        tags_list = tags
    else:
        raise TypeError("Tags must be a string or list of strings")

    # Join and double-encode tags
    joined_tags = ",".join(tags_list)
    encoded_once = quote(joined_tags)
    encoded_twice = quote(encoded_once)

    query = f"tags={encoded_twice}&sortBy=createdAt&order=desc&offset=0&limit=25&userId=USR1"
    full_url = f"{base_url}{query}"

    headers = {
        "Authorization": f"bearer {bearer}"
    }

    response = requests.get(full_url, headers=headers)
    response.raise_for_status()

    data = response.json()
    items = data.get("Items", [])

    return [
        (item["albertId"].replace("PRG", "PG"), item["name"])
        for item in items
    ]



# Validation for if task template is the expected_category
def check_template_category(ctpID: str, expected_category: str, client: Albert):
    ctp=client.custom_templates.get_by_id(ctpID)
    return ctp.category==expected_category

#Option 1: Get DTs with a prefix
def option_1(bearer: str,url: str,input:str):
    client = Albert.from_token(
        base_url=url,
        token=bearer
        )
    return get_data_templates_by_prefix(prefix=input,client=client)
    
#Option 2: Get DTs with a tag
def option_2(bearer:str,url:str,input:str):
    client = Albert.from_token(
        base_url=url,
        token=bearer
        )
    return get_data_templates_by_tag(tags=input,client=client)

#Option 3: Get PGs with a prefix
def option_3(bearer:str,url:str,input:str):
    client = Albert.from_token(
        base_url=url,
        token=bearer
        )
    return get_parameter_groups_by_prefix(prefix=input,client=client)

#Option 4: Get PGs with a tag
def option_4(bearer:str,url:str,input:str):
    client = Albert.from_token(
        base_url=url,
        token=bearer
        )
    return get_data_templates_by_tag(tags=input,client=client)

#Option 5: Get Property Task Templates with a Prefix
def option_5(bearer:str,url:str,input:str):
    client = Albert.from_token(
        base_url=url,
        token=bearer
        )
    return get_custom_templates_by_prefix(prefix=input,category=options[TemplateCategory.PROPERTY])

#Option 6: Get Batch Task Templates with a Prefix
def option_6(bearer:str,url:str,input:str):
    client = Albert.from_token(
        base_url=url,
        token=bearer
        )
    return get_custom_templates_by_prefix(prefix=input,category=options[TemplateCategory.BATCH])

#Option 7: Get General Task Templates with a Prefix
def option_7(bearer:str,url:str,input:str):
    client = Albert.from_token(
        base_url=url,
        token=bearer
        )
    return get_custom_templates_by_prefix(prefix=input,category=options[TemplateCategory.GENERAL])

#Option 8: Get Sheet Templates with a Prefix
def option_8(bearer:str,url:str,input:str):
    client = Albert.from_token(
        base_url=url,
        token=bearer
        )
    return get_custom_templates_by_prefix(prefix=input,category=options[TemplateCategory.SHEET])

#Option 9: Get Notebook Templates with a Prefix
def option_9(bearer:str,url:str,input:str):
    client = Albert.from_token(
        base_url=url,
        token=bearer
        )
    return get_custom_templates_by_prefix(prefix=input,category=options[TemplateCategory.NOTEBOOK])

