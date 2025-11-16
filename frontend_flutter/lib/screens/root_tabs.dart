import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/google_auth_provider.dart';
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
  final _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
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
        Widget page;
        // Si settings.name est null ou '/', on affiche la page principale du tab
        if (settings.name == null || settings.name == '/') {
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
        } else {
          // Pour toute autre route, on affiche la page principale du tab (ou personnaliser si besoin)
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
        }
        return MaterialPageRoute(
          builder: (_) => page,
          settings: settings,
        );
      },
    );
  }

  Future<bool> _onWillPop() async {
    final currentNavigator = _navigatorKeys[_index].currentState;
    if (currentNavigator != null && currentNavigator.canPop()) {
      currentNavigator.pop();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          actions: [
            Builder(
              builder: (context) {
                return PopupMenuButton<String>(
                  icon: const Icon(Icons.account_circle),
                  itemBuilder: (context) {
                    final googleAuth =
                        Provider.of<GoogleAuthProvider>(context, listen: false);
                    if (googleAuth.user != null) {
                      return [
                        PopupMenuItem<String>(
                          value: 'logout',
                          child: Text(
                              'Déconnexion (${googleAuth.user!.displayName})'),
                        ),
                      ];
                    } else {
                      return [
                        PopupMenuItem<String>(
                          value: 'login',
                          child: Text('Se connecter avec Google'),
                        ),
                      ];
                    }
                  },
                  onSelected: (value) async {
                    final googleAuth =
                        Provider.of<GoogleAuthProvider>(context, listen: false);
                    if (value == 'logout') {
                      await googleAuth.signOut();
                      // Retour à l'écran de login
                      Navigator.of(context).pushReplacementNamed('/');
                    } else if (value == 'login') {
                      await googleAuth.signIn();
                    }
                  },
                );
              },
            ),
          ],
        ),
        body: IndexedStack(
          index: _index,
          children: List.generate(4, (i) => _buildTabNavigator(i)),
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
      ),
    );
  }
}
