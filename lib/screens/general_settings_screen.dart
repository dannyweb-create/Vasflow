import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class GeneralSettingsScreen extends StatelessWidget {
  final AuthService auth;

  const GeneralSettingsScreen({super.key, required this.auth});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('General settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Workspace',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.business_outlined,
                    label: 'Name',
                    value:
                        auth.workspaceName.isEmpty
                            ? 'Not loaded'
                            : auth.workspaceName,
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Your role',
                    value: auth.role.toUpperCase(),
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.mail_outline,
                    label: 'Signed in as',
                    value:
                        auth.currentEmail.isEmpty
                            ? 'No email on this account'
                            : auth.currentEmail,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                auth.online
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                color: auth.online ? scheme.primary : scheme.error,
              ),
              title: Text(auth.online ? 'Connected' : 'Offline build'),
              subtitle: Text(
                auth.online
                    ? 'Workspace data is synced with Supabase. Access rules '
                        'are enforced by the server.'
                    : 'This build is not connected to a Supabase project, so '
                        'workspace settings and account changes are limited.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.manage_accounts_outlined),
              title: Text('Workspace-wide settings'),
              subtitle: Text(
                'Workspace membership and server-side policies are managed '
                'by your Admin in Supabase. Use Consultants to invite staff, '
                'and Backup and recovery to keep a protected copy of the '
                'workspace.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
