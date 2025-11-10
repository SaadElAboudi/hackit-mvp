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
  int _index = 0;
  final _pages = const [
    HomeScreen(),
    LessonsScreen(),
    FavoritesScreen(),
    HistoryScreen()
  ];
  final _pageKeys = [
    const PageStorageKey('tab_chat'),
    const PageStorageKey('tab_lessons'),
    const PageStorageKey('tab_favorites'),
    const PageStorageKey('tab_history'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: List.generate(
            _pages.length,
            (i) => KeyedSubtree(
                  key: _pageKeys[i],
                  child: _pages[i],
                )),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: 'Leçons',
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
    );
  }
}
