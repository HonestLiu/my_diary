import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/services/locator_data.dart';
import 'package:my_diary_mobile/services/locator_service.dart';
import 'package:my_diary_mobile/sync/auth_service.dart';
import 'package:my_diary_mobile/ui/app_shell.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/vault/local_vault.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // intl 在 Android 上不会自动初始化非默认 locale 的数据，
  // 使用 DateFormat(..., 'zh_CN') 前必须先初始化，否则抛 LocaleDataException。
  await initializeDateFormatting('zh_CN', null);
  final prefs = await SharedPreferences.getInstance();
  final docs = await getApplicationDocumentsDirectory();
  final vault = LocalVault('${docs.path}/my-diary');
  final repo = JournalRepository(vault);
  final auth = AuthService(prefs);
  final store = AppStore(auth: auth, prefs: prefs, repo: repo);
  final locatorData = LocatorData();
  final locator = LocatorService(locatorData);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<AppStore>.value(value: store),
        ChangeNotifierProvider<LocatorData>.value(value: locatorData),
        ChangeNotifierProvider<LocatorService>.value(value: locator),
      ],
      child: MyApp(store: store),
    ),
  );

  // 启动后初始化 vault（创建目录、加载设置、扫描条目）。
  WidgetsBinding.instance.addPostFrameCallback((_) => store.init());
}

class MyApp extends StatelessWidget {
  final AppStore store;
  const MyApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStore>(
      builder: (context, store, _) {
        final accent = store.settings.accent;
        final themeMode = store.settings.theme == ThemePreference.light
            ? ThemeMode.light
            : store.settings.theme == ThemePreference.dark
                ? ThemeMode.dark
                : ThemeMode.system;
        return MaterialApp(
          title: 'MyDiary',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(ThemePreference.light, accent, store.settings.font),
          darkTheme:
              buildTheme(ThemePreference.dark, accent, store.settings.font),
          themeMode: themeMode,
          home: store.initialized
              ? const AppShell()
              : const _SplashScreen(),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在准备你的日记 vault…',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
