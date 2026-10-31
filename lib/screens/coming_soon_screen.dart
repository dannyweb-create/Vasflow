import 'package:flutter/material.dart';

class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;
  final List<String> plans;

  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
    required this.plans,
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
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      icon,
                      size: 38,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Coming soon',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
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
                  Text(
                    'What it will do',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < plans.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 13,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(plans[i])),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.construction_outlined),
              title: const Text('Not available yet'),
              subtitle: Text(
                'Nothing is connected or shared with $title in this build. '
                'Your existing VasFlow data stays where it is.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
