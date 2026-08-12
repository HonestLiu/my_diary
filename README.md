# MyDiary

> 一个「数据属于用户」的现代化跨平台日记软件。
> 本地优先（Local First）· 开放格式存储 · 软件停止维护后你的数据依然可直接访问。

## 核心理念

1. **用户数据不能被软件锁死** —— 日记以纯 Markdown 落盘，任何人都能用任意文本编辑器打开。
2. **开放格式** —— `Markdown + Assets`，frontmatter 存元数据，正文即内容。
3. **本地文件是真实数据源**，SQLite 只做索引 / 搜索 / 缓存 / 同步状态，**绝不存储正文**。
4. **本地优先** —— 所有读写先落本地，联网可选。
5. **对象存储云同步** —— 抽象 `StorageProvider`，兼容 S3 / R2 / MinIO / 阿里云 OSS。
6. **UI 精美** —— 参考 Apple Journal / Bear / Craft / Notion，大量留白、圆角卡片、柔和动画。

## 技术选型

| 层 | 技术 |
| --- | --- |
| 桌面端 | Tauri 2.x + React + TypeScript + Vite |
| UI | TailwindCSS + shadcn/ui（手写组件，遵循其约定） |
| 动画 | Framer Motion |
| 状态管理 | Zustand |
| 富文本 | TipTap / ProseMirror（Phase 3） |
| 本地索引 | SQLite（FTS5，仅索引，不存正文） |
| 文件存储 | Markdown + Assets |
| 云服务端 | Python FastAPI + PostgreSQL（Phase 7） |
| 移动端 | 预留接口，未来 Flutter（同步协议通用） |

## 目录结构

```
my-diary/
├── package.json            # 前端依赖与脚本
├── vite.config.ts          # Vite + Tauri 配置（含路由级代码分割）
├── tailwind.config.js      # 设计令牌（暖色纸张主题）
├── tsconfig*.json          # TS 严格模式（strict + noUncheckedIndexedAccess 等）
├── src/
│   ├── components/ui/      # shadcn 风格基础组件
│   ├── components/layout/  # 侧边栏 / 应用布局（含 Suspense 边界）
│   ├── components/dashboard/
│   ├── components/editor/  # TipTap 编辑器 / 工具栏 / 版本历史
│   ├── pages/              # Dashboard / Editor / Timeline / Calendar / Search / Settings
│   ├── store/              # Zustand 状态
│   ├── lib/                # utils / constants / storage / db / sync / version / journal
│   └── types/journal.ts    # 贯穿所有阶段的核心类型与协议
├── src-tauri/              # Tauri 2.x Rust 壳
├── cloud/                  # 云服务端（FastAPI + PostgreSQL，绝不存储正文）
└── scripts/               # 各阶段回归测试 / 工具脚本（如 phase6_test.ts）
```

## 开发

```bash
# 前端开发（Vite）
npm install
npm run dev          # http://localhost:1420

# 类型检查 / 构建
npm run build

# 启动 Tauri 桌面应用（需 Rust 工具链 + WebView2）
npm run tauri dev

# 打包
npm run tauri build
```

## 云服务端（Phase 7）

可选的轻量同步中枢，位于 `cloud/`（FastAPI + PostgreSQL）。核心契约：**永不接收或存储日记正文**——
它只负责身份认证、按用户命名空间签发短期对象存储预签名 URL、登记同步设备与同步元数据。

- 用户注册 / 登录（JWT：access + refresh 轮换）
- 同步设备与同步令牌（`X-Sync-Token`，服务端仅存 SHA-256 哈希；原始令牌仅返回一次）
- 对象存储预签名授权（S3 / R2 / MinIO / 阿里云 OSS 兼容；手写 SigV4，已对齐 AWS 官方向量）
- 同步日志（仅计数 / 概要，不含内容）
- PostgreSQL 模型：`users` / `sync_devices` / `sync_logs`，**无正文列**

运行：

```bash
cd cloud
cp .env.example .env      # 填写 JWT 密钥、S3 凭证、数据库连接串
docker compose up         # 推荐；或本地：pip install -r requirements.txt && uvicorn app.main:app --reload
# 交互式 API 文档： http://localhost:8000/docs
```

> 客户端与云服务通信的最小配置通过 `VITE_` 前缀的环境变量注入（见 `vite.config.ts` 的 `envPrefix`）。
> 即便云服务完全下线，日记正文仍完整保存在本地 Markdown 文件中——这正是「数据不被锁死」的保证。

## 阶段进度

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| Phase 1 | 项目初始化：Tauri + React + UI 框架 + 基础布局 | ✅ 完成 |
| Phase 2 | 本地 Markdown 存储与文件管理 | ✅ 完成 |
| Phase 3 | 富文本编辑器（TipTap） | ✅ 完成 |
| Phase 4 | 时间轴 / 日历 / 搜索（FTS5） | ✅ 完成 |
| Phase 5 | 对象存储同步引擎（手写 SigV4 预签名） | ✅ 完成 |
| Phase 6 | 版本历史 | ✅ 完成 |
| Phase 7 | 云服务端（FastAPI + PostgreSQL，不存正文） | ✅ 完成 |
| Phase 8 | UI 优化 / 动画 / 性能（路由级代码分割）/ 打包 / 文档 | 🔧 进行中 |

## 数据格式

见 `src/types/journal.ts`。日记落盘为 `entries/YYYY/MM/YYYY-MM-DD.md`，
元数据用 YAML frontmatter，正文为 Markdown；附件存于 `assets/`。
