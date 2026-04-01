import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/lessons_screen.dart';
import '../screens/favorites_screen.dart';
import '../screens/history_screen.dart';

class RootTabs extends StatefulWidget {
  const RootTabs({super.key});

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  final List<String> tabRoutes = [
    '/',
    '/lessons',
    '/favorites',
    '/history',
  ];

  int _index = 0;
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.settings.name;
    if (route != null) {
      final tabIdx = tabRoutes.indexOf(route);
      if (tabIdx != -1 && tabIdx != _index) {
        setState(() => _index = tabIdx);
      }
    }
  }

  Widget _buildTabNavigator(int tabIndex) {
    return Navigator(
      key: _navigatorKeys[tabIndex],
      initialRoute: '/',
      onGenerateRoute: (settings) {
        late final Widget page;
        switch (tabIndex) {
          case 0:
            page = const HomeScreen();
            break;
          case 1:
            page = const LessonsScreen();
            break;
          case 2:
            page = const FavoritesScreen();
            break;
          case 3:
            page = const HistoryScreen();
            break;
          default:
            page = const HomeScreen();
        }
        return MaterialPageRoute(builder: (_) => page, settings: settings);
      },
    );
  }

  void _onPopInvoked(bool didPop) {
    if (didPop) return;
    final currentNavigator = _navigatorKeys[_index].currentState;
    if (currentNavigator != null && currentNavigator.canPop()) {
      currentNavigator.pop();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _index,
          children: List.generate(4, (i) => _buildTabNavigator(i)),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            if (i != _index) {
              setState(() => _index = i);
              final routeName = tabRoutes[i];
              if (ModalRoute.of(context)?.settings.name != routeName) {
                Navigator.of(context).pushReplacementNamed(routeName);
              }
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chat',
            ),
            NavigationDestination(
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school_rounded),
              label: 'Lecons',
            ),
            NavigationDestination(
              icon: Icon(Icons.star_border_rounded),
              selectedIcon: Icon(Icons.star_rounded),
              label: 'Favoris',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              selectedIcon: Icon(Icons.history_toggle_off_rounded),
              label: 'Historique',
            ),
          ],
        ),
      ),
    );
  }
}
