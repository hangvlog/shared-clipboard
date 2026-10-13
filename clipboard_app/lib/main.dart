import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'stores/clipboard_store.dart';
import 'stores/auth_store.dart';
import 'screens/login_screen.dart';
import 'screens/clipboard_screen.dart';
import 'widgets/glass_surface.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ClipboardApp());
}

class ClipboardApp extends StatelessWidget {
  const ClipboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthStore()),
        ChangeNotifierProxyProvider<AuthStore, ClipboardStore>(
          create: (_) => ClipboardStore(),
          update: (_, authStore, clipboardStore) {
            clipboardStore?.updateAuth(authStore);
            return clipboardStore!;
          },
        ),
      ],
      child: MaterialApp(
        title: '共享剪贴板',
        debugShowCheckedModeBanner: false,
        theme: clipboardTheme(Brightness.light),
        darkTheme: clipboardTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const AuthGate(),
      ),
    );
  }
}

/// 根据登录状态切换页面
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authStore = context.watch<AuthStore>();

    if (authStore.isLoggedIn) {
      return const ClipboardScreen();
    }
    return const LoginScreen();
  }
}
