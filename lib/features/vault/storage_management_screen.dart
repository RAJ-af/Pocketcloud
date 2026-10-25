import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/app_theme.dart';

class StorageManagementScreen extends StatefulWidget {
  const StorageManagementScreen({super.key});

  static const _storageModeKey = 'pocketcloud.storage_mode';
  static const _grantedTreeKey = 'pocketcloud.granted_tree_uri';

  static Future<String> getSelectedMode() async {
    const storage = FlutterSecureStorage();
    return (await storage.read(key: _storageModeKey)) ?? 'selected';
  }

  static Future<void> setSelectedMode(String mode) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: _storageModeKey, value: mode);
  }

  static Future<String?> getGrantedTreeUri() async {
    const storage = FlutterSecureStorage();
    return await storage.read(key: _grantedTreeKey);
  }

  static Future<void> setGrantedTreeUri(String? uri) async {
    const storage = FlutterSecureStorage();
    if (uri == null) {
      await storage.delete(key: _grantedTreeKey);
    } else {
      await storage.write(key: _grantedTreeKey, value: uri);
    }
  }

  @override
  State<StorageManagementScreen> createState() =>
      _StorageManagementScreenState();
}

class _StorageManagementScreenState extends State<StorageManagementScreen>
    with WidgetsBindingObserver {
  String _currentMode = 'selected';
  String? _grantedFolderUri;
  bool _loading = true;

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
    setState(() => _loading = true);
    final mode = await StorageManagementScreen.getSelectedMode();
    final tree = await StorageManagementScreen.getGrantedTreeUri();
    if (mounted) {
      setState(() {
        _currentMode = mode;
        _grantedFolderUri = tree;
        _loading = false;
      });
    }
  }

  Future<void> _switchMode(String newMode) async {
    await StorageManagementScreen.setSelectedMode(newMode);
    setState(() => _currentMode = newMode);
  }

  Future<void> _pickFolderSaf() async {
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath();
      if (selectedDirectory != null) {
        await StorageManagementScreen.setGrantedTreeUri(selectedDirectory);
        if (mounted) {
          setState(() => _grantedFolderUri = selectedDirectory);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Folder selected: $selectedDirectory')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select folder: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage Access Mode')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Storage Access Settings',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose how PocketCloud accesses files on this phone. PocketCloud never accesses other applications’ private data.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                _ModeCard(
                  title: 'Selected files only',
                  modeKey: 'selected',
                  activeMode: _currentMode,
                  badge: 'Recommended',
                  description:
                      'Uses Android’s system file picker (Storage Access Framework). You pick individual or multiple files as needed. No broad storage permissions required.',
                  onSelect: () => _switchMode('selected'),
                ),
                const SizedBox(height: 14),
                _ModeCard(
                  title: 'Full shared-storage access',
                  modeKey: 'full',
                  activeMode: _currentMode,
                  badge: 'Broad Access',
                  description:
                      'Provides access to shared folders or external storage on this phone via SAF folder selection or All Files Access where supported. Required if hosting full shared directories as a server.',
                  onSelect: () => _switchMode('full'),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Access Status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Active Mode: ${_currentMode == "selected" ? "Selected files only" : "Full shared-storage access"}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Granted Folder: ${_grantedFolderUri ?? "None selected"}',
                      ),
                      const SizedBox(height: 14),
                      if (_currentMode == 'full') ...[
                        ElevatedButton.icon(
                          onPressed: _pickFolderSaf,
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('Select Shared Folder (SAF)'),
                        ),
                        const SizedBox(height: 10),
                      ],
                      OutlinedButton.icon(
                        onPressed: () {
                          if (Platform.isAndroid) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Open Android Settings -> Apps -> PocketCloud -> Permissions to manage permissions.',
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.settings_rounded),
                        label: const Text('Open Android Settings'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Storage Locations Explained',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '• App-Private Vault: Local encrypted/app-isolated folder where received files and imported library items live.\n'
                        '• Shared Storage: Phone folders (e.g. Downloads, Documents, Media) accessible when in Full shared-storage mode.\n'
                        '• Remote Server: Files hosted on a separate paired phone when connected over WebRTC.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                          height: 1.4,
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.modeKey,
    required this.activeMode,
    required this.badge,
    required this.description,
    required this.onSelect,
  });

  final String title;
  final String modeKey;
  final String activeMode;
  final String badge;
  final String description;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = activeMode == modeKey;

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: isSelected ? AppColors.accent : AppColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
