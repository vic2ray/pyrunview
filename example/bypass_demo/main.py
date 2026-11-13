"""用 PyPasser 解开页面里的嵌入式 Cloudflare Turnstile。

    python main.py
    URL=https://turnstile-test.vercel.app/ python main.py

注意：解出来的 token 是一次性的，由宿主页面自己提交，
这里只证明 widget 被解开了，不代表拿到登录态。
"""

import json
import os

from patchright.sync_api import sync_playwright
from pypasser.captcha import turnstile

URL = os.environ.get("URL") or "https://turnstile-test.vercel.app/"
TIMEOUT = int(os.environ.get("SOLVE_TIMEOUT") or "30")
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
        page = browser.new_page()
        try:
            page.goto(URL, wait_until="domcontentloaded", timeout=60_000)
            title = page.title()

            has_widget = page.query_selector(
                ".cf-turnstile, iframe[src*='challenges.cloudflare.com']"
            )
            if has_widget is None:
                return {"ok": False, "url": URL, "title": title, "error": "页面没有 Turnstile widget"}

            result = turnstile.solve(page, timeout=TIMEOUT)
            token = result.response_token
            if not token:
                # managed 模式下 token 也可能已经写进隐藏 input
                node = page.query_selector("input[name='cf-turnstile-response']")
                token = node.get_attribute("value") if node else None

            return {
                "ok": bool(token),
                "url": URL,
                "title": title,
                "solved": bool(token),
                "token": (token[:24] + "…") if token else "",
            }
        finally:
            browser.close()


if __name__ == "__main__":
    try:
        print(json.dumps(main(), ensure_ascii=False))
    except Exception as error:
        print(json.dumps({"ok": False, "error": f"{type(error).__name__}: {error}"}, ensure_ascii=False))
        raise SystemExit(1)
