import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization_service.dart';

class AccessibilityService {
  final LocalizationService _localizationService;

  AccessibilityService(this._localizationService);

  void announcePageChange(BuildContext context, String pageName) {
    final message = _localizationService.translate(
      context,
      'pageChanged',
      {'page': pageName},
    );
    SemanticsService.announce(message, TextDirection.ltr);
  }

  void announceLoadingState(BuildContext context, bool isLoading) {
    if (isLoading) {
      final message = _localizationService.translate(context, 'loading');
      SemanticsService.announce(message, TextDirection.ltr);
    }
  }

  void announceError(BuildContext context, String error) {
    SemanticsService.announce(error, TextDirection.ltr);
  }

  void announceSuccess(BuildContext context, String message) {
    SemanticsService.announce(message, TextDirection.ltr);
  }

  SemanticsProperties getVideoCardSemantics(BuildContext context, VideoModel video) {
    return SemanticsProperties(
      label: video.title,
      value: video.description,
      hint: _localizationService.translate(
        context,
        'tapToViewVideo',
      ),
    );
  }

  SemanticsProperties getButtonSemantics(BuildContext context, String label) {
    return SemanticsProperties(
      button: true,
      enabled: true,
      label: label,
    );
  }

  void handleKeyboardShortcut(
    BuildContext context,
    RawKeyEvent event,
    FocusNode focusNode,
  ) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        // Gérer la touche Échap
        FocusScope.of(context).unfocus();
      } else if (event.logicalKey == LogicalKeyboardKey.tab) {
        // Gérer la navigation au clavier
        if (event.isShiftPressed) {
          FocusScope.of(context).previousFocus();
        } else {
          FocusScope.of(context).nextFocus();
        }
      }
    }
  }
}