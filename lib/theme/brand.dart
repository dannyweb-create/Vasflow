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

  // Liquid-glass dark palette. The backdrop fades from an emerald glow at the
  // top to near black at the edges, while cards stay translucent green-black.
  static const darkGlow = Color(0xFF16A55F);
  static const darkGradientCore = Color(0xFF0C4A31);
  static const darkGradientMid = Color(0xFF071E15);
  static const darkGradientEdge = Color(0xFF030A07);
  static const darkGlassFillTop = Color(0xCC142A20);
  static const darkGlassFillBottom = Color(0xB30B2017);
  static const darkGlassBorder = Color(0x4D6BE59A);
  static const darkCardFill = Color(0xCC13271E);
}

/// Shared corner radii so every surface keeps the same soft geometry.
class AppRadii {
  static const card = 24.0;
  static const panel = 28.0;
  static const button = 16.0;
  static const nav = 32.0;
}

/// Reusable shadows for glass surfaces and the glowing primary action button.
class AppShadows {
  static const glass = <BoxShadow>[
    BoxShadow(color: Color(0x66010805), blurRadius: 30, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x140BA84A), blurRadius: 18, offset: Offset(0, 2)),
  ];

  static const glow = <BoxShadow>[
    BoxShadow(
      color: Color(0x730BA84A),
      blurRadius: 26,
      spreadRadius: 2,
      offset: Offset(0, 8),
    ),
  ];
}

/// Layout constants shared by the shell and the tab screens it hosts.
class AppLayout {
  static const navBarHeight = 66.0;
  static const navBarMargin = 12.0;
  static const navBarClearance = 108.0;
  static const bottomContentPadding = 128.0;
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
