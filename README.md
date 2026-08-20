# MyDiary

> 一个「数据属于用户」的现代化跨平台日记应用。
> 本地优先（Local First）· 开放格式存储 · 桌面端与移动端通过对象存储互通 ·
> 即使软件停止维护，你的数据依然可以直接访问。

---

## 核心理念

1. **用户数据不能被软件锁死** —— 日记以纯 Markdown 落盘，任何文本编辑器都能直接打开。
2. **开放格式** —— `Markdown + Assets`，YAML frontmatter 存元数据，正文即内容。
3. **本地文件是唯一数据源** —— 本地 Markdown 文件即真实数据；SQLite 索引只用于搜索 / 统计 / 同步状态，**绝不存储正文**。
4. **本地优先** —— 所有读写先落本地，联网（同步）完全可选。
5. **对象存储云同步** —— 抽象 `StorageProvider`，兼容 AWS S3 / Cloudflare R2 / MinIO / 阿里云 OSS；双向、冲突感知、绝不静默覆盖。
6. **可选云中枢** —— FastAPI 服务只负责鉴权与签发预签名 URL，**正文与附件字节从不经过云端**。
7. **UI 精美** —— 参考 Apple Journal / Bear / Craft / Notion：大量留白、圆角卡片、柔和动画。

## 平台与功能

MyDiary 由三部分组成：桌面端、移动端、可选的云服务，共用同一套数据格式与同步协议。

| 平台 | 技术栈 | 目录 |
| --- | --- | --- |
| 桌面端 | Tauri 2 + React + TypeScript + Vite + TipTap | `Desktop/` |
| 移动端 | Flutter (Android) | `Mobile2/my_diary/` |
| 云服务（可选） | Python FastAPI + PostgreSQL | `Desktop/cloud/` |

### 桌面端

- **首页** —— 统计（本月 / 连续 / 喜欢 / 总计）、心情与天气柱状分布、标签云、最近条目、心情选择器
- **记录（富文本编辑器）** —— TipTap 所见即所得 + Markdown 源、条目导航、版本历史、图片/视频压缩、位置与地图选点、附件
- **日历** —— 按月浏览、按日查看
- **媒体** —— 扑克扇 + 时间轴双风格浏览全部图片/视频
- **地图** —— Leaflet 地图、地点聚合、地理编码、GPS 定位
- **搜索** —— 全文搜索（标题 / 正文 / 标签）
- **回忆** —— 历史上的今天
- **设置** —— 主题 / 品牌色 / 字体、头像与座右铭、同步配置、Markdown 导入导出、版本历史

### 移动端（五个主标签页）

- **首页** —— 日记卡片流（含封面与 meta 胶囊）、「回忆」横向轮播、悬浮「写日记 / 回到顶部」按钮
- **日历** —— 按月浏览
- **媒体** —— 图片 / 视频浏览
- **地图** —— 天地图 WMTS 瓦片（合规持牌源，CGCS2000 与 WGS-84 偏差 <1m）、GPS 定位
- **我的** —— 头像 / 座右铭、四格统计（本月 / 连续 / 喜欢 / 总计）、心情与天气柱状图、标签云、收藏列表、搜索、设置
- **编辑器** —— 富文本、心情 / 天气 / 位置 / 标签 / 喜欢、相册 / 拍照 / 录像 / 音频 / 任意文件附件、新建时自动定位与天气填充
- **Android 桌面小组件** —— 今日速览 + 最近一条 + 一键「写日记」直达（冷/热启动均可）

### 两端共性

- 主题（亮 / 暗 / 跟随系统）、6 种品牌色、无衬线 / 衬线字体
- 头像与座右铭（个人档案随同步在设备间迁移）
- 图片压缩保持原格式（jpg→jpg、png→png、webp→webp，长边 ≤2000px）+ 256px 列表缩略图
- 视频压缩（桌面端经 ffmpeg 转码、移动端 100% 原生实现），压缩进度实时反馈
- 版本历史（每次保存自动归档前一个版本）
- 完整备份导出（Markdown zip，含全部附件）

## 数据格式（Vault 布局）

两端共用同一套开放磁盘结构（实现见桌面端 `src/lib/vault.ts` 与移动端 `lib/vault/vault_layout.dart`）：

```
MyDiary/                                # 默认位于系统文档目录下
├── entries/YYYY/MM/YYYY-MM-DD-<shortid>.md   # 日记正文，frontmatter 元数据 + Markdown
├── assets/
│   ├── images/  audio/  video/  attachments/ # 附件按类型分目录，uuid 命名
│   └── thumbnails/                           # 256px JPEG 列表缩略图
├── profile/
│   ├── profile.json                          # displayName / motto / avatar（随同步迁移）
│   └── avatar.<ext>                          # 头像文件
├── metadata/
│   ├── index.json                            # 索引缓存（可重建）
│   ├── sync.json                             # 本机同步基线（设备专属，不跨设备同步）
│   └── hashes.json                           # 本地哈希缓存（加速增量扫描）
├── versions/<entry-id>/vN.md                 # 版本历史快照
├── conflicts/<entry-file-name>.{local,remote}.md  # 同步冲突副本
└── settings.json                             # 设备专属偏好 + 凭据（不参与同步）
```

- 条目以 `id`（而非日期）标识：任意多条目可共享同一天，日期只是普通元数据。
- 每个条目是一个 `.md` 文件，YAML frontmatter 记录 `id / date / title / mood / weather / location / tags / favorite / assets / created_at / updated_at`，正文即 Markdown 内容。

