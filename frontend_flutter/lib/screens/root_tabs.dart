import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/room_provider.dart';
import '../screens/salons_screen.dart';
import '../screens/my_day_screen.dart';
import '../screens/inbox_screen.dart';
import '../screens/ops_hub_screen.dart';
import '../screens/execution_board_screen.dart';

/// Root tab navigation: Ops Hub (default) + Channels.
class RootTabs extends StatefulWidget {
  const RootTabs({super.key});

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prov = context.read<RoomProvider>();
      await prov.loadRooms();
      await prov.loadTemplates();
      await prov.loadTemplateStats();

      if (!mounted) return;

      final hasRoom = await prov.ensureCurrentRoom(createIfMissing: true);
      if (hasRoom) {
        await prov.refreshExecutionPulse(silent: true);
        await prov.loadFeedbackDigest(silent: true);
      }

      if (mounted && !hasRoom && _selectedIndex == 0) {
        setState(() {
          _selectedIndex = 1;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          OpsHubScreen(),
          MyDayScreen(),
          InboxScreen(),
          SalonsScreen(),
          ExecutionBoardScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Ops Hub',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'My Day',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox),
            label: 'Inbox',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Channels',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Kanban',
          ),
        ],
      ),
    );
  }
}
