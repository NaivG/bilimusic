# BiliMusic · Chrome 扩展（MV3）

BiliMusic 的 Chrome 扩展端，功能保持基础：**搜索、完整播放、登录、收藏夹、通知、持久化**。

与 Flutter 主 App（`lib/`）、TUI（`bin/`）、Vela 手表端（`vela/`）互不共享代码，只共用 B 站接口协议。

> 仅供学习交流，不得商用。

---

## 安装

需要 **Chrome 116+**。

1. 拉取远程 UI 资源：

```shell
node extension/scripts/gen_daisyui_subset.mjs        # daisyUI 组件子集
node extension/scripts/gen_fontawesome_subset.mjs    # FA 图标子集 + woff2
```

2. 打开 `chrome://extensions`
3. 右上角打开「开发者模式」
4. 「加载已解压的扩展程序」→ 选择本 `extension/` 目录
5. 改完代码回这个页面点「刷新」

## 使用

- **搜索**：点扩展图标打开 popup，或点右上角展开全页播放器。输入关键词 / `BV1xxx` / `AV号`。
- **播放**：搜索或收藏夹里点播放；popup 与全页共用一套队列。
- **登录**：全页播放器「我的」页，两种方式——扫码登录（哔哩哔哩 App），或从 Chrome 导入 Cookie（需先在 bilibili.com 网页登录）。登录后可看 B 站收藏夹。
- **本地收藏**：歌曲右侧 ♥ 添加，播放控制条的 ♥ 收藏当前曲目；与账号无关，不需要登录。
- **播放设置**：音质、系统通知、循环模式、主题。
- **后台播放**：播放由 offscreen 文档承载，关闭 popup 或全页都不中断。

## 权限说明

| 权限 | 用途 |
| --- | --- |
| `storage` | 队列 / 进度 / 登录态 / 收藏 / 设置的持久化 |
| `cookies` | 从浏览器导入 bilibili Cookie、扫码登录写回、退出登录摘会话 Cookie |
| `notifications` | 播放失败、登录结果的系统通知 |
| `offscreen` | 播放宿主 |
| `declarativeNetRequest` | 给 bilibili / CDN 请求改写 `Referer` |
| `host_permissions` | 上述域名的跨域请求与 DNR 生效范围 |

未申请 `tabs` 权限：复用已打开的播放页用 `tabs.query({url})` 按 URL 匹配即可，不需要读取所有标签页地址。

---

## 架构

```text
  popup / player 页  ──指令──▶  service worker  ──指令──▶  offscreen document
        │                          │  （唯一写入面）            │  （唯一播放面）
        │                          │  storage / cookies /       │  <audio>
        │                          │  notifications / 取流      │  Media Session
        │                          │
        └────只读 storage（onChanged）◀──── 落盘 ────┘
```

三条边界由 MV3 的约束决定：

| 约束 | 后果 |
| --- | --- |
| service worker 无 DOM 且随时被回收 | 播放必须放 offscreen document |
| offscreen 只支持 `chrome.runtime` 一个扩展 API | storage / notifications / cookies 全在 service worker |
| `AUDIO_PLAYBACK` 静音 30 秒后文档自动关闭 | 暂停久了要能重建宿主并从持久化进度续播 |

于是：**UI 只读 storage，SW 只写 storage，offscreen 只播**。offscreen 死了 UI 照常显示，UI 关了播放照常继续。

消息信封统一是 `{ target: 'sw'|'ui'|'offscreen'|'page', ns, type, payload }`，每个上下文先看 `target` 再决定要不要处理。

### Referer 注入

B 站 CDN 的 `upos` / `edge` 节点校验 `Referer`，缺它返回 403。扩展由 [`rules.json`](rules.json) 的 declarativeNetRequest 规则在网络层注入 `Referer: https://www.bilibili.com/`，因此所有节点都能直链播。

---

## 目录

```text
extension/
├── manifest.json            # MV3
├── rules.json               # DNR：改写 Referer
├── icons/icon.png
├── scripts/
│   ├── verify.mjs               # 离线自检（纯 Node，无网络）
│   ├── gen_daisyui_subset.mjs   # 生成 daisyUI 按需子集（联网）
│   ├── gen_fontawesome_subset.mjs # 生成 FA 图标子集 + woff2（联网）
│   ├── gen_md3_tokens.mjs       # 生成 MD3 色彩令牌（纯计算，不联网）
│   ├── gen_qr_tables.py         # 生成 QR 参数表（对照 Python qrcode 库）
│   ├── gen_qr_fixtures.py       # 生成 QR 对照矩阵
│   └── fixtures/qr_matrices.json
└── src/
    ├── core/                # 纯函数，无 chrome.* → 可被 Node 直接 import 测
    ├── net/                 # 只在 service worker 里跑
    ├── auth/                # cookies.js(纯) / session.js / qr_login.js
    ├── qr/qr_encode.js      # 手写 QR 编码器（零依赖）
    ├── bg/service_worker.js # 消息路由 / 存储 / 通知 / offscreen 生命周期
    ├── offscreen/           # offscreen.html + audio_host.js（唯一播放面）
    └── ui/                  # popup + player 全页 + shared/ + MD3 令牌 + vendor/
```

