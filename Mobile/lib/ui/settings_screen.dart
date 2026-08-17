import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/sync/auth_service.dart';
import 'package:provider/provider.dart';

bool _isDirect(SyncProvider p) =>
    p == SyncProvider.s3 ||
    p == SyncProvider.r2 ||
    p == SyncProvider.minio ||
    p == SyncProvider.oss;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemePreference _theme;
  late AccentKey _accent;
  late FontKey _font;
  late Mood _defaultMood;
  late String _displayName;
  late int _weekStartsOn;

  late SyncProvider _provider;
  late bool _pathStyle;
  late TextEditingController _baseUrlCtl;
  late TextEditingController _endpointCtl;
  late TextEditingController _bucketCtl;
  late TextEditingController _regionCtl;
  late TextEditingController _accessKeyCtl;
  late TextEditingController _secretKeyCtl;
  late TextEditingController _emailCtl;
  late TextEditingController _passwordCtl;

  bool _accountBusy = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppStore>().settings;
    _theme = s.theme;
    _accent = s.accent;
    _font = s.font;
    _defaultMood = s.defaultMood;
    _displayName = s.displayName;
    _weekStartsOn = s.weekStartsOn;
    _provider = s.sync.provider;
    _pathStyle = s.sync.pathStyle ?? false;
    _baseUrlCtl = TextEditingController(text: s.sync.baseUrl ?? '');
    _endpointCtl = TextEditingController(text: s.sync.endpoint ?? '');
    _bucketCtl = TextEditingController(text: s.sync.bucket ?? '');
    _regionCtl = TextEditingController(text: s.sync.region ?? '');
    _accessKeyCtl = TextEditingController();
    _secretKeyCtl = TextEditingController();
    _emailCtl = TextEditingController();
    _passwordCtl = TextEditingController();
  }

  @override
  void dispose() {
    _baseUrlCtl.dispose();
    _endpointCtl.dispose();
    _bucketCtl.dispose();
    _regionCtl.dispose();
    _accessKeyCtl.dispose();
    _secretKeyCtl.dispose();
    _emailCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.read<AppStore>();
    final auth = context.read<AuthService>();

    final sync = SyncConfig(
      enabled: _provider != SyncProvider.none,
      provider: _provider,
      baseUrl: _provider == SyncProvider.cloud
          ? _baseUrlCtl.text.trim()
          : null,
      endpoint: _isDirect(_provider) ? _endpointCtl.text.trim() : null,
      bucket: _isDirect(_provider) ? _bucketCtl.text.trim() : null,
      region: _isDirect(_provider) ? _regionCtl.text.trim() : null,
      pathStyle: _isDirect(_provider) ? _pathStyle : null,
    );

    if (_provider == SyncProvider.cloud && _baseUrlCtl.text.trim().isNotEmpty) {
      await auth.configureCloud(_baseUrlCtl.text.trim());
    } else {
      // 切走云服务时清空可能残留的旧地址（如 ab.bblmw.cn），避免后续同步误用它。
      await auth.clearCloudConfig();
    }
    if (_isDirect(_provider)) {
      final ak = _accessKeyCtl.text.trim();
      final sk = _secretKeyCtl.text.trim();
      if (ak.isNotEmpty && sk.isNotEmpty) {
        await auth.saveS3Secrets(ak, sk);
      }
    }

    final newSettings = store.settings.copyWith(
      theme: _theme,
      accent: _accent,
      font: _font,
      displayName: _displayName,
      weekStartsOn: _weekStartsOn,
      defaultMood: _defaultMood,
      sync: sync,
    );
    await store.saveSettings(newSettings);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设置已保存')));
      Navigator.pop(context);
    }
  }

  Future<void> _login() async {
    final auth = context.read<AuthService>();
    setState(() => _accountBusy = true);
    try {
      await auth.login(_emailCtl.text.trim(), _passwordCtl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('登录成功')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('登录失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  Future<void> _register() async {
    final auth = context.read<AuthService>();
    setState(() => _accountBusy = true);
    try {
      await auth.register(_emailCtl.text.trim(), _passwordCtl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('注册成功并创建设备')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('注册失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('账户（云服务）'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: auth.isCloudAuthenticated
                  ? Row(
                      children: [
                        const Icon(Icons.verified_user_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text('已登录：${auth.email ?? ""}')),
                        TextButton(
                          onPressed: () async {
                            await auth.logout();
                            setState(() {});
                          },
                          child: const Text('注销'),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        TextField(
                          controller: _emailCtl,
                          decoration:
                              const InputDecoration(hintText: '邮箱'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordCtl,
                          obscureText: true,
                          decoration:
                              const InputDecoration(hintText: '密码（≥8 位）'),
                        ),
                        const SizedBox(height: 10),
                        _accountBusy
                            ? const CircularProgressIndicator()
                            : Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                        onPressed: _login,
                                        child: const Text('登录')),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton(
                                        onPressed: _register,
                                        child: const Text('注册')),
                                  ),
                                ],
                              ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 18),
          _SectionTitle('同步'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  DropdownButtonFormField<SyncProvider>(
                    value: _provider,
                    decoration:
                        const InputDecoration(labelText: '同步方式'),
                    items: const [
                      DropdownMenuItem(
                          value: SyncProvider.none, child: Text('不使用同步')),
                      DropdownMenuItem(
                          value: SyncProvider.cloud, child: Text('云服务（预签名中枢）')),
                      DropdownMenuItem(
                          value: SyncProvider.s3, child: Text('AWS S3')),
                      DropdownMenuItem(
                          value: SyncProvider.r2, child: Text('Cloudflare R2')),
                      DropdownMenuItem(
                          value: SyncProvider.minio, child: Text('MinIO')),
                      DropdownMenuItem(
                          value: SyncProvider.oss, child: Text('阿里云 OSS')),
                    ],
                    onChanged: (v) => setState(() => _provider = v!),
                  ),
                  if (_provider == SyncProvider.cloud) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _baseUrlCtl,
                      decoration: const InputDecoration(
                        hintText: '云服务地址，如 https://diary.example.com',
                        labelText: '云服务 Base URL',
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text('选择「云服务」后，请在上方「账户」中登录或注册。',
                        style: TextStyle(fontSize: 12)),
                  ],
                  if (_isDirect(_provider)) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _endpointCtl,
                      decoration: const InputDecoration(
                        hintText: 'https://s3.us-east-1.amazonaws.com',
                        labelText: 'Endpoint',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bucketCtl,
                      decoration:
                          const InputDecoration(labelText: 'Bucket'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _regionCtl,
                      decoration:
                          const InputDecoration(labelText: 'Region'),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Path-style 寻址'),
                      subtitle: const Text('MinIO / R2 / OSS 开启；AWS S3 关闭'),
                      value: _pathStyle,
                      onChanged: (v) => setState(() => _pathStyle = v),
                    ),
                    TextField(
                      controller: _accessKeyCtl,
                      decoration: const InputDecoration(
                        labelText: 'Access Key（留空则不修改）',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _secretKeyCtl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Secret Key（留空则不修改）',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _SectionTitle('外观'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('主题'),
                  SegmentedButton<ThemePreference>(
                    segments: const [
                      ButtonSegment(
                          value: ThemePreference.light, label: Text('亮')),
                      ButtonSegment(
                          value: ThemePreference.dark, label: Text('暗')),
                      ButtonSegment(
                          value: ThemePreference.system, label: Text('跟随系统')),
                    ],
                    selected: {_theme},
                    onSelectionChanged: (s) =>
                        setState(() => _theme = s.first),
                  ),
                  const SizedBox(height: 10),
                  const Text('品牌色'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    children: AccentKey.values
                        .map((a) => ChoiceChip(
                              label: Text(accentLabels[a]!),
                              selected: _accent == a,
                              avatar: CircleAvatar(
                                backgroundColor: accentSeeds[a],
                                radius: 8,
                              ),
                              onSelected: (_) => setState(() => _accent = a),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  const Text('默认心情'),
                  Wrap(
                    spacing: 6,
                    children: Mood.ordered
                        .map((m) => ChoiceChip(
                              label: Text('${m.emoji} ${m.label}'),
                              selected: _defaultMood == m,
                              onSelected: (_) =>
                                  setState(() => _defaultMood = m),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(labelText: '昵称'),
                    onChanged: (v) => _displayName = v,
                    controller: TextEditingController(text: _displayName)
                      ..selection = TextSelection.fromPosition(
                          TextPosition(offset: _displayName.length)),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: _weekStartsOn,
                    decoration:
                        const InputDecoration(labelText: '每周起始日'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('周日')),
                      DropdownMenuItem(value: 1, child: Text('周一')),
                    ],
                    onChanged: (v) => setState(() => _weekStartsOn = v!),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15)),
      );
}
