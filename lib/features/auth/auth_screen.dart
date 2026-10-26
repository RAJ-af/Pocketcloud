import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});
  final VoidCallback onAuthenticated;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _loading = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.length < 8) {
      setState(
        () => _error =
            'Enter a valid email and a password of at least 8 characters.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_signUp) {
        final response = await auth.signUp(email: email, password: password);
        if (response.session == null && mounted) {
          setState(
            () => _error =
                'Check your email to confirm the account, then sign in.',
          );
          return;
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
      if (mounted) widget.onAuthenticated();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not connect. Check internet and Supabase configuration.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your email above first.');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset email requested. Check your inbox.'),
          ),
        );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.cloud_done_rounded,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 11),
                Text(
                  'pocketcloud',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 52),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: AppColors.accent,
                    size: 16,
                  ),
                  SizedBox(width: 7),
                  Text(
                    'YOUR DEVICES. YOUR STORAGE.',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              _signUp
                  ? 'Build your\npersonal cloud.'
                  : 'Your old phone.\nA new purpose.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 14),
            Text(
              _signUp
                  ? 'Create one account to connect the devices you own.'
                  : 'Sign in to reach your PocketCloud devices securely.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: 13),
            TextField(
              controller: _password,
              obscureText: _hidePassword,
              autofillHints: _signUp
                  ? const [AutofillHints.newPassword]
                  : const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
            ),
            if (!_signUp)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _resetPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6, bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.ink,
                      ),
                    )
                  : Text(_signUp ? 'Create account' : 'Sign in'),
            ),
            const SizedBox(height: 13),
            OutlinedButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      _signUp = !_signUp;
                      _error = null;
                    }),
              child: Text(
                _signUp ? 'I already have an account' : 'Create a new account',
              ),
            ),
            const SizedBox(height: 26),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Your account connects your own devices. Pairing alone never grants access without sign-in and device approval.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
