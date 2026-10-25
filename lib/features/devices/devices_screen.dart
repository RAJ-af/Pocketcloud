import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../services/device_repository.dart';
import '../remote/remote_files_screen.dart';
import 'pairing_scanner_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _repo = DeviceRepository();
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  String? _error;
  String? _pairCode;
  String? _localDeviceId;
  List<Map<String, dynamic>> _pairs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final current = await _repo.ensureThisDevice();
      final data = await _repo.listDevices();
      final pairs = await _repo.listPairs();
      if (mounted) {
        setState(() {
          _localDeviceId = current['id'];
          _devices = List<Map<String, dynamic>>.from(data);
          _pairs = List<Map<String, dynamic>>.from(pairs);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load devices. Apply the Supabase migration and check RLS.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _makeCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _createPairCode(
    Map<String, dynamic> device, {
    required bool allowUpload,
  }) async {
    final code = _makeCode();
    final hash = sha256.convert(utf8.encode(code)).toString();
    try {
      await Supabase.instance.client.from('pairing_codes').insert({
        'owner_id': Supabase.instance.client.auth.currentUser!.id,
        'server_device_id': device['id'],
        'code_hash': hash,
        'can_upload': allowUpload,
      });
      if (mounted) {
        setState(() => _pairCode = code);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create pairing code. Ensure this device is marked as a server.')),
        );
      }
    }
  }

  Future<void> _startPairing(Map<String, dynamic> device) async {
    var allowUpload = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const Text('Create pairing code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Generate a one-time pairing code for this server.'),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: allowUpload,
                onChanged: (value) => setDialogState(() => allowUpload = value ?? false),
                title: const Text('Allow uploads to this server'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Generate')),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _createPairCode(device, allowUpload: allowUpload);
    }
  }

  Future<void> _redeemCode({String? suppliedCode}) async {
    String? code = suppliedCode;
    if (code == null) {
      final controller = TextEditingController();
      code = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pair with a server'),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(hintText: 'Enter 12-character code'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Pair')),
          ],
        ),
      );
      controller.dispose();
    }

    if (code == null || code.length != 12) return;

    try {
      final localId = _localDeviceId;
      if (localId == null) throw StateError('This device has not finished registering.');

      final result = await Supabase.instance.client.functions.invoke(
        'redeem-pairing',
        body: {'code': code, 'clientDeviceId': localId},
      );
      if (result.status < 200 || result.status >= 300) {
        throw StateError('Pairing was rejected.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Devices paired. Upload access follows the server owner’s choice.')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pairing failed: ${e is StateError ? e.message : 'Check code and connection.'}')),
        );
      }
    }
  }

  Future<void> _confirmRevoke(Map<String, dynamic> device) async {
    if (device['id'] == _localDeviceId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot revoke the device you are using. Sign out and revoke it from another device instead.')),
        );
      }
      return;
    }

    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Revoke device?'),
        content: Text('Revoke access for ${device['name'] ?? 'this device'}? Existing server files stay local, and the pairing can be re-created later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Revoke')),
        ],
      ),
    );

    if (yes != true) return;

    try {
      await Supabase.instance.client.functions.invoke('revoke-device', body: {'deviceId': device['id']});
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not revoke device.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceCards = _devices.map((device) {
      final isCurrent = device['id'] == _localDeviceId;
      final canConnect = !isCurrent && device['server_enabled'] == true && device['revoked_at'] == null;
      return _DeviceCard(
        device: device,
        isCurrent: isCurrent,
        onPair: canConnect ? () => _startPairing(device) : null,
        onConnect: canConnect
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RemoteFilesScreen(
                      localDeviceId: _localDeviceId ?? '',
                      serverDeviceId: device['id'].toString(),
                    ),
                  ),
                )
            : null,
        onRevoke: () => _confirmRevoke(device),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your devices'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ),
                  if (_pairCode != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: QrImageView(data: _pairCode!, version: QrVersions.auto, size: 120.0),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Pairing code', style: TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                SelectableText(_pairCode!, style: const TextStyle(fontSize: 24, letterSpacing: 2)),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () async {
                                    final code = _pairCode;
                                    if (code == null || code.isEmpty) return;
                                    await Clipboard.setData(ClipboardData(text: code));
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Pairing code copied to clipboard.')),
                                    );
                                  },
                                  icon: const Icon(Icons.copy_rounded),
                                  label: const Text('Copy code'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_devices.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Center(child: Text('No devices are paired yet.')),
                    )
                  else
                    ...deviceCards,
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async => _redeemCode(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isCurrent,
    required this.onPair,
    required this.onConnect,
    required this.onRevoke,
  });

  final Map<String, dynamic> device;
  final bool isCurrent;
  final VoidCallback? onPair;
  final VoidCallback? onConnect;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final lastSeen = DateTime.tryParse(device['last_seen_at']?.toString() ?? '');
    final fresh = lastSeen != null && DateTime.now().toUtc().difference(lastSeen.toUtc()) < const Duration(seconds: 90);
    final active = device['revoked_at'] == null && fresh;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  device['name']?.toString() ?? 'Unnamed device',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('This device', style: TextStyle(fontSize: 12)),
                )
              else if (device['server_enabled'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: active ? AppColors.accent.withValues(alpha: 0.12) : AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(active ? 'Online' : 'Offline', style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(device['model']?.toString() ?? 'PocketCloud device'),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: active ? AppColors.accent : AppColors.warning),
              const SizedBox(width: 6),
              Text(active ? 'Active recently' : 'Needs a fresh sync'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onPair != null)
                TextButton.icon(
                  onPressed: onPair,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Pair'),
                ),
              if (onConnect != null)
                FilledButton.icon(
                  onPressed: onConnect,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('Open'),
                ),
              TextButton.icon(
                onPressed: onRevoke,
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('Revoke'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
