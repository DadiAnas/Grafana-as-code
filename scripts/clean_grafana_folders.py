import requests
import os
import sys

def get_env_var(var_name, prompt_text):
    value = os.environ.get(var_name)
    if not value:
        value = input(f"{prompt_text}: ")
    return value

def clean_folders():
    print("WARNING: This script will delete ALL folders in Grafana except 'General'.")
    print("Ensure you have a backup or can recreate them via Terraform.")
    
    grafana_url = get_env_var("GRAFANA_URL", "Enter Grafana URL (e.g. http://localhost:3000)")
    grafana_auth = get_env_var("GRAFANA_AUTH", "Enter Grafana Auth (Basic username:password or Bearer token)")
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": grafana_auth if "Basic" in grafana_auth or "Bearer" in grafana_auth else f"Bearer {grafana_auth}"
    }

    # Remove trailing slash
    if grafana_url.endswith("/"):
        grafana_url = grafana_url[:-1]

    # List all folders
    try:
        response = requests.get(f"{grafana_url}/api/folders", headers=headers)
        response.raise_for_status()
        folders = response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error listing folders: {e}")
        return

    print(f"Found {len(folders)} folders.")
    
    for folder in folders:
        uid = folder['uid']
        title = folder['title']
        print(f"Deleting folder: {title} (uid: {uid}) ...")
        
        try:
            del_response = requests.delete(f"{grafana_url}/api/folders/{uid}", headers=headers)
            if del_response.status_code == 200:
                print(f"Successfully deleted {title}")
            else:
                print(f"Failed to delete {title}: {del_response.status_code} - {del_response.text}")
        except requests.exceptions.RequestException as e:
            print(f"Error deleting folder {title}: {e}")

if __name__ == "__main__":
    clean_folders()
