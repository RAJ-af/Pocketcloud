import 'dart:math';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
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
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try { final current = await _repo.ensureThisDevice(); final data = await _repo.listDevices(); final pairs = await _repo.listPairs(); if (mounted) setState(() { _localDeviceId = current['id'] as String; _devices = data; _pairs = pairs; }); }
    catch (_) { if (mounted) setState(() => _error = 'Could not load devices. Apply the Supabase migration and check RLS.'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  String _makeCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }
  Future<void> _createPairCode(Map<String, dynamic> device, {required bool allowUpload}) async {
    final code = _makeCode();
    final hash = sha256.convert(utf8.encode(code)).toString();
    try {
      await Supabase.instance.client.from('pairing_codes').insert({'owner_id': Supabase.instance.client.auth.currentUser!.id, 'server_device_id': device['id'], 'code_hash': hash, 'can_upload': allowUpload, 'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String()});
      if (mounted) setState(() { _pairCode = code; });
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create pairing code. Ensure this device is marked as a server.'))); }
  }

  Future<void> _startPairing(Map<String, dynamic> device) async {
    var allowUpload = false;
    final confirmed = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, setDialogState) => AlertDialog(title: const Text('Create pairing code'), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('This code lets another device pair with this server.'), CheckboxListTile(value: allowUpload, onChanged: (value) => setDialogState(() => allowUpload = value ?? false), title: const Text('Allow upload access'))]), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Create code'))])));
    if (confirmed == true) await _createPairCode(device, allowUpload: allowUpload);
  }

  Future<void> _redeemCode({String? suppliedCode}) async {
    String? code = suppliedCode;
    if (code == null) {
      final controller = TextEditingController();
      code = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('Pair with a server'), content: TextField(controller: controller, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(hintText: 'Enter 12-character code')), actions: [TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Pair'))]));
      controller.dispose();
    }
    if (code == null || code.length != 12) return;
    try {
      final localId = _localDeviceId;
      if (localId == null) throw StateError('This device has not finished registering.');
      final result = await Supabase.instance.client.functions.invoke('redeem-pairing', body: {'code': code, 'clientDeviceId': localId});
      if (result.status < 200 || result.status >= 300) throw StateError('Pairing was rejected.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Devices paired. Upload access follows the server owner’s choice.')));
        await _load();
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pairing failed: ${e is StateError ? e.message : 'Check code and connection.'}'))); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Your devices'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]), body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 28), children: [Text('Connected by trust,\nnot by guesswork.', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 9), Text('Pair only devices signed in to your PocketCloud account. Codes expire after five minutes.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)), const SizedBox(height: 18), Row(children: [Expanded(child: FilledButton.icon(onPressed: _redeemCode, icon: const Icon(Icons.link_rounded), label: const Text('Enter code'))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PairingScannerScreen())), icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('Scan QR')))]), if (_pairCode != null) Container(margin: const EdgeInsets.only(top: 18), padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Pairing code', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.muted)), const SizedBox(height: 4), SelectableText(_pairCode!, style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700))])), IconButton(onPressed: () { Clipboard.setData(ClipboardData(text: _pairCode!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pairing code copied.'))); }, icon: const Icon(Icons.copy_rounded))])), const SizedBox(height: 22), if (_loading) const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator())), if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)), if (!_loading && _devices.isEmpty) const Text('No devices registered yet.'), ..._devices.map((d) { final id = d['id'] as String; final pairedServer = _pairs.any((p) => p['server_device_id'] == id && p['client_device_id'] == _localDeviceId && p['revoked_at'] == null); final connected = d['server_enabled'] == true && d['is_online'] == true; return _DeviceCard(device: d, isCurrent: id == _localDeviceId, onPair: () => _startPairing(d), onConnect: pairedServer ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RemoteFilesScreen(localDeviceId: _localDeviceId ?? '', serverDeviceId: id))) : null, onRevoke: () => _confirmRevoke(d)); }).toList(), const SizedBox(height: 10), Text('Pairing codes authorize setup only. Every connection must also be authenticated, and access can be revoked from this screen.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)), ])));

  Future<void> _confirmRevoke(Map<String, dynamic> d) async {
    if (d['id'] == _localDeviceId) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You cannot revoke the device you are using. Sign out and revoke it from another device.'))); return; }
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Revoke device?'), content: Text('Revoke access for ${d['name'] ?? 'this device'}? Existing server settings remain in place until you remove them separately.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Revoke'))]));
    if (yes != true) return;
    try { await Supabase.instance.client.functions.invoke('revoke-device', body: {'deviceId': d['id']}); await _load(); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not revoke device.'))); }
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.isCurrent, required this.onPair, required this.onConnect, required this.onRevoke});
  final Map<String, dynamic> device; final bool isCurrent; final VoidCallback? onPair; final VoidCallback? onConnect; final VoidCallback onRevoke;
  @override
  Widget build(BuildContext context) {
    final lastSeen = DateTime.tryParse(device['last_seen_at']?.toString() ?? '');
    final fresh = lastSeen != null && DateTime.now().toUtc().difference(lastSeen.toUtc()) < const Duration(seconds: 90);
    final active = device['revoked_at'] == null && fresh;
    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(device['name']?.toString() ?? 'Device', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 4), Text(device['server_enabled'] == true ? (active ? 'Online and ready to host' : 'Server registered') : 'Client only', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)), const SizedBox(height: 8), Row(children: [Icon(Icons.circle, color: active ? Colors.green : AppColors.warning, size: 10), const SizedBox(width: 6), Text(active ? 'Active' : 'Idle', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: active ? Colors.green : AppColors.warning))])])), Column(children: [if (!isCurrent) ...[ElevatedButton(onPressed: onPair, child: const Text('Pair')), const SizedBox(height: 8), if (onConnect != null) ElevatedButton(onPressed: onConnect, child: const Text('Open'))], if (!isCurrent) TextButton(onPressed: onRevoke, child: const Text('Revoke'))]))]);
  }
}

