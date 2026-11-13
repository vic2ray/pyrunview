#!/bin/bash
# 起 KasmVNC 桌面（它自己就是 X 服务器），就绪后执行传入的命令。
# 约定：成功路径完全静默，失败才往 stderr 写一行。
set -euo pipefail

DISPLAY_NUM="${XVFB_DISPLAY:-:99}"
SCREEN="${XVFB_SCREEN:-1920x1080x24}"
PORT="${KASMVNC_PORT:-6901}"
SOCKET="/tmp/.X11-unix/X${DISPLAY_NUM#:}"

export DISPLAY="$DISPLAY_NUM"

# 桌面组件：openbox 管窗口，pcmanfm 画图标。两个都可关闭（纯脚本运行省内存）。
DESKTOP="${PYRUNVIEW_DESKTOP:-1}"

start_desktop() {
    [ "$DESKTOP" = "0" ] && return 0
    command -v openbox >/dev/null 2>&1 && (openbox >/dev/null 2>&1 &)
    command -v pcmanfm >/dev/null 2>&1 && (pcmanfm --desktop >/dev/null 2>&1 &)
    return 0
}

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

    # 参数含义（见 Xvnc(1)），两个认证开关各管一层，缺一不可：
    #   -websocketPort   Web 端口，默认 6800。注意不是 -rfbport（那是 RFB 端口）
    #   -disableBasicAuth 关掉 HTTP Basic Auth（页面加载这一层）
    #   -SecurityTypes None 关掉 VNC/RFB 鉴权（画面上来这一层）
    #     少了它浏览器会报：Authentication failure: No password configured for VNC Auth
    #   -httpd           静态资源目录，与 websocket 同端口
    "$SERVER" "$DISPLAY_NUM" \
        -geometry "${SCREEN%x*}" \
        -depth "${SCREEN##*x}" \
        -interface 0.0.0.0 \
        -websocketPort "$PORT" \
        -httpd /usr/share/kasmvnc/www \
        -disableBasicAuth \
        -SecurityTypes None \
        -BlacklistThreshold 0 \
        -AlwaysShared \
        -AcceptSetDesktopSize \
        >/tmp/kasmvnc.log 2>&1 &
    vnc_pid=$!

    for _ in $(seq 1 200); do
        if [ -S "$SOCKET" ]; then
            start_desktop
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

start_desktop
exec "$@"