### UI 第三方资源

UI 用到的第三方资源全部由生成脚本本地化，运行时不访问 CDN：

- **daisyUI 5**：按需拼接的组件子集，`src/ui/vendor/daisyui.subset.css`
- **Font Awesome 5.15.4 Free**：按白名单裁剪的图标子集与自托管 woff2，`src/ui/vendor/`

---

## 开发

### 离线自检

```bash
node extension/scripts/verify.mjs
```

覆盖纯逻辑（MD5、WBI 签名、APP 签名、AV→BV、搜索解析、CDN 过期窗口、曲目同一性、本地收藏、Cookie 头拼装、QR 编码逐位比对、播放进度外推），以及静态接线核对（消息名与 handler 对齐、manifest 引用、页面资源引用、UI 依赖完整性）。

改网络层、消息名、QR 参数、manifest 或 UI 依赖后必跑。

### 重新生成 QR 对照

改了 QR 参数或摆放规则后：

```bash
python -m pip install qrcode
PYTHONIOENCODING=utf-8 python extension/scripts/gen_qr_tables.py    > extension/src/core/qr_tables.js
PYTHONIOENCODING=utf-8 python extension/scripts/gen_qr_fixtures.py
node extension/scripts/verify.mjs
```

### 升级 UI 依赖

```bash
node extension/scripts/gen_daisyui_subset.mjs        # daisyUI 组件子集
node extension/scripts/gen_fontawesome_subset.mjs    # FA 图标子集 + woff2
node extension/scripts/gen_md3_tokens.mjs            # MD3 色彩令牌（纯计算，不联网）
node extension/scripts/verify.mjs                    # 反查 UI 实际用到的图标/组件是否覆盖
```

增删 Font Awesome 图标：改 `gen_fontawesome_subset.mjs` 里的 `SOLID` / `REGULAR` / `BRANDS` 白名单后重跑。

---

## 真机验证清单

1. **DNR Referer 生效** —— 取一首落在 `upos` 节点的曲目，DevTools Network 里看 `*.bilivideo.com` 的请求头是否带 `Referer: https://www.bilibili.com/`、响应是否 206。
2. **offscreen 自动播放** —— 第一次点播放是否被 autoplay 策略拦。
3. 搜索（关键词 / `BV1xxx` / `AVxxx`）→ 播放 → 暂停 → 关掉 popup 再开，仍在播且状态一致。
4. 暂停超过 30 秒再点播放 → offscreen 已被回收，能重建并从原进度续播。
5. 播放中进度条每秒都在走，不是 5 秒一跳；暂停后时间冻结，拖动进度条能跳。
6. popup 底部队列：点行切歌、× 移出、🗑 清空；当前曲目高亮且自动滚进视野；进度走动时列表不被顶回顶部。
7. 两种登录各自走通（扫码含过期提示、从 Chrome 导入）。判据是「我的」页显示出了昵称。
8. 收藏夹：列文件夹 → 播放全部 → 点播 → 分页；本地收藏添加/取消/重启后仍在。
9. 切歌 → 系统媒体控制栏出现元数据与播控键。
10. 拔网播放 → 出现「播放失败」系统通知。
11. 重启浏览器 → 队列、进度、登录态、本地收藏全部恢复。

---

## 排查

| 现象 | 多半是 |
| --- | --- |
| 点播放没反应 | offscreen 消息竞态；看 SW 控制台有没有 `创建 offscreen 失败` |
| 所有曲目 403 | DNR 没生效（见验证清单第 1 条），或取流地址过期 |
| 登录后仍显示未登录 | `session.ready()` 没等到；或浏览器 jar 里没有 `SESSDATA` |
| 显示「已登录：（未取到昵称）」 | 票据没到服务端，看诊断行的域名后缀 |
| 收藏夹为空 | 未登录，或该账号没有自建收藏夹 |
| 系统媒体栏没变化 | 看 offscreen 控制台有没有 `navigator.mediaSession 不可用` |
| 暂停久了再播要等一下 | offscreen 被回收后重建 + 重新取流，属预期 |

