import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';

class RootTabs extends StatefulWidget {
  const RootTabs({super.key});

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  final List<String> tabRoutes = [
    '/',
    '/library',
  ];

  int _index = 0;
  final _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Synchronise l'onglet sélectionné avec la route actuelle
    final route = ModalRoute.of(context)?.settings.name;
    if (route != null) {
      final tabIdx = tabRoutes.indexOf(route);
      final legacyLibraryRoutes = {'/lessons', '/favorites', '/history'};
      final resolvedIdx =
          (tabIdx == -1 && legacyLibraryRoutes.contains(route)) ? 1 : tabIdx;
      if (resolvedIdx != -1 && resolvedIdx != _index) {
        setState(() => _index = resolvedIdx);
      }
    }
  }

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
              // Met à jour la route pour deep linking
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
