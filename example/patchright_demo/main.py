"""patchright 打开页面，截一张图，并在页面上停留一会儿。

用来看清"镜像里的 Chrome 到底起没起来"——跑起来后打开 http://<host>:6901
就能看到它正在操作浏览器。

    python main.py
    URL=https://example.com HOLD_SECONDS=30 python main.py
"""

import json
import os
import time

from patchright.sync_api import sync_playwright

URL = os.environ.get("URL") or "https://example.com"
HOLD = float(os.environ.get("HOLD_SECONDS") or "10")
SHOT = os.environ.get("SCREENSHOT") or "/tmp/pyrunview-shot.png"
PROXY = (os.environ.get("PROXY") or "").strip()


def main():
    launch = {
        "channel": "chrome",
        "headless": False,
        "args": ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
    }
    if PROXY:
        launch["proxy"] = {"server": PROXY}

    with sync_playwright() as pw:
        browser = pw.chromium.launch(**launch)
        page = browser.new_page(viewport={"width": 1280, "height": 800})
        try:
            page.goto(URL, wait_until="domcontentloaded", timeout=60_000)
            title = page.title()
            page.screenshot(path=SHOT)
            # 留出时间让人切到 6901 看画面
            time.sleep(HOLD)
            return {"ok": True, "url": URL, "title": title, "screenshot": SHOT}
        finally:
            browser.close()


if __name__ == "__main__":
    try:
        print(json.dumps(main(), ensure_ascii=False))
    except Exception as error:  # 让失败也以 JSON 收尾，便于插件解析
        print(json.dumps({"ok": False, "error": f"{type(error).__name__}: {error}"}, ensure_ascii=False))
        raise SystemExit(1)
