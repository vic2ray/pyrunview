#!/bin/bash
# 依赖准备：把某个工程的依赖并入「一份共享依赖库」，供运行时只读挂载。
#
# 只有一份，不分项目、不分版本组合：
#   <cache>/wheels/          —— 下载过的 wheel，单一集合
#   <cache>/site-packages/   —— 所有依赖都装在这里，后续工程往里累加
#
# 为什么 pip download 要在目标镜像里跑：平台标签必须匹配容器（manylinux / cp312）。
# 在 Windows 宿主直接下载会拿到 win_amd64 轮子，进 Linux 容器必废。
#
# 用法：
#   bash prepare_deps.sh requests_demo [--proxy http://host.docker.internal:7890]

set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/vic2ray/pyrunview:latest}"
CACHE_ROOT="${CACHE_ROOT:-$HOME/.dsh/cache/pyrunview}"

TARGET="${1:-}"
shift || true
PROXY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --proxy) PROXY="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "用法: bash prepare_deps.sh <工程目录名> [--proxy URL]" >&2
    exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$HERE/$TARGET"
REQ="$PROJECT/requirements.txt"

if [ ! -f "$REQ" ]; then
    echo "找不到 $REQ" >&2
    exit 1
fi

# Windows 宿主上必须把 POSIX 路径转成 C:\...：Git Bash 的 MSYS 会把 -v 两侧
# 路径都做转换，导致容器内目标路径被改写。
winpath() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

WHEELS="$CACHE_ROOT/wheels"
DEPS="$CACHE_ROOT/site-packages"
mkdir -p "$WHEELS" "$DEPS"

WHEELS_HOST="$(winpath "$WHEELS")"
DEPS_HOST="$(winpath "$DEPS")"
REQ_HOST="$(winpath "$REQ")"

echo "工程      : $TARGET"
echo "依赖      : $(tr '\n' ' ' < "$REQ")"
echo "wheelhouse: $WHEELS"
echo "依赖库    : $DEPS"

proxy_opt=()
if [ -n "$PROXY" ]; then
    proxy_opt=(--proxy "$PROXY")
fi

# --upgrade：共享库里已有同名包时按 requirements 更新，避免"装了旧的就不动"
install_from_wheels() {
    docker run --rm \
        -v "$WHEELS_HOST:/wheels:ro" \
        -v "$DEPS_HOST:/deps" \
        -v "$REQ_HOST:/req.txt:ro" \
        --entrypoint bash "$IMAGE" -c \
        'pip install -q --no-index --find-links=/wheels --upgrade --target=/deps -r /req.txt'
}

echo "--- 从 wheelhouse 安装（缺什么会失败）---"
if ! install_from_wheels 2>/dev/null; then
    echo "--- wheel 不全，先下载补齐 ---"
    docker run --rm \
        -v "$WHEELS_HOST:/wheels" \
        -v "$REQ_HOST:/req.txt:ro" \
        --entrypoint bash "$IMAGE" -c \
        "pip download -q -r /req.txt -d /wheels --only-binary=:all: ${proxy_opt[*]}"
    echo "--- 再安装 ---"
    install_from_wheels
fi

echo "--- 依赖库现有顶层模块 ---"
docker run --rm -v "$DEPS_HOST:/deps:ro" --entrypoint bash "$IMAGE" -c \
    'ls /deps | grep -v dist-info | head -20'

echo
echo "准备完成。运行方式（零安装、零网络）："
echo
echo "docker run --rm -p 6901:6901 \\"
echo "  -v \"$PROJECT:/app/mine:ro\" \\"
echo "  -v \"$DEPS:/app/deps:ro\" \\"
echo "  -e PYTHONPATH=/app/deps \\"
echo "  $IMAGE python /app/mine/main.py"
