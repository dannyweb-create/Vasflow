import 'package:flutter/material.dart';

Color documentStatusColor(BuildContext context, String status) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  Color pick(Color light, Color darkColor) => dark ? darkColor : light;
  return switch (status) {
    'Approved' => pick(const Color(0xFF0A7B3E), const Color(0xFF6FDE94)),
    'Under review' => pick(const Color(0xFF0E7490), const Color(0xFF5FC8D8)),
    'Rejected' => pick(const Color(0xFFB42318), const Color(0xFFFF8A80)),
    'Needs replacement' => pick(
      const Color(0xFFB45309),
      const Color(0xFFE0A25A),
    ),
    _ => pick(const Color(0xFF54705F), const Color(0xFF9DB8AA)),
  };
}

class DocumentStatusBadge extends StatelessWidget {
  final String status;

  const DocumentStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = documentStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.2 : 0.1,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
