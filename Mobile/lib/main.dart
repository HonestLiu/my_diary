import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/sync/auth_service.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/home_screen.dart';
import 'package:my_diary_mobile/vault/local_vault.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final docs = await getApplicationDocumentsDirectory();
  final vault = LocalVault('${docs.path}/my-diary');
  final repo = JournalRepository(vault);
  final auth = AuthService(prefs);
  final store = AppStore(auth: auth, prefs: prefs, repo: repo);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<AppStore>.value(value: store),
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
          theme: buildTheme(ThemePreference.light, accent),
          darkTheme: buildTheme(ThemePreference.dark, accent),
          themeMode: themeMode,
          home: store.initialized
              ? const HomeScreen()
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
