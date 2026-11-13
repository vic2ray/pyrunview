"""纯 requests：不碰浏览器，验证 Python + 网络 + 代理。

    python main.py
    URL=https://httpbin.org/ip python main.py
"""

import json
import os

import requests

URL = os.environ.get("URL") or "https://api.ipify.org?format=json"
PROXY = (os.environ.get("PROXY") or "").strip()
TIMEOUT = float(os.environ.get("TIMEOUT") or "20")


def main():
    proxies = {"http": PROXY, "https": PROXY} if PROXY else None
    response = requests.get(URL, proxies=proxies, timeout=TIMEOUT)
    response.raise_for_status()
    try:
        data = response.json()
    except ValueError:
        data = {"raw": response.text[:200]}

    ip = data.get("ip") if isinstance(data, dict) else None
    return {"ok": True, "status": response.status_code, "ip": ip, "url": URL}


if __name__ == "__main__":
    print(json.dumps(main(), ensure_ascii=False))
