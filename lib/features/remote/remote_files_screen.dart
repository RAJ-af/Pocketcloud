import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/app_theme.dart';
import '../../services/webrtc_transfer_service.dart';
import '../../services/vault_store.dart';

class RemoteFilesScreen extends StatefulWidget {
  const RemoteFilesScreen({super.key, required this.localDeviceId, required this.serverDeviceId});
  final String localDeviceId;
  final String serverDeviceId;
  @override
  State<RemoteFilesScreen> createState() => _RemoteFilesScreenState();
}

class _RemoteFilesScreenState extends State<RemoteFilesScreen> {
  late final WebRtcTransferService _transfer;
  PeerStatus _status = PeerStatus.waiting;
  String _statusMessage = 'Preparing secure connection…';
  List<RemoteFile> _files = [];
  bool _loadingFiles = false;
  bool _starting = true;
  bool _canUpload = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _transfer = WebRtcTransferService(localDeviceId: widget.localDeviceId, onStatus: (status, message) {
      if (!mounted) return;
      setState(() { _status = status; _statusMessage = message; _starting = status == PeerStatus.connecting || status == PeerStatus.waiting; if (status == PeerStatus.connected) _error = null; });
      if (status == PeerStatus.connected) unawaited(_loadFiles());
    });
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (mounted) setState(() { _starting = true; _error = null; _status = PeerStatus.connecting; _statusMessage = 'Connecting to your server…'; });
    try {
      await _transfer.startListening();
      await _transfer.connectToServer(widget.serverDeviceId);
      if (mounted) setState(() { _starting = false; _canUpload = _transfer.canUpload; });
    } catch (e) {
      if (mounted) setState(() { _starting = false; _status = PeerStatus.failed; _statusMessage = 'Could not connect'; _error = e is StateError ? e.message.toString() : 'Check that the server is online and the pairing is still active.'; });
    }
  }

  Future<void> _loadFiles() async {
    if (_loadingFiles || !_transfer.connected) return;
    setState(() { _loadingFiles = true; _error = null; });
    try {
      final files = await _transfer.listRemoteFiles();
      if (mounted) setState(() => _files = files);
    } catch (e) {
      if (mounted) setState(() => _error = e is StateError ? e.message.toString() : 'Could not read the server library.');
    } finally { if (mounted) setState(() => _loadingFiles = false); }
  }

  Future<void> _download(RemoteFile remote) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading ${remote.name}…')));
      final file = await _transfer.downloadRemoteFile(remote.name);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Downloaded from PocketCloud'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: ${e is StateError ? e.message : 'connection timed out'}')));
    }
  }

  Future<void> _upload() async {
    if (!_canUpload) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload is disabled by the server owner.'))); return; }
    try {
      // file_picker v12+ returns PlatformFile directly; pickFile is the
      // single-selection API and readAsBytes works with Android SAF URIs too.
      final item = await FilePicker.pickFile();
      if (item == null) return;

      final selectedLength = item.lengthSync() ?? await item.length();
      if (selectedLength == null) {
        throw StateError('Could not determine the selected file size.');
      }
      if (selectedLength > VaultStore.maxFileBytes) {
        throw StateError('Files larger than 25 MB are blocked in this MVP.');
      }

      final bytes = await item.readAsBytes();
      // Recheck actual bytes, rather than trusting metadata from the picker.
      if (bytes.length > VaultStore.maxFileBytes) {
        throw StateError('Files larger than 25 MB are blocked in this MVP.');
      }
      await _transfer.uploadFile(VaultStore().safeName(item.name), bytes);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload received and integrity-checked by the server.'))); await _loadFiles(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: ${e is StateError ? e.message : 'check connection and storage'}')));
    }
  }

  String _formatSize(int bytes) { if (bytes < 1024) return '$bytes B'; if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB'; return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'; }
  Color get _statusColor => _status == PeerStatus.connected ? AppColors.accent : (_status == PeerStatus.failed ? AppColors.danger : AppColors.warning);

  @override
  void dispose() { unawaited(_transfer.dispose()); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Remote library'), actions: [IconButton(onPressed: _status == PeerStatus.connected ? _loadFiles : null, icon: const Icon(Icons.refresh_rounded)), IconButton(onPressed: () async { await _transfer.hangUp(); if (mounted) Navigator.of(context).pop(); }, icon: const Icon(Icons.link_off_rounded))]), body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
    Text('Your files,\nnot a cloud copy.', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 10), Text('Connect to the paired server and transfer selected files directly over an encrypted WebRTC data channel.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
    const SizedBox(height: 18),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)), child: Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: _statusColor.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)), child: Icon(_status == PeerStatus.connected ? Icons.lock_rounded : Icons.sync_rounded, color: _statusColor)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_status.name.toUpperCase(), style: TextStyle(letterSpacing: 1.1, fontSize: 11, fontWeight: FontWeight.w900, color: _statusColor)), const SizedBox(height: 4), Text(_statusMessage, style: const TextStyle(color: AppColors.muted, height: 1.4))])), if (_starting) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))])),
    const SizedBox(height: 18),
    if (_status == PeerStatus.failed || _status == PeerStatus.closed) Padding(padding: const EdgeInsets.only(bottom: 12), child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _starting ? null : _connect, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry connection')))),
    Row(children: [Expanded(child: FilledButton.icon(onPressed: _status == PeerStatus.connected ? _loadFiles : null, icon: const Icon(Icons.folder_open_rounded), label: const Text('Load files'))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: _status == PeerStatus.connected ? _upload : null, icon: const Icon(Icons.upload_rounded), label: Text(_canUpload ? 'Upload file' : 'Upload off')))]),
    if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)), child: Text(_error!, style: const TextStyle(color: AppColors.danger)))),
    const SizedBox(height: 24), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Server files', style: Theme.of(context).textTheme.titleLarge), Text('${_files.length} items', style: const TextStyle(color: AppColors.muted, fontSize: 12))]),
    const SizedBox(height: 12),
    if (_loadingFiles) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
    if (!_loadingFiles && _status == PeerStatus.connected && _files.isEmpty) Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)), child: const Column(children: [Icon(Icons.folder_off_outlined, size: 36, color: AppColors.muted), SizedBox(height: 9), Text('No files found'), SizedBox(height: 4), Text('Import files on the server phone first.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))])),
    ..._files.map((file) => Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(16)), child: Row(children: [const Icon(Icons.insert_drive_file_outlined, color: AppColors.aqua), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(_formatSize(file.size), style: const TextStyle(color: AppColors.muted, fontSize: 12))])), IconButton(tooltip: 'Download', onPressed: _status == PeerStatus.connected && file.size <= 25 * 1024 * 1024 ? () => _download(file) : null, icon: const Icon(Icons.download_rounded, color: AppColors.accent))]))),
    const SizedBox(height: 22), Text('Transfers are limited to 25 MB per file in this MVP. If direct peer connectivity fails, configure a TURN relay. Keep the server app open for now; reliable background hosting is not yet implemented.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted, height: 1.5)),
  ])));
}
