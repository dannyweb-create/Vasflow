import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../theme/glass_widgets.dart';

/// The AI Agent tab. It is a DESIGNED placeholder: the architecture and rules
/// are fixed, and every interactive part is clearly disabled because no AI
/// provider is connected or tested yet.
///
/// Privacy rules (enforced by design, and restated on screen):
///  * The agent never reads client records, documents, passwords or keys.
///  * Prompts never contain client data.
///  * The provider key stays server-side, behind a secure proxy, never in
///    this app.
class AiAgentScreen extends StatelessWidget {
  const AiAgentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI Agent')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          GlassPanel(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Brand.deepGreen,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.smart_toy_outlined,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VasFlow Assistant',
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(
                            'General visa & study-abroad know-how',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: scheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block_outlined, size: 15, color: scheme.error),
                      const SizedBox(width: 6),
                      Text(
                        'Not connected yet',
                        style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('What it will help with', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _capabilityTile(
            context,
            Icons.menu_book_outlined,
            'Application procedures',
            'Step-by-step country and university application walkthroughs.',
          ),
          _capabilityTile(
            context,
            Icons.checklist_outlined,
            'General checklists',
            'Templates for intake prep, visa files and pre-departure steps.',
          ),
          _capabilityTile(
            context,
            Icons.drafts_outlined,
            'Email drafts',
            'Follow-up and enquiry drafts you review before sending.',
          ),
          _capabilityTile(
            context,
            Icons.translate_outlined,
            'Translation',
            'Translate standard guidance between English and common source languages.',
          ),
          _capabilityTile(
            context,
            Icons.fact_check_outlined,
            'Document requirements',
            'Explain common visa and admission document sets.',
          ),
          _capabilityTile(
            context,
            Icons.event_repeat_outlined,
            'Follow-up plans',
            'Suggest follow-up schedules you can copy into Tasks.',
          ),
          const SizedBox(height: 16),
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('Privacy rules', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'The assistant never reads client records, the client '
                  'database, uploaded documents, passwords or private keys. '
                  'Anything you type is sent without client data.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dns_outlined, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'How it will connect',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'When enabled, the app talks to a secure Supabase Edge '
                  'Function that holds the AI provider key server-side. The '
                  'key never ships inside the app, and every prompt passes '
                  'through that proxy only.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AbsorbPointer(
            child: TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Ask a question about visa procedures…',
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: scheme.onSurface.withValues(alpha: 0.16),
                  ),
                ),
                prefixIcon: Icon(
                  Icons.chat_bubble_outline,
                  color: scheme.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Chat stays locked until the secure backend is live, tested and '
            'reviewed. Nothing here pretends to answer.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _capabilityTile(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 18,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
