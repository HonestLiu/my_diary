# MyDiary Cloud

后端云服务（FastAPI + PostgreSQL），为本地优先的日记应用提供：

1. **用户认证** —— 邮箱/密码注册登录，签发短期 JWT（access + refresh）。
2. **同步设备与同步令牌** —— 每台设备注册后获得一个长期、可吊销的 `sync_token`（仅服务端保存其 SHA-256 哈希，原始令牌仅返回一次）。
3. **对象存储授权** —— 为 S3 兼容存储（AWS S3 / Cloudflare R2 / MinIO / 阿里云 OSS）生成**用户命名空间隔离**、**短时有效**的预签名 URL（上传 PUT / 下载 GET）。
4. **同步日志** —— 记录每次同步的元数据（文件数、字节数、冲突数），**绝不存储日记正文或附件字节**。

> 核心原则延续客户端：**云端永不持有你的日记内容**。正文与附件只存在于你掌控的对象存储桶中，按 `<user_id>/...` 命名空间隔离；云端只负责鉴权、发令牌、签 URL、记日志。

## 目录结构

```
cloud/
├── app/
│   ├── main.py          # FastAPI 应用装配 + CORS + 启动建表
│   ├── config.py        # 环境变量配置 (pydantic-settings)
│   ├── database.py      # SQLAlchemy engine / session
│   ├── models.py        # User / SyncDevice / SyncLog（无正文列）
│   ├── schemas.py       # Pydantic 请求/响应模型
│   ├── security.py      # 密码哈希、JWT、sync token
│   ├── storage.py       # 手写 AWS SigV4 预签名（无 SDK 依赖）
│   ├── deps.py          # 依赖注入：当前用户 / 当前设备
│   └── routers/
│       ├── auth.py      # /auth/register|login|refresh|me|devices
│       ├── sync.py      # /sync/presign|logs
│       └── health.py    # /health
├── requirements.txt
├── Dockerfile
├── docker-compose.yml   # web + postgres
└── .env.example
```

## 本地运行

```bash
cd cloud
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # 填入 JWT_SECRET 与 S3 凭据
uvicorn app.main:app --reload
# 打开 http://localhost:8000/docs 查看交互式 API
```

## Docker 一键启动

```bash
cd cloud
cp .env.example .env
docker compose up --build
```

PostgreSQL 在 `:5432`，API 在 `:8000`。

## 同步协议（客户端如何使用）

1. 客户端 `POST /auth/register` 或 `/auth/login` → 拿到 `access_token`。
2. 客户端 `POST /auth/devices`（`Authorization: Bearer <access_token>`）→ 拿到 `sync_token`（仅此一次）。
3. 同步前，客户端 `POST /sync/presign`（`X-Sync-Token: <sync_token>`，body `{keys:[...], op:"upload"}`）
   → 拿到每个对象的预签名 URL，直接用 PUT 上传到对象存储（绕过云端，正文不经过服务器）。
4. 同步结束后，客户端 `POST /sync/logs` 上报元数据（文件数/字节数/冲突数）。

冲突处理、版本历史等逻辑全部在**客户端本地**完成（见主项目 Phase 5/6），云端不参与内容合并。

## 安全说明

- 密码使用 bcrypt 哈希；JWT 使用 HS256（生产环境请替换为强密钥或使用非对称 RS256）。
- `sync_token` 仅存哈希，原始令牌泄露风险可控，且可在 `sync_devices` 表直接删除该行来吊销。
- 所有对象键被强制限制在 `<user_id>/` 命名空间下，并拒绝 `..` 路径穿越。
- 生产环境请改用 Alembic 迁移替代启动建表（`environment=production` 时已关闭自动建表）。
