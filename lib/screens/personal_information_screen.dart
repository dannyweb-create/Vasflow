import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class PersonalInformationScreen extends StatelessWidget {
  final AuthService auth;

  const PersonalInformationScreen({super.key, required this.auth});

  @override
  Widget build(BuildContext context) {
    final email =
        auth.currentEmail.isEmpty
            ? 'No email on this account'
            : auth.currentEmail;
    final name = auth.displayName.isEmpty ? 'Not set' : auth.displayName;
    return Scaffold(
      appBar: AppBar(title: const Text('Personal information')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Name'),
                  subtitle: Text(name),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('Email'),
                  subtitle: Text(email),
                  trailing: const Icon(Icons.lock_outline, size: 18),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('Role'),
                  subtitle: Text(auth.role.toUpperCase()),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.business_outlined),
                  title: const Text('Workspace'),
                  subtitle: Text(
                    auth.workspaceName.isEmpty
                        ? 'Not loaded'
                        : auth.workspaceName,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Email is read-only'),
              subtitle: Text(
                auth.isAdmin
                    ? 'Change your name and photo from Admin profile. Your '
                        'email is tied to the Supabase account and cannot be '
                        'edited inside VasFlow.'
                    : 'Ask your workspace Admin to update account details. '
                        'Your email is tied to the Supabase account and '
                        'cannot be edited inside VasFlow.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
