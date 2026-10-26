import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/app_theme.dart';
import '../../services/device_repository.dart';
import '../vault/storage_management_screen.dart';

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
  String _storageMode = 'selected';
  bool _cameraPermission = false;
  bool _notificationPermission = false;
  bool _enableServerMode = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadState();
    }
  }

  Future<void> _loadState() async {
    final mode = await StorageManagementScreen.getSelectedMode();
    if (mounted) {
      setState(() => _storageMode = mode);
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
            _PermissionCard(
              title:
                  'Storage Mode: ${_storageMode == "selected" ? "Selected Files Only" : "Full Shared Storage"}',
              statusText: _storageMode == 'selected'
                  ? 'Mode A (System Picker)'
                  : 'Mode B (Folder/SAF)',
              statusColor: AppColors.accent,
              actionLabel: 'Configure Mode',
              onAction: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const StorageManagementScreen(),
                  ),
                );
                await _loadState();
              },
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('2. Camera Permission (Optional)'),
            const SizedBox(height: 10),
            _PermissionCard(
              title: 'Camera Access for QR Scanning',
              statusText: _cameraPermission ? 'Granted' : 'Not Requested',
              statusColor: _cameraPermission
                  ? AppColors.accent
                  : AppColors.muted,
              actionLabel: _cameraPermission ? 'Granted' : 'Allow Camera',
              onAction: () {
                setState(() => _cameraPermission = !_cameraPermission);
              },
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('3. Notifications (Optional)'),
            const SizedBox(height: 10),
            _PermissionCard(
              title: 'Background Server Notifications',
              statusText: _notificationPermission ? 'Granted' : 'Not Requested',
              statusColor: _notificationPermission
                  ? AppColors.accent
                  : AppColors.muted,
              actionLabel: _notificationPermission
                  ? 'Granted'
                  : 'Allow Notifications',
              onAction: () {
                setState(
                  () => _notificationPermission = !_notificationPermission,
                );
              },
            ),
            const SizedBox(height: 20),
            _buildSectionHeader('4. Server Hosting Mode'),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _enableServerMode,
              onChanged: (val) =>
                  setState(() => _enableServerMode = val ?? false),
              title: const Text('Enable server hosting on this phone'),
              subtitle: const Text('Mark this phone as a personal cloud host.'),
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

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.title,
    required this.statusText,
    required this.statusColor,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String statusText;
  final Color statusColor;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
