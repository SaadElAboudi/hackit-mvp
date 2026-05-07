import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/room_provider.dart';
import '../screens/home_overview_screen.dart';
import '../screens/salons_screen.dart';
import '../screens/my_day_screen.dart';

/// Navigation principale simplifiee: Accueil, Priorites, Salons.
class RootTabs extends StatefulWidget {
  const RootTabs({super.key});

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _selectedIndex = 0;
  late final List<Widget?> _loadedTabs;

  void _goToTab(int index) {
    setState(() {
      _selectedIndex = index;
      _loadedTabs[index] ??= _buildTab(index);
    });
  }

  @override
  void initState() {
    super.initState();
    _loadedTabs = List<Widget?>.filled(3, null);
    _loadedTabs[_selectedIndex] = _buildTab(_selectedIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prov = context.read<RoomProvider>();
      await prov.loadRooms();

      if (!mounted) return;

      final hasRoom = await prov.ensureCurrentRoom(createIfMissing: true);

      if (mounted && !hasRoom && _selectedIndex == 0) {
        setState(() {
          _selectedIndex = 2;
          _loadedTabs[_selectedIndex] = _buildTab(_selectedIndex);
        });
      }
    });
  }

  Widget _buildTab(int index) {
    switch (index) {
      case 0:
        return HomeOverviewScreen(
          onOpenPriorities: () => _goToTab(1),
          onOpenSalons: () => _goToTab(2),
        );
      case 1:
        return const MyDayScreen();
      case 2:
        return const SalonsScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: List<Widget>.generate(3, (index) {
          return _loadedTabs[index] ?? const SizedBox.shrink();
        }),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            _loadedTabs[index] ??= _buildTab(index);
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.playlist_add_check_circle_outlined),
            selectedIcon: Icon(Icons.playlist_add_check_circle),
            label: 'Priorites',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Salons',
          ),
        ],
      ),
    );
  }
}
