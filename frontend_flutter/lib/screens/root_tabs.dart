import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';

class RootTabs extends StatefulWidget {
  const RootTabs({super.key});

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _index = 0;
  final _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  Widget _buildTabNavigator(int tabIndex) {
    return Navigator(
      key: _navigatorKeys[tabIndex],
      initialRoute: '/',
      onGenerateRoute: (settings) {
        Widget page;
        // Si settings.name est null ou '/', on affiche la page principale du tab
        if (settings.name == null || settings.name == '/') {
          switch (tabIndex) {
            case 0:
              page = const HomeScreen();
              break;
            case 1:
              page = const LibraryScreen();
              break;
            default:
              page = const HomeScreen();
          }
        } else {
          // Pour toute autre route, on affiche la page principale du tab (ou personnaliser si besoin)
          switch (tabIndex) {
            case 0:
              page = const HomeScreen();
              break;
            case 1:
              page = const LibraryScreen();
              break;
            default:
              page = const HomeScreen();
          }
        }
        return MaterialPageRoute(
          builder: (_) => page,
          settings: settings,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        final currentNavigator = _navigatorKeys[_index].currentState;
        if (currentNavigator != null && currentNavigator.canPop()) {
          currentNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: List.generate(2, (i) => _buildTabNavigator(i)),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            if (i != _index) {
              setState(() => _index = i);
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chat',
            ),
            NavigationDestination(
              icon: Icon(Icons.collections_bookmark_outlined),
              selectedIcon: Icon(Icons.collections_bookmark_rounded),
              label: 'Pipeline',
            ),
          ],
        ),
      ),
    );
  }
}
