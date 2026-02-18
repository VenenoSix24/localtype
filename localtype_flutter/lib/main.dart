import 'package:flutter/material.dart';
import 'package:animations/animations.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'providers/local_type_provider.dart';
import 'screens/connection_screen.dart';
import 'screens/input_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocalTypeProvider()),
      ],
      child: const LocalTypeApp(),
    ),
  );
}

class LocalTypeApp extends StatelessWidget {
  const LocalTypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalTypeProvider>(
      builder: (context, provider, child) {
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            ColorScheme lightColorScheme;
            ColorScheme darkColorScheme;

            if (lightDynamic != null &&
                darkDynamic != null &&
                provider.useDynamicColor) {
              // 使用提取的主色重新生成 Seed，以确保所有容器变体都被正确填充
              lightColorScheme = ColorScheme.fromSeed(
                seedColor: lightDynamic.primary,
                brightness: Brightness.light,
              ).harmonized();
              darkColorScheme = ColorScheme.fromSeed(
                seedColor: darkDynamic.primary,
                brightness: Brightness.dark,
              ).harmonized();
            } else {
              lightColorScheme = ColorScheme.fromSeed(
                seedColor: provider.seedColor,
                brightness: Brightness.light,
              );
              darkColorScheme = ColorScheme.fromSeed(
                seedColor: provider.seedColor,
                brightness: Brightness.dark,
              );
            }

            return MaterialApp(
              title: 'LocalType',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme(
                seedColor: provider.seedColor,
                colorScheme: lightColorScheme,
                useSystemFont: provider.useSystemFont,
              ),
              darkTheme: AppTheme.darkTheme(
                seedColor: provider.seedColor,
                colorScheme: darkColorScheme,
                useSystemFont: provider.useSystemFont,
              ),
              themeMode: provider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
              home: const MainScreen(),
            );
          },
        );
      },
    );
  }
}

/// 四标签页主界面：连接 → 键盘 → 成就 → 设置
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  int _lastIndex = 0;

  static const List<Widget> _screens = <Widget>[
    ConnectionScreen(),
    InputScreen(),
    InsightsScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _lastIndex = _selectedIndex;
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LocalTypeProvider>(context);
    final isReverse = _selectedIndex < _lastIndex;

    return Scaffold(
      body: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 400),
        reverse: isReverse,
        transitionBuilder: (child, primaryAnimation, secondaryAnimation) {
          switch (provider.pageTransitionType) {
            case 'sharedAxisX':
              return SharedAxisTransition(
                animation: primaryAnimation,
                secondaryAnimation: secondaryAnimation,
                transitionType: SharedAxisTransitionType.horizontal,
                child: child,
              );
            case 'sharedAxisY':
              return SharedAxisTransition(
                animation: primaryAnimation,
                secondaryAnimation: secondaryAnimation,
                transitionType: SharedAxisTransitionType.vertical,
                child: child,
              );
            case 'sharedAxisZ':
              return SharedAxisTransition(
                animation: primaryAnimation,
                secondaryAnimation: secondaryAnimation,
                transitionType: SharedAxisTransitionType.scaled,
                child: child,
              );
            case 'fadeThrough':
              return FadeThroughTransition(
                animation: primaryAnimation,
                secondaryAnimation: secondaryAnimation,
                child: child,
              );
            default:
              return child;
          }
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_selectedIndex),
          child: _screens[_selectedIndex],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: _onItemTapped,
        selectedIndex: _selectedIndex,
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors_rounded),
            label: '连接',
          ),
          NavigationDestination(
            icon: Icon(Icons.keyboard_alt_outlined),
            selectedIcon: Icon(Icons.keyboard_alt),
            label: '键盘',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: '成就',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
