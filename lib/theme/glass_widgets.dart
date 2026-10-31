import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'brand.dart';

bool isGlass(BuildContext context) =>
    Theme.of(context).extension<GlassStyle>() != null;

/// Soft green gradient with a few colour glows. It is painted once per page and
/// uses no blur, so it is cheap. Cards float on top of it in the glass theme.
class GlassBackdrop extends StatelessWidget {
  final Widget child;
  const GlassBackdrop({super.key, required this.child});

  static Widget _glow(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.9),
                radius: 1.25,
                colors: [
                  Brand.darkGradientCore,
                  Brand.darkGradientMid,
                  Brand.darkGradientEdge,
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -130,
            left: -100,
            child: _glow(320, Brand.darkGlow.withValues(alpha: 0.42)),
          ),
          Positioned(
            top: -90,
            right: -110,
            child: _glow(300, Brand.green.withValues(alpha: 0.26)),
          ),
          Positioned(
            bottom: -180,
            left: -90,
            child: _glow(360, Brand.deepGreen.withValues(alpha: 0.20)),
          ),
          child,
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEAF8EF), Color(0xFFD3F0DE), Color(0xFFE6F5EF)],
            ),
          ),
        ),
        Positioned(
          top: -90,
          left: -70,
          child: _glow(260, Brand.green.withValues(alpha: 0.30)),
        ),
        Positioned(
          top: 240,
          right: -120,
          child: _glow(300, const Color(0xFF3FD0C9).withValues(alpha: 0.24)),
        ),
        Positioned(
          bottom: -130,
          left: -50,
          child: _glow(330, Brand.deepGreen.withValues(alpha: 0.20)),
        ),
        child,
      ],
    );
  }
}

/// In the glass theme every page gets its own opaque gradient background, so
/// pages never show through each other while they slide in and out.
class GlassPageTransitionsBuilder extends PageTransitionsBuilder {
  const GlassPageTransitionsBuilder();

  static const PageTransitionsBuilder _inner = ZoomPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _inner.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      GlassBackdrop(child: child),
    );
  }
}

/// A card that is a normal card in Light and Dark, and a frosted glass panel
/// (blur, translucent fill, glossy edge, soft shadow) in Liquid Glass.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadii.card,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!isGlass(context) && !dark) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
    }
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow:
            dark
                ? AppShadows.glass
                : [
                  BoxShadow(
                    color: Brand.deepGreen.withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: dark ? 18 : 14,
            sigmaY: dark ? 18 : 14,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors:
                      dark
                          ? const [
                            Brand.darkGlassFillTop,
                            Brand.darkGlassFillBottom,
                          ]
                          : [
                            Colors.white.withValues(alpha: 0.74),
                            Colors.white.withValues(alpha: 0.40),
                          ],
                ),
                border: Border.all(
                  color:
                      dark
                          ? Brand.darkGlassBorder
                          : Colors.white.withValues(alpha: 0.85),
                  width: 1,
                ),
              ),
              child: InkWell(
                borderRadius: borderRadius,
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
