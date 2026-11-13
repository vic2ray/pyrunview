#!/bin/bash
# 起 KasmVNC 桌面（它自己就是 X 服务器），就绪后执行传入的命令。
# 约定：成功路径完全静默，失败才往 stderr 写一行。
set -euo pipefail

DISPLAY_NUM="${XVFB_DISPLAY:-:99}"
SCREEN="${XVFB_SCREEN:-1920x1080x24}"
PORT="${KASMVNC_PORT:-6901}"
SOCKET="/tmp/.X11-unix/X${DISPLAY_NUM#:}"

export DISPLAY="$DISPLAY_NUM"

# KasmVNC 的 X 服务器在不同版本里叫 Xkasmvnc 或 Xvnc，两个都认。
SERVER=""
for candidate in /usr/bin/Xkasmvnc /usr/bin/Xvnc; do
    if [ -x "$candidate" ]; then
        SERVER="$candidate"
        break
    fi
done

if [ -z "$SERVER" ]; then
    printf '[entrypoint] 找不到 KasmVNC 的 X 服务器（Xkasmvnc / Xvnc）\n' >&2
    exit 1
fi

if [ ! -S "$SOCKET" ]; then
    rm -f "/tmp/.X${DISPLAY_NUM#:}-lock" "$SOCKET"

    # -SecurityTypes None：不登录直接进桌面（内网、一次性容器）
    # -rfbport 同时作为 Web 端口，network.websocket_port 已配成同一个值
    "$SERVER" "$DISPLAY_NUM" \
        -geometry "${SCREEN%x*}" \
        -depth "${SCREEN##*x}" \
        -rfbport "$PORT" \
        -interface 0.0.0.0 \
        -httpd /usr/share/kasmvnc/www \
        -SecurityTypes None \
        -AlwaysShared \
        -AcceptSetDesktopSize \
        >/tmp/kasmvnc.log 2>&1 &
    vnc_pid=$!

    for _ in $(seq 1 200); do
        if [ -S "$SOCKET" ]; then
            exec "$@"
        fi
        if ! kill -0 "$vnc_pid" 2>/dev/null; then
            printf '[entrypoint] KasmVNC 启动失败，日志末尾：\n' >&2
            tail -n 20 /tmp/kasmvnc.log >&2 || true
            exit 1
        fi
        sleep 0.05
    done

    printf '[entrypoint] KasmVNC 超时：%s 10 秒内未就绪\n' "$DISPLAY_NUM" >&2
    tail -n 20 /tmp/kasmvnc.log >&2 || true
    exit 1
fi

exec "$@"
