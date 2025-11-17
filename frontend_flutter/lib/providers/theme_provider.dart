import 'package:flutter/material.dart';

class ThemeProvider with ChangeNotifier {
  ThemeProvider();

  ThemeMode get themeMode => ThemeMode.dark;

  void setThemeMode(ThemeMode mode) {
    notifyListeners();
  }

  void toggleTheme() {
    notifyListeners();
  }
}
