import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:injectable/injectable.dart';

@singleton
class LocalizationService {
  final _supportedLocales = [
    const Locale('fr'), // Français
    const Locale('en'), // Anglais
    const Locale('es'), // Espagnol
    const Locale('ar'), // Arabe
  ];

  List<Locale> get supportedLocales => _supportedLocales;

  LocalizationsDelegate<AppLocalizations> get delegate =>
      AppLocalizations.delegate;

  String translate(BuildContext context, String key) {
    return AppLocalizations.of(context)?.getString(key) ?? key;
  }

  bool isRTL(BuildContext context) {
    return Directionality.of(context) == TextDirection.rtl;
  }

  TextDirection getTextDirection(Locale locale) {
    return locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;
  }
}