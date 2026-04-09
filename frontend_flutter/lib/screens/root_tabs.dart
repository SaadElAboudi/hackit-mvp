import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/salons_screen.dart';
import '../providers/search_provider.dart';

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
    GlobalKey<NavigatorState>(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Register a callback so SearchProvider can switch to the chat tab
    // (index 0) whenever a new search or refinement starts.
    context.read<SearchProvider>().onNavigateToChat = () {
      if (mounted && _index != 0) setState(() => _index = 0);
    };
  }

  @override
  void dispose() {
    try {
      context.read<SearchProvider>().onNavigateToChat = null;
    } catch (_) {}
    super.dispose();
  }

  Widget _buildTabNavigator(int tabIndex) {
    return Navigator(
      key: _navigatorKeys[tabIndex],
      initialRoute: '/',
      onGenerateRoute: (settings) {
        final Widget page;
        switch (tabIndex) {
          case 1:
            page = const LibraryScreen();
            break;
          case 2:
            page = const SalonsScreen();
            break;
          default:
            page = const HomeScreen();
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
          children: List.generate(3, (i) => _buildTabNavigator(i)),
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
            NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum_rounded),
              label: 'Salons',
            ),
          ],
        ),
      ),
    );
  }
}