## 同步架构

### 双向引擎（客户端本地）

1. 扫描本地文件，计算 SHA-256 + 大小，构建清单
2. 获取远程清单（`metadata/sync.json`）与本机基线
3. 对比后上传 / 下载差异文件
4. 两侧自上次同步以来都被修改 → 写入 `conflicts/` 冲突副本，**绝不静默覆盖**，由用户在设置中手动解决（保留本地 / 采用远程）

关键设计：

- **同步范围**：仅 `entries/`、`assets/`、`versions/`、`profile/`；`settings.json`、`metadata/*`、`conflicts/` 属设备本地状态，排除在外，避免偏好、凭据与基线跨设备互覆。
- **性能**：资产文件（uuid 命名、落盘后不改写）用 `size + mtime` 命中本地哈希缓存，跳过重复读取；哈希计算在后台 isolate / 阻塞线程池执行，不卡 UI。
- **桌面端**：同步逻辑（含手写 AWS SigV4）整体下沉到 Rust `sync_vault` 命令，前端只调用命令；强制 HTTP/1.1，连接错误给出可操作提示。
- **移动端**：Dart 实现同样协议，与桌面端互通。

### 云中枢（可选，`Desktop/cloud/`）

轻量同步中枢，核心契约：**永不接收或存储日记正文与附件字节**。它只负责：

- 用户注册 / 登录（邮箱密码，JWT access + refresh）
- 同步设备与同步令牌（`sync_token`，服务端仅存 SHA-256 哈希，原始令牌仅返回一次，可吊销）
- 按用户命名空间签发**短时有效**的 S3 兼容对象存储预签名 URL（上传 PUT / 下载 GET，正文直连桶，不经过云端）
- 同步日志（仅计数 / 概要，不含内容）

即使云服务完全下线，日记正文仍完整保存在本地 Markdown 文件中。

## 技术栈

### 桌面端（`Desktop/`）

| 层 | 技术 |
| --- | --- |
| 框架 | Tauri 2.x + React + TypeScript + Vite |
| UI | TailwindCSS + shadcn 风格手写组件 + Framer Motion |
| 富文本 | TipTap / ProseMirror（Markdown 互转） |
| 状态管理 | Zustand |
| 路由 | react-router（路由级代码分割） |
| 地图 | Leaflet |
| 本地索引 | SQLite FTS5（仅索引 / 搜索，不存正文） |
| 同步 / 媒体 | Rust（SigV4、压缩、缩略图） |

### 移动端（`Mobile2/my_diary/`）

| 层 | 技术 |
| --- | --- |
| 框架 | Flutter + Material 3 |
| 状态管理 | provider |
| 存储 | path_provider + shared_preferences（LocalVault 落盘） |
| 富文本 | 自研编辑器（Markdown 解析 / 内联样式 / 媒体卡片） |
| 地图 | flutter_map（天地图 WMTS 瓦片）+ geolocator |
| 附件 | image_picker / file_picker / video_player / audioplayers / open_filex |
| 压缩 | flutter_image_compress + video_compress（100% 原生） |
| 小组件 | home_widget（Android） |
| 同步 | Dart 实现（isolate 后台哈希） |

### 云服务（`Desktop/cloud/`）

FastAPI + SQLAlchemy + PostgreSQL；手写 AWS SigV4（无 SDK 依赖）；密码 bcrypt、JWT HS256。

## 开发

### 桌面端

```bash
cd Desktop
npm install
npm run dev            # 前端开发：http://localhost:1420
npm run tauri dev      # 桌面应用（需 Rust 工具链 + WebView2）
npm run build          # 类型检查 + 构建
npm run tauri build    # 打包
```

### 移动端

```bash
cd Mobile2/my_diary
flutter pub get
flutter run            # 连接 Android 设备 / 模拟器
flutter test           # 运行测试
```

### 云服务（可选）

```bash
cd Desktop/cloud
cp .env.example .env   # 填写 JWT_SECRET 与 S3 凭据
docker compose up      # 推荐；或本地：uvicorn app.main:app --reload
# 交互式 API 文档： http://localhost:8000/docs
```

## 测试

- 移动端：`test/` 覆盖同步引擎、S3 预签名、编辑器编解码、导出、frontmatter、搜索标签等（`flutter test`）。
- 桌面端：`Desktop/scripts/` 提供各阶段回归脚本（`phase2_test.ts` ~ `phase6_test.ts`、`vault_import_test.ts` 等）。

## 目录结构

```
my-diary/
├── Desktop/                  # 桌面端（Tauri + React）
│   ├── src/                  # 前端：components / pages / store / lib / types
│   ├── src-tauri/            # Rust 壳：sync（SigV4 同步）、media（压缩/缩略图）
│   ├── cloud/                # 可选云服务（FastAPI + PostgreSQL）
│   └── scripts/              # 回归测试 / 工具脚本
└── Mobile2/my_diary/         # 移动端（Flutter）
    ├── lib/                  # main / models / repository / sync / vault / ui / services
    ├── android/              # 原生层（含桌面小组件 DiaryWidgetProvider）
    └── test/                 # 单元测试
```

## 开源说明

本项目为个人学习 / 自用项目。若你有兴趣在此基础上继续开发，欢迎 fork；数据格式与同步协议是开放契约，详见 `Desktop/src/types/journal.ts` 与 `Mobile2/my_diary/lib/vault/vault_layout.dart`。
