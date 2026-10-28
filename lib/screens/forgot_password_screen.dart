import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}
class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final email = TextEditingController();
  bool busy = false, sent = false;
  String? error;
  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try { await AuthService().resetPassword(email.text); setState(() => sent = true); }
    catch (e) { setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset password')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.mark_email_read_outlined, size: 48),
      const SizedBox(height: 18),
      Text(sent ? 'Check your email' : 'Forgot your password?', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 10),
      Text(sent ? 'If an account exists for that email, Supabase will send a password reset link.' : 'Enter the email address on your account and we’ll send a reset link.', textAlign: TextAlign.center),
      const SizedBox(height: 24),
      if (!sent) TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email address', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email_outlined))),
      if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Colors.red))),
      if (!sent) const SizedBox(height: 14),
      if (!sent) FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Sending…' : 'Send reset link')),
      if (sent) FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back to login')),
    ])))),
  );
}
