from albert import Albert
import pandas as pd

def _to_row(user: object) -> dict:
    """Convert an SDK user/search-user model to a plain dict."""
    if hasattr(user, "model_dump"):
        try:
            # Prefer JSON-safe values (enums/dates become strings).
            return user.model_dump(mode="json")
        except TypeError:
            return user.model_dump()
    return {}

def DownloadAllUsers(token: str, base_url: str) -> pd.DataFrame:
    """
    Fetches all users from the given Albert tenant and returns a DataFrame.
    """
    client = Albert(base_url=base_url, token=token)

    # Fast path: `search()` returns partial user rows in one paginated endpoint and
    # avoids per-user hydration calls performed by `get_all()`.
    if hasattr(client.users, "search"):
        user_data = [_to_row(user) for user in client.users.search(max_items=None)]
        return pd.DataFrame(user_data)

    # Compatibility fallback for older SDKs.
    users = client.users.get_all()
    user_data = [_to_row(user) for user in users]
    return pd.DataFrame(user_data)

# Preferred snake_case alias (engine.py supports either name)
def download_all_users(token: str, base_url: str) -> pd.DataFrame:
    return DownloadAllUsers(token, base_url)
