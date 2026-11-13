# example —— 只用于手工测试镜像，不参与构建

这三个小工程是**给 pyrunview 镜像做验收用**的，不是插件的一部分。

它们刻意都写成「零适配脚本」的形态，也就是未来插件要支持的样子：

- 没有 `base.py`、没有 `Crawler` 类、没有 `input_schema`
- 参数从环境变量读
- 最后一行为 JSON（插件据此提取结果）
- 依赖写在各自的 `requirements.txt` 里

> `example/` 已加入 `.dockerignore` 和 CI 的 `paths-ignore`，
> 改动这里不会触发重新构建镜像。

## 三个例子

| 目录 | 依赖 | 验证什么 |
|---|---|---|
| `requests_demo/` | requests | 纯脚本：无浏览器，只验证 Python + 网络 |
| `patchright_demo/` | patchright | 浏览器：Chrome 能否在虚拟屏上**有头**启动，画面里能不能看见 |
| `bypass_demo/` | patchright, PyPasser | 绕过能力：PyPasser 能否解开 Turnstile widget |

## 怎么跑

假设镜像已在本地：

```bash
# 纯脚本
docker run --rm -p 6901:6901 pyrunview:latest \
  bash -c 'pip install -q requests && python /app/example/requests_demo/main.py'

# 有头浏览器（打开 http://127.0.0.1:6901 就能看到它操作页面）
docker run --rm -p 6901:6901 -v "$PWD/example:/app/example:ro" pyrunview:latest \
  bash -c 'pip install -q patchright && python /app/example/patchright_demo/main.py'
```

`patchright_demo` 默认会在页面上停留 10 秒（`HOLD_SECONDS` 可调），够你切到 6901 看画面。

## 预期结果

| 例子 | 成功时最后一行 |
|---|---|
| requests | `{"ok": true, "ip": "..."}` |
| patchright | `{"ok": true, "title": "...", "screenshot": "/tmp/..."}` |
| bypass | `{"ok": true, "solved": true, "token": "1.23..."}` |
