import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import '../services/analytics_service.dart';

@singleton
class GlobalErrorHandler {
  final AnalyticsService _analytics;
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey;

  GlobalErrorHandler(this._analytics)
      : _scaffoldKey = GlobalKey<ScaffoldMessengerState>();

  GlobalKey<ScaffoldMessengerState> get scaffoldKey => _scaffoldKey;

  Future<void> handleError(Object error, StackTrace stackTrace) async {
    // Log l'erreur
    await _analytics.logError(error.toString(), stackTrace);

    // Afficher un message à l'utilisateur
    _showErrorSnackBar(error);
  }

  void _showErrorSnackBar(Object error) {
    final message = _getErrorMessage(error);
    _scaffoldKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            _scaffoldKey.currentState?.hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  String _getErrorMessage(Object error) {
    if (error is NetworkError) {
      return 'Erreur de connexion. Veuillez vérifier votre connexion internet.';
    } else if (error is ServerError) {
      return 'Erreur serveur. Veuillez réessayer plus tard.';
    } else if (error is ValidationError) {
      return error.message;
    } else {
      return 'Une erreur inattendue s\'est produite.';
    }
  }
}

class NetworkError implements Exception {
  final String message;
  NetworkError([this.message = 'Network error occurred']);
}

class ServerError implements Exception {
  final String message;
  ServerError([this.message = 'Server error occurred']);
}

class ValidationError implements Exception {
  final String message;
  ValidationError(this.message);
}

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final GlobalErrorHandler errorHandler;

  const ErrorBoundary({
    super.key,
    required this.child,
    required this.errorHandler,
  });

  @override
  ErrorBoundaryState createState() => ErrorBoundaryState();
}

class ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    FlutterError.onError = _handleFlutterError;
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    setState(() {
      _hasError = true;
    });
    widget.errorHandler.handleError(
      details.exception,
      details.stack ?? StackTrace.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Material(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Oops! Une erreur s\'est produite.',
                style: TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _hasError = false;
                  });
                },
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}