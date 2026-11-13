# pyrunview

Python 脚本的**一次性容器运行环境**，并且你能看见它在干什么。

一个镜像同时提供三样东西：

- **Python 3.12** —— 跑你的脚本
- **Google Chrome** —— 脚本里 `channel="chrome"` 或 `CHROME_PATH` 都能找到
- **KasmVNC 桌面** —— 浏览器打开 `:6901` 就是实时画面，可鼠标键盘操作

不含任何业务代码、绕过服务、手机画面服务。依赖也不在镜像里：宿主侧维护**一份共享依赖库**，运行时只读挂进去，镜像本身保持稳定。

## 快速开始

```bash
docker build -t pyrunview:latest .

# 桌面 + 你的脚本
docker run --rm -p 6901:6901 -v "$PWD/your-project:/app/mine:ro" pyrunview:latest \
  python /app/mine/main.py
```

浏览器打开 <http://127.0.0.1:6901> —— 不需要密码，直接就是桌面，双击桌面上的 Chrome 图标即可上网。

## 依赖怎么处理

镜像里**不装第三方依赖**。宿主侧维护一份共享库，所有工程共用：

```
~/.dsh/cache/pyrunview/
├─ wheels/          # 下载过的 wheel，单一集合
└─ site-packages/   # 所有依赖装这里，新工程往里累加
```

准备依赖（见 `example/prepare_deps.sh`）：

```bash
bash example/prepare_deps.sh requests_demo --proxy http://host.docker.internal:7890
```

运行时**零安装、零网络**：

```bash
docker run --rm -p 6901:6901 \
  -v "$PWD/proj:/app/mine:ro" \
  -v "$HOME/.dsh/cache/pyrunview/site-packages:/app/deps:ro" \
  -e PYTHONPATH=/app/deps \
  pyrunview:latest python /app/mine/main.py
```

关键点：`pip download` 要在**目标镜像里**执行，否则宿主平台下载的轮子（win_amd64）进 Linux 容器无法使用。

> 已知边界：共享库只有一份，同名包只能存在一个版本。需要不同版本时请钉死 `requirements.txt`，或单独开一份库。

## 组件与决策

| 组件 | 用途 | 说明 |
|---|---|---|
| `google-chrome-stable` | 浏览器 | Google 官方 apt 源 |
| `kasmvncserver` | X 服务器 + Web 桌面 | 版本钉死在 Dockerfile 的 `ARG`，构建可复现 |
| `tini` | PID 1 | 回收子进程 |
| `openbox` | 窗口管理器 | 没有它 Chrome 窗口无边框、不可拖动 |
| `pcmanfm` | 桌面图标层 | 没有它桌面是一片纯黑 |
| `xfonts-base` | 基础字体 | 不含 CJK 字体；需要中文渲染时自行加 `fonts-noto-cjk` |

**为什么用 KasmVNC 而不是 Xvfb + x11vnc + noVNC**：KasmVNC 的 `Xvnc` 自己就是 X 服务器，一个进程同时提供显示和 Web 服务，浏览器直连，不需要 VNC 客户端，也不需要 WebSocket 桥。

**两个认证开关缺一不可**：

| 开关 | 作用层 | 少了它的症状 |
|---|---|---|
| `-disableBasicAuth` | HTTP Basic Auth | 打开页面直接弹登录框 |
| `-SecurityTypes None` | VNC/RFB 鉴权 | 页面能开，但画面报 `No password configured for VNC Auth` |

## 文件

| 文件 | 作用 |
|---|---|
| `Dockerfile` | 构建步骤 |
| `kasmvnc.yaml` | KasmVNC 服务端配置（HTTP、0.0.0.0、1080p、无密码） |
| `entrypoint.sh` | 起桌面 → 等 X 就绪 → exec 传入的命令 |

## 环境变量

| 变量 | 默认 | 作用 |
|---|---|---|
| `DISPLAY` | `:99` | X display |
| `XVFB_DISPLAY` | `:99` | 覆盖 display 号 |
| `XVFB_SCREEN` | `1920x1080x24` | 分辨率 |
| `KASMVNC_PORT` | `6901` | Web 端口 |
| `CHROME_PATH` | `/usr/bin/google-chrome` | 给 `executable_path` 用 |

## 注意

- **无鉴权**：`-SecurityTypes None`，内网 / 一次性容器用，别暴露到公网
- **无 CJK 字体**：中文页面会渲染成方块
- **无 GPU**：走软件渲染，必要时给 Chrome 加 `--disable-gpu`
- 命令退出 → 容器结束 → 桌面消失
