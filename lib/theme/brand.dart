import 'package:flutter/material.dart';

/// VasFlow brand colours.
class Brand {
  static const green = Color(0xFF0BA84A);
  static const deepGreen = Color(0xFF075B43);
  static const mint = Color(0xFFE2F6E9);
  static const lightBackground = Color(0xFFF7FAF7);
  static const darkBackground = Color(0xFF101713);
  static const text = Color(0xFF18352B);
  static const white = Color(0xFFFFFFFF);

  /// Text/icon colour used on top of the brand green. Dark, because white on
  /// #0BA84A is only about 3.1:1 contrast and this is about 5:1.
  static const onGreen = Color(0xFF04210F);
}

enum AppThemeChoice {
  light('Light', 'Clean white backgrounds with green accents'),
  dark('Dark', 'Near-black backgrounds that are easy on the eyes'),
  glass('Liquid Glass', 'Frosted, translucent surfaces with soft highlights');

  const AppThemeChoice(this.label, this.description);
  final String label;
  final String description;
}

/// Marker added to the Liquid Glass theme so widgets can tell it is active.
@immutable
class GlassStyle extends ThemeExtension<GlassStyle> {
  const GlassStyle();

  @override
  GlassStyle copyWith() => this;

  @override
  GlassStyle lerp(ThemeExtension<GlassStyle>? other, double t) => this;
}
