import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../core/error/global_error_handler.dart';
import '../services/analytics_service.dart';
import '../services/performance_monitor.dart';

class AppBlocObserver extends BlocObserver {
  final GlobalErrorHandler _errorHandler;
  final AnalyticsService _analytics;
  final PerformanceMonitor _performance;

  AppBlocObserver(
    this._errorHandler,
    this._analytics,
    this._performance,
  );

  @override
  void onCreate(BlocBase bloc) {
    super.onCreate(bloc);
    _analytics.logEvent(
      name: 'bloc_created',
      parameters: {'bloc': bloc.runtimeType.toString()},
    );
  }

  @override
  void onEvent(Bloc bloc, Object? event) {
    super.onEvent(bloc, event);
    
    _performance.startTrace('bloc_event_${event.runtimeType}');
    
    _analytics.logEvent(
      name: 'bloc_event',
      parameters: {
        'bloc': bloc.runtimeType.toString(),
        'event': event.runtimeType.toString(),
      },
    );
  }

  @override
  void onTransition(Bloc bloc, Transition transition) {
    super.onTransition(bloc, transition);

    _performance.endTrace('bloc_event_${transition.event.runtimeType}');
    
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'bloc',
        message: 'Bloc transition in ${bloc.runtimeType}',
        data: {
          'event': transition.event.toString(),
          'currentState': transition.currentState.toString(),
          'nextState': transition.nextState.toString(),
        },
        level: SentryLevel.info,
      ),
    );
  }

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    _errorHandler.handleError(error, stackTrace);
  }

  @override
  void onClose(BlocBase bloc) {
    super.onClose(bloc);
    _analytics.logEvent(
      name: 'bloc_closed',
      parameters: {'bloc': bloc.runtimeType.toString()},
    );
  }
}