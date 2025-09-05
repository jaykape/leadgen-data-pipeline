import requests
import os
from dotenv import load_dotenv

load_dotenv("configtest.env")

URL = os.getenv("URL")
BODY = {"name": "Jane Does", "email": "jane2@example.com"}
QUERY = os.getenv("QUERY")

try:
    response = requests.post(URL, params=QUERY, json=BODY, timeout=5)
    print(response.status_code, response.text)
except Exception as e:
    print(e)
