import 'package:flutter/material.dart';

class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 350);
}

class AppRadii {
  static const xs = Radius.circular(8);
  static const s = Radius.circular(12);
  static const m = Radius.circular(16);
  static const l = Radius.circular(20);
  static BorderRadius get capsule => BorderRadius.circular(999);
}

class AppElevation {
  static const double low = 2;
  static const double medium = 4;
  static const double high = 8;
}
