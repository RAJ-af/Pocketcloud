import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_theme.dart';
import '../../core/legal_versions.dart';
import '../../core/policy_text.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _terms = false;
  bool _privacy = false;
  bool _saving = false;
  String? _error;

  Future<void> _saveConsent(bool accepted) async {
    setState(() { _saving = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser!.id;
      final timestamp = DateTime.now().toUtc().toIso8601String();
      await client.from('user_consents').insert([
        {'user_id': userId, 'policy_type': 'terms', 'policy_version': LegalVersions.terms, 'consented': accepted, 'source': 'mobile_onboarding'},
        {'user_id': userId, 'policy_type': 'privacy', 'policy_version': LegalVersions.privacy, 'consented': accepted, 'source': 'mobile_onboarding'},
      ]);
      if (accepted) {
        await client.from('profiles').upsert({'id': userId, 'updated_at': timestamp});
        if (mounted) widget.onComplete();
      } else {
        if (mounted) setState(() => _error = 'Consent declined. PocketCloud setup remains locked. You can sign out or review the policies again.');
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = 'Could not save your decision: ${e.message}. Check that the database migration is applied.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save consent. Check your connection and try again.');
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _decline() async {
    await _saveConsent(false);
    if (mounted && Supabase.instance.client.auth.currentUser != null) {
      // The explicit rejection is stored for audit; user can leave the account.
    }
  }

  Future<void> _showFullPolicy(BuildContext context, String title, String content) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 12),
                Expanded(child: SingleChildScrollView(child: SelectableText(content, style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(height: 1.55)))),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.of(sheetContext).pop(), child: const Text('Close policy'))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: ListView(padding: const EdgeInsets.all(22), children: [
        Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.verified_user_rounded, color: AppColors.ink)), const SizedBox(width: 12), Text('Before we connect', style: Theme.of(context).textTheme.titleLarge)]),
        const SizedBox(height: 26), Text('Your privacy comes first.', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 10), Text('PocketCloud keeps files on your chosen server phone. The cloud backend stores account, device pairing, connection signalling and consent records, not your file contents.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted)),
        const SizedBox(height: 22),
        _PolicyCard(icon: Icons.description_outlined, title: 'Terms & Conditions', version: LegalVersions.terms, body: 'Use only devices and files you own or have permission to access. Pairings are revocable, and you are responsible for securing the server phone and account.', onRead: () => _showFullPolicy(context, 'Terms & Conditions', PolicyText.terms)),
        const SizedBox(height: 12), _PolicyCard(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', version: LegalVersions.privacy, body: 'Account, device, consent and connection metadata are processed. File contents are intended to travel over WebRTC, not be stored in the Supabase database. Some metadata is still visible to service providers.', onRead: () => _showFullPolicy(context, 'Privacy Policy', PolicyText.privacy)),
        const SizedBox(height: 14),
        CheckboxListTile(value: _terms, onChanged: (v) => setState(() => _terms = v ?? false), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: const Text('I agree to the Terms & Conditions'), subtitle: const Text('Required before using server features.'), activeColor: AppColors.accent),
        CheckboxListTile(value: _privacy, onChanged: (v) => setState(() => _privacy = v ?? false), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, title: const Text('I acknowledge the Privacy Policy'), subtitle: const Text('Required to record how account and device metadata is processed.'), activeColor: AppColors.accent),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
        FilledButton(onPressed: _saving || !_terms || !_privacy ? null : () => _saveConsent(true), child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink)) : const Text('Agree & continue')),
        const SizedBox(height: 9), TextButton(onPressed: _saving ? null : _decline, child: const Text('Decline and do not continue')),
        TextButton(onPressed: _saving ? null : () => Supabase.instance.client.auth.signOut(), child: const Text('Sign out')),
        const SizedBox(height: 14), Text('OS permissions are requested only when a feature needs them, such as camera access for QR scanning. This screen does not silently grant Android permissions.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
      ])));
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.icon, required this.title, required this.version, required this.body, required this.onRead});
  final IconData icon; final String title; final String version; final String body; final VoidCallback onRead;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, color: AppColors.accent), const SizedBox(width: 9), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Text(version, style: const TextStyle(fontSize: 10, color: AppColors.muted))]), const SizedBox(height: 10), Text(body, style: const TextStyle(height: 1.5, color: AppColors.muted)), Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: onRead, icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Read full policy')))]));
}
