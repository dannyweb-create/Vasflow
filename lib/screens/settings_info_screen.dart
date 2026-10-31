import 'package:flutter/material.dart';

class SettingsInfoScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String summary;
  final List<String> points;
  final String? footnote;

  const SettingsInfoScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.summary,
    required this.points,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: scheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(summary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < points.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.check_circle_outline,
                            size: 20,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(points[i])),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(child: Text(footnote!)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
