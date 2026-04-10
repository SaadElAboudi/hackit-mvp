import 'package:flutter/material.dart';
import '../screens/salons_screen.dart';

/// Single-tab root: only the Salons experience.
/// The former "Recherche" tab has been removed.
class RootTabs extends StatelessWidget {
  const RootTabs({super.key});

  @override
  Widget build(BuildContext context) {
    return const SalonsScreen();
  }
}
