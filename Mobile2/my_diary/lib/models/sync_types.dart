/// 同步协议类型 —— 与桌面端 `Desktop/src/types/journal.ts` 的 Sync 段落一致。

/// 同步提供者。'none' 表示未启用同步。
enum SyncProvider { none, s3, r2, minio, oss, cloud }

/// 同步配置（provider-agnostic）。
class SyncConfig {
  final bool enabled;
  final SyncProvider provider;

  // 直接对象存储（S3 / R2 / MinIO / OSS）
  final String? endpoint;
  final String? bucket;
  final String? region;
  final String? accessKey;
  final String? secretKey;
  final bool? pathStyle;

  // 自动同步间隔（分钟）。0 表示关闭定期同步（仅手动 / 编辑后防抖同步）。
  final int autoSyncIntervalMinutes;

  // 云服务（FastAPI 预签名中枢）
  final String? baseUrl;
  // 注意：authToken 在移动端不使用 —— 设备通过 X-Sync-Token 鉴权，
  // 该令牌由云服务签发且只返回一次，持久化在设备的安全存储中。

  const SyncConfig({
    this.enabled = false,
    this.provider = SyncProvider.none,
    this.endpoint,
    this.bucket,
    this.region,
    this.accessKey,
    this.secretKey,
    this.pathStyle,
    this.autoSyncIntervalMinutes = 0,
    this.baseUrl,
  });

  factory SyncConfig.disabled() => const SyncConfig(
        enabled: false,
        provider: SyncProvider.none,
      );

  factory SyncConfig.fromJson(Map<String, dynamic> json) {
    final providerStr = (json['provider'] as String?) ?? 'none';
    final provider =
        SyncProvider.values.asNameMap()[providerStr] ?? SyncProvider.none;
    final rawPathStyle = json['pathStyle'];
    return SyncConfig(
      enabled: json['enabled'] as bool? ?? false,
      provider: provider,
      endpoint: json['endpoint'] as String?,
      bucket: json['bucket'] as String?,
      region: json['region'] as String?,
      accessKey: json['accessKey'] as String?,
      secretKey: json['secretKey'] as String?,
      pathStyle: rawPathStyle is bool ? rawPathStyle : null,
      autoSyncIntervalMinutes:
          ((json['autoSyncIntervalMinutes'] as int? ?? 0).clamp(0, 1440)).toInt(),
      baseUrl: json['baseUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider.name,
        if (endpoint != null) 'endpoint': endpoint,
        if (bucket != null) 'bucket': bucket,
        if (region != null) 'region': region,
        if (accessKey != null) 'accessKey': accessKey,
        if (secretKey != null) 'secretKey': secretKey,
        if (pathStyle != null) 'pathStyle': pathStyle,
        'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
        if (baseUrl != null) 'baseUrl': baseUrl,
      };

  /// 是否为「直接对象存储」模式（需要 SigV4 签名）。
  bool get isDirectStorage =>
      provider == SyncProvider.s3 ||
      provider == SyncProvider.r2 ||
      provider == SyncProvider.minio ||
      provider == SyncProvider.oss;

  /// 是否为「云服务预签名」模式。
  bool get isCloud => provider == SyncProvider.cloud;

  /// 有效 path-style 寻址（未显式配置时的合理默认）。
  ///
  /// MinIO / 阿里云 OSS 不支持 virtual-hosted（bucket 子域）寻址；IP 或
  /// localhost 端点也无法做 bucket 子域 —— 这些都必须用 path-style，否则
  /// 客户端会去解析 `bucket.<endpoint>` 这种不存在的主机名，导致
  /// "Failed host lookup"。AWS S3 用 virtual-hosted，故保持关闭。
  bool effectivePathStyle() {
    if (pathStyle != null) return pathStyle!;
    if (provider == SyncProvider.minio || provider == SyncProvider.oss) {
      return true;
    }
    final uri = Uri.tryParse(endpoint ?? '');
    if (uri != null) {
      final h = uri.host;
      if (h.isEmpty || h == 'localhost' || h == '127.0.0.1') return true;
      if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(h)) return true; // IPv4
      if (h.contains(':')) return true; // IPv6 字面量
    }
    return false;
  }

  /// 解析 SigV4 签名用的 region。显式填写优先；阿里云 OSS 从 Endpoint
  /// 主机名自动推导（oss-cn-hangzhou.aliyuncs.com → oss-cn-hangzhou）——
  /// OSS 会严格校验 region，若按默认 us-east-1 签名会被拒签 403；其余
  /// S3 兼容存储（MinIO / R2）不校验 region，按 AWS 默认 us-east-1。
  String effectiveRegion() {
    final explicit = region?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    if (provider == SyncProvider.oss) {
      final host = Uri.tryParse(endpoint ?? '')?.host ?? '';
      final m = RegExp(r'(oss-[a-z0-9-]+)\.aliyuncs\.com').firstMatch(host);
      if (m != null) return m.group(1)!;
    }
    return 'us-east-1';
  }

  SyncConfig copyWith({
    bool? enabled,
    SyncProvider? provider,
    String? endpoint,
    String? bucket,
    String? region,
    String? accessKey,
    String? secretKey,
    bool? pathStyle,
    int? autoSyncIntervalMinutes,
    String? baseUrl,
    bool clearCredentials = false,
  }) =>
      SyncConfig(
        enabled: enabled ?? this.enabled,
        provider: provider ?? this.provider,
        endpoint: endpoint ?? this.endpoint,
        bucket: bucket ?? this.bucket,
        region: region ?? this.region,
        accessKey: clearCredentials ? null : (accessKey ?? this.accessKey),
        secretKey: clearCredentials ? null : (secretKey ?? this.secretKey),
        pathStyle: pathStyle ?? this.pathStyle,
        autoSyncIntervalMinutes:
            autoSyncIntervalMinutes ?? this.autoSyncIntervalMinutes,
        baseUrl: baseUrl ?? this.baseUrl,
      );
}

/// 同步清单中的单条文件记录。path 始终相对于 vault 根（或用户命名空间）。
class SyncFile {
  final String path;
  final String hash; // SHA-256 hex
  final int size;
  final int updated; // ms since epoch

