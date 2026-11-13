# pyrunview 基础镜像：Python + Chrome + 可直接用浏览器访问的桌面。
#
# 负责的事情只有一件：让一个带浏览器界面的 Python 脚本跑起来，并且用户能看见、能操作。
#   - Python 3.12
#   - Google Chrome（channel="chrome" / CHROME_PATH 都能找到）
#   - KasmVNC：X 服务器 + Web 原生远程桌面（一个进程，浏览器直连，无需 VNC 客户端）
#   - tini：PID 1 回收子进程
#
# 刻意不包含：noVNC/websockify、手机画面服务、绕过服务、任何业务代码。
# 依赖也不进镜像 —— 运行期从挂载的 wheelhouse 安装到独立目录。

FROM python:3.12-slim-bookworm

# KasmVNC 版本钉死，保证构建可复现
ARG KASMVNC_VERSION=1.5.2
ARG KASMVNC_DEB=kasmvncserver_debian_bookworm_${KASMVNC_VERSION}_amd64.deb

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONIOENCODING=utf-8 \
    DISPLAY=:99 \
    CHROME_PATH=/usr/bin/google-chrome \
    KASMVNC_PORT=6901

# 一次装完：Chrome 运行库 + Chrome 本体 + KasmVNC。
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates wget gnupg \
        tini \
        libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
        libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
        libgbm1 libasound2 libpango-1.0-0 libcairo2 \
        xfonts-base \
        procps iproute2 curl; \
    install -m 0755 -d /etc/apt/keyrings; \
    wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /etc/apt/keyrings/google.gpg; \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends google-chrome-stable; \
    wget -qO /tmp/kasmvnc.deb \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/${KASMVNC_DEB}"; \
    apt-get install -y --no-install-recommends /tmp/kasmvnc.deb; \
    rm -f /tmp/kasmvnc.deb; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    chmod 1777 /tmp; \
    google-chrome --version; \
    ls -1 /usr/bin | grep -iE '^(X|kasm)?vnc|kasmxproxy' || true

WORKDIR /app

# KasmVNC 服务端配置：明文 HTTP、监听所有网卡、1080p、不拉黑
COPY kasmvnc.yaml /etc/kasmvnc/kasmvnc.yaml

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 6901：浏览器直接打开这一个端口就是桌面
EXPOSE 6901

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

# 手工调试用；插件运行时总是自己传 command。
CMD ["bash"]
