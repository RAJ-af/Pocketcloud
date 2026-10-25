import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/app_theme.dart';
import '../../services/device_repository.dart';

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;

  static const _setupCompleteKey = 'pocketcloud.onboarding_setup_completed';

  static Future<bool> isSetupCompleted() async {
    const storage = FlutterSecureStorage();
    final value = await storage.read(key: _setupCompleteKey);
    return value == 'true';
  }

  static Future<void> markSetupCompleted() async {
    const storage = FlutterSecureStorage();
    await storage.write(key: _setupCompleteKey, value: 'true');
  }

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen>
    with WidgetsBindingObserver {
  bool _cameraPermission = false;
  bool _notificationPermission = false;
  String _storageMode = 'selected'; // 'selected' or 'full'
  bool _enableServerMode = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
  }

  Future<void> _finishSetup() async {
    setState(() => _saving = true);
    try {
      if (_enableServerMode) {
        final repo = DeviceRepository();
        final device = await repo.ensureThisDevice();
        await repo.setServerEnabled(device['id'] as String, true);
      }
      await PermissionSetupScreen.markSetupCompleted();
      if (mounted) widget.onComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not complete setup: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions & Setup'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _saving ? null : _finishSetup,
            child: const Text('Skip optional'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Set up PocketCloud',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Configure how PocketCloud accesses files and handles connections on this phone.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('1. Storage Access Mode'),
            const SizedBox(height: 10),
            RadioListTile<String>(
              value: 'selected',
              groupValue: _storageMode,
              onChanged: (v) => setState(() => _storageMode = v ?? 'selected'),
              title: const Text(
                'Selected files only (Recommended)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Pick individual or multiple files as needed using the system file picker. Broad storage permissions are not requested.',
              ),
            ),
            RadioListTile<String>(
              value: 'full',
              groupValue: _storageMode,
              onChanged: (v) => setState(() => _storageMode = v ?? 'full'),
              title: const Text(
                'Full shared-storage access',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Grants broad folder/file access on this phone via Storage Access Framework or Manage External Storage for host phone library sharing.',
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('2. Camera Permission (Optional)'),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _cameraPermission,
              onChanged: (val) => setState(() => _cameraPermission = val),
              title: const Text('Camera access for QR pairing'),
              subtitle: const Text(
                'Used only when scanning the host device’s QR code to pair phone-to-phone quickly.',
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionHeader('3. Notifications (Optional)'),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _notificationPermission,
              onChanged: (val) => setState(() => _notificationPermission = val),
              title: const Text('Background server notifications'),
              subtitle: const Text(
                'Keep notifications active when hosting files in server mode.',
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('4. Server Hosting Mode'),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _enableServerMode,
              onChanged: (val) =>
                  setState(() => _enableServerMode = val ?? false),
              title: const Text('Enable server mode on this phone'),
              subtitle: const Text(
                'Mark this phone as a personal cloud host so other paired devices can connect and read files.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _finishSetup,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.ink,
                        ),
                      )
                    : const Text('Complete setup & open Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18),
    );
  }
}
