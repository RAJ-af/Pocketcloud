import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'core/legal_versions.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/permission_setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }
  runApp(const PocketCloudApp());
}

class PocketCloudApp extends StatelessWidget {
  const PocketCloudApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PocketCloud',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: const AppGate(),
  );
}

class AppGate extends StatefulWidget {
  const AppGate({super.key});
  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  int _revision = 0;
  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isConfigured) return const SetupRequiredScreen();
    final client = Supabase.instance.client;
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      builder: (context, authSnapshot) {
        final session =
            authSnapshot.data?.session ?? client.auth.currentSession;
        if (session == null)
          return AuthScreen(
            key: const ValueKey('auth'),
            onAuthenticated: () {},
          );
        return FutureBuilder<bool>(
          key: ValueKey(
            '${session.user.id}:$_revision:${authSnapshot.data?.event}',
          ),
          future: ConsentRepository.hasCurrentConsent(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            if (snapshot.hasError)
              return ErrorScreen(
                message:
                    'Could not verify privacy consent. Check your connection and retry.',
                onRetry: () => setState(() => _revision++),
              );
            if (snapshot.data == true) {
              return FutureBuilder<bool>(
                future: PermissionSetupScreen.isSetupCompleted(),
                builder: (context, setupSnapshot) {
                  if (setupSnapshot.connectionState != ConnectionState.done) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (setupSnapshot.data == true) {
                    return const HomeScreen();
                  }
                  return PermissionSetupScreen(
                    onComplete: () => setState(() => _revision++),
                  );
                },
              );
            }
            return OnboardingScreen(
              onComplete: () => setState(() => _revision++),
            );
          },
        );
      },
    );
  }
}

class ConsentRepository {
  static const termsVersion = LegalVersions.terms;
  static const privacyVersion = LegalVersions.privacy;

  static Future<bool> hasCurrentConsent() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return false;

    final terms = await client
        .from('user_consents')
        .select('consented')
        .eq('user_id', uid)
        .eq('policy_type', 'terms')
        .eq('policy_version', termsVersion)
        .order('decided_at', ascending: false)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();
    final privacy = await client
        .from('user_consents')
        .select('consented')
        .eq('user_id', uid)
        .eq('policy_type', 'privacy')
        .eq('policy_version', privacyVersion)
        .order('decided_at', ascending: false)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();

    return terms?['consented'] == true && privacy?['consented'] == true;
  }
}

class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _BrandMark(),
            const SizedBox(height: 28),
            Text(
              'Your own cloud.\nYour own rules.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 14),
            Text(
              'PocketCloud needs your Supabase project URL and publishable key before sign-in can work.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            const _InfoTile(
              icon: Icons.terminal_rounded,
              title: 'Configure the build',
              detail:
                  'Use the GitHub Actions workflow or pass --dart-define values locally.',
            ),
            const SizedBox(height: 10),
            const _InfoTile(
              icon: Icons.lock_outline_rounded,
              title: 'Never add secret keys',
              detail:
                  'The service-role key must never appear in Flutter or in a public APK.',
            ),
            const SizedBox(height: 24),
            SelectableText(
              'SUPABASE_URL\nSUPABASE_PUBLISHABLE_KEY',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.accent),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Icon(
          Icons.cloud_done_rounded,
          color: AppColors.ink,
          size: 27,
        ),
      ),
      const SizedBox(width: 12),
      Text(
        'pocketcloud',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
      ),
    ],
  );
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(color: AppColors.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