  SyncFile({
    required this.path,
    required this.hash,
    required this.size,
    required this.updated,
  });

  factory SyncFile.fromJson(Map<String, dynamic> json) => SyncFile(
        path: json['path'] as String,
        hash: json['hash'] as String,
        size: json['size'] as int,
        updated: json['updated'] as int,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'hash': hash,
        'size': size,
        'updated': updated,
      };
}

/// 同步清单（元数据/sync.json）。与桌面端结构一致。
class SyncManifest {
  final int version;
  final String deviceId;
  final List<SyncFile> files;
  final int generatedAt;

  SyncManifest({
    required this.deviceId,
    required this.files,
    required this.generatedAt,
    this.version = 1,
  });

  factory SyncManifest.fromJson(Map<String, dynamic> json) => SyncManifest(
        version: json['version'] as int? ?? 1,
        deviceId: (json['deviceId'] as String?) ??
            (json['device_id'] as String?) ??
            '',
        files: (json['files'] as List<dynamic>? ?? [])
            .map((e) => SyncFile.fromJson(e as Map<String, dynamic>))
            .toList(),
        generatedAt: (json['generatedAt'] as int?) ??
            (json['generated_at'] as int?) ??
            0,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'deviceId': deviceId,
        'files': files.map((f) => f.toJson()).toList(),
        'generatedAt': generatedAt,
      };
}

enum ConflictResolution { local, remote }

/// 同步冲突：同一文件自上次同步起在两侧都被修改。
class SyncConflict {
  final String path;
  final SyncFile local;
  final SyncFile remote;

  SyncConflict({
    required this.path,
    required this.local,
    required this.remote,
  });
}

/// 一次同步的结果汇总。
class SyncResult {
  final List<String> uploaded;
  final List<String> downloaded;
  final List<SyncConflict> conflicts;
  final List<String> errors;

  SyncResult({
    List<String>? uploaded,
    List<String>? downloaded,
    List<SyncConflict>? conflicts,
    List<String>? errors,
  })  : uploaded = uploaded ?? [],
        downloaded = downloaded ?? [],
        conflicts = conflicts ?? [],
        errors = errors ?? [];

  bool get hasChanges =>
      uploaded.isNotEmpty || downloaded.isNotEmpty || conflicts.isNotEmpty;
}
