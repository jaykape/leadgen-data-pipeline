"""test lead data generated"""

import os
import requests
from dotenv import load_dotenv

load_dotenv("configtest.env")

api_url = os.getenv("api_url")
query = os.getenv("query")
lead_data = os.getenv("lead_data")

api_url = api_url + query

try:
    response = requests.post(api_url, json=lead_data, timeout=5)

    response.raise_for_status()
    data = response.text
    print(data)
except requests.exceptions.HTTPError as http_err:
    print(f"HTTP error occurred: {http_err}")
except requests.exceptions.ConnectionError as conn_err:
    print(f"Connection error occurred: {conn_err}")
except requests.exceptions.Timeout as timeout_err:
    print(f"Timeout error: {timeout_err}")
except requests.exceptions.RequestException as req_err:
    print(f"An error occurred: {req_err}")
