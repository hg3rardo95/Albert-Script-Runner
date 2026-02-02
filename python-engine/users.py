from albert import Albert
import pandas as pd

def DownloadAllUsers(token: str, base_url: str) -> pd.DataFrame:
    """
    Fetches all users from the given Albert tenant and returns a DataFrame.
    """
    client = Albert(base_url=base_url, token=token)
    users = client.users.get_all()
    user_data = [user.model_dump() for user in users]
    return pd.DataFrame(user_data)

# Preferred snake_case alias (engine.py supports either name)
def download_all_users(token: str, base_url: str) -> pd.DataFrame:
    return DownloadAllUsers(token, base_url)