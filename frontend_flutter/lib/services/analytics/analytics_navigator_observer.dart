import 'package:flutter/material.dart';
import '../services/analytics/analytics_manager.dart';

class AnalyticsNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _trackScreenView(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _trackScreenView(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      _trackScreenView(previousRoute);
    }
  }

  void _trackScreenView(Route<dynamic> route) {
    if (route is PageRoute) {
      final String screenName = route.settings.name ?? route.runtimeType.toString();
      AnalyticsManager.instance.trackScreenView(
        screenName: screenName,
        screenClass: route.runtimeType.toString(),
      );
    }
  }
}