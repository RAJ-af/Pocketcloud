import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import 'vault_store.dart';

enum PeerStatus { idle, waiting, connecting, connected, reconnecting, failed, closed }

class RemoteFile {
  const RemoteFile({required this.name, required this.size});
  final String name;
  final int size;
}

class WebRtcTransferService {
  WebRtcTransferService({required this.localDeviceId, this.onStatus});
  final String localDeviceId;
  final void Function(PeerStatus status, String message)? onStatus;
  final SupabaseClient _db = Supabase.instance.client;
  final VaultStore _vault = VaultStore();
  final Uuid _uuid = const Uuid();
  RealtimeChannel? _signalChannel;
  RTCPeerConnection? _peer;
  RTCDataChannel? _data;
  String? _remoteDeviceId;
  Map<String, dynamic>? _pair;
  bool _disposed = false;
  Future<void> _signalQueue = Future<void>.value();
  bool _remoteDescriptionReady = false;
  Timer? _reconnectTimer;
  Timer? _leaseTimer;
  int _reconnectAttempts = 0;
  bool _explicitlyClosed = false;
  bool _connectInFlight = false;
  String? _targetServerId;
  DateTime _lastLeaseSuccess = DateTime.now().toUtc();
  final List<RTCIceCandidate> _pendingCandidates = [];
  final Map<String, Completer<List<RemoteFile>>> _listWaiters = {};
  final Map<String, List<RemoteFile>> _pendingFileLists = {};
  final Map<String, Completer<File>> _downloadWaiters = {};
  final Map<String, Completer<void>> _uploadWaiters = {};
  final Map<String, _IncomingFile> _incoming = {};

  bool get connected => _data?.state == RTCDataChannelState.RTCDataChannelOpen;
  bool get canList => _pair?['can_list'] == true;
  bool get canDownload => _pair?['can_download'] == true;
  bool get canUpload => _pair?['can_upload'] == true;

  void _status(PeerStatus status, String message) {
    if (!_disposed) onStatus?.call(status, message);
  }

  Future<void> startListening() async {
    if (_disposed || _signalChannel != null) return;
    final ready = Completer<void>();
    final channel = _db.channel('pocketcloud-signals-$localDeviceId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'signaling_messages',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'to_device_id', value: localDeviceId),
        callback: (payload) {
          final row = Map<String, dynamic>.from(payload.newRecord);
          _signalQueue = _signalQueue.then((_) => _handleSignal(row)).catchError((Object _) {});
        },
      );
    _signalChannel = channel;
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (!ready.isCompleted) ready.complete();
      } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
        if (!ready.isCompleted) {
          ready.completeError(error ?? StateError('Realtime subscription failed: $status'));
        } else {
          _status(PeerStatus.failed, 'Realtime signalling was interrupted. Check network and Supabase publication settings.');
        }
      }
    });
    try {
      await ready.future.timeout(const Duration(seconds: 12));
    } catch (_) {
      if (identical(_signalChannel, channel)) _signalChannel = null;
      try { await _db.removeChannel(channel); } catch (_) {}
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _loadActivePair(String remoteId) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw StateError('Sign in before connecting.');
    final pairs = await _db.from('device_pairs').select()
      .eq('owner_id', uid).isFilter('revoked_at', null);
    for (final raw in pairs) {
      final row = Map<String, dynamic>.from(raw);
      final idsMatch = (row['server_device_id'] == localDeviceId && row['client_device_id'] == remoteId) ||
          (row['server_device_id'] == remoteId && row['client_device_id'] == localDeviceId);
      if (idsMatch) return row;
    }
    throw StateError('These devices are not paired, or access has been revoked.');
  }

  Future<void> connectToServer(String serverDeviceId) async {
    if (_disposed) throw StateError('Connection manager has been disposed.');
    if (localDeviceId == serverDeviceId) throw StateError('A device cannot connect to itself.');
    _cancelReconnect();
    _targetServerId = serverDeviceId;
    _explicitlyClosed = false;
    _reconnectAttempts = 0;
    try {
      await _connectOnce();
    } catch (error) {
      _status(PeerStatus.failed, 'Initial connection failed. PocketCloud will retry if pairing is still valid.');
      _scheduleReconnect(error);
      rethrow;
    }
  }

  Future<void> _connectOnce() async {
    final serverDeviceId = _targetServerId;
    if (_disposed || _explicitlyClosed || serverDeviceId == null) return;
    if (_connectInFlight) return;
    _connectInFlight = true;
    try {
      _pair = await _loadActivePair(serverDeviceId);
      if (_pair!['server_device_id'] != serverDeviceId || _pair!['client_device_id'] != localDeviceId) {
        throw StateError('Open the server from the client device that was paired to it.');
      }
      if (!canList) throw StateError('This pairing does not allow listing files.');
      _remoteDeviceId = serverDeviceId;
      await startListening();
      await _createPeer(initiator: true);
      final pc = _peer!;
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      final local = await pc.getLocalDescription();
      if (local?.sdp == null) throw StateError('Could not create connection offer.');
      await _sendSignal('offer', {'sdp': local!.sdp, 'type': 'offer'});
      _startLeaseChecks();
      _status(PeerStatus.connecting, 'Negotiating secure peer connection…');
    } finally {
      _connectInFlight = false;
    }
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _scheduleReconnect([Object? reason]) {
    if (_disposed || _explicitlyClosed || _targetServerId == null || _reconnectTimer != null || _connectInFlight) return;
    final detail = reason?.toString().toLowerCase() ?? '';
    if (detail.contains('revoked') || detail.contains('not paired') || detail.contains('not allow listing') || detail.contains('not from the client') || detail.contains('open the server')) {
      _cancelReconnect();
      return;
    }
    const delays = [2, 4, 8, 16, 30, 30, 60, 60];
    if (_reconnectAttempts >= delays.length) {
      _status(PeerStatus.failed, 'Automatic reconnect paused after 8 attempts. Tap Retry to start again.');
      return;
    }
    final wait = Duration(seconds: delays[_reconnectAttempts++]);
    _status(PeerStatus.reconnecting, 'Connection lost. Retrying in ${wait.inSeconds}s (attempt $_reconnectAttempts/8)…');
    _reconnectTimer = Timer(wait, () async {
      _reconnectTimer = null;
      try {
        await _connectOnce();
      } catch (error) {
        _scheduleReconnect(error);
      }
    });
  }

  void _startLeaseChecks() {
    _leaseTimer?.cancel();
    _lastLeaseSuccess = DateTime.now().toUtc();
    _leaseTimer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_verifyAccessLease()));
  }

  Future<void> _verifyAccessLease() async {
    if (_disposed || _pair == null) return;
    try {
      final pairId = _pair!['id']?.toString();
      if (pairId == null) throw StateError('Missing pairing ID.');
      final row = await _db.from('device_pairs').select('id,server_device_id,client_device_id,can_list,can_download,can_upload,revoked_at')
          .eq('id', pairId).maybeSingle();
      Map<String, dynamic>? server;
      if (row != null) {
        final rawServer = await _db.from('devices').select('id,server_enabled,is_online,revoked_at,last_seen_at')
            .eq('id', row['server_device_id']).maybeSingle();
        if (rawServer != null) server = Map<String, dynamic>.from(rawServer);
      }
      final lastSeen = DateTime.tryParse(server?['last_seen_at']?.toString() ?? '');
      final serverFresh = lastSeen != null && DateTime.now().toUtc().difference(lastSeen.toUtc()) < const Duration(seconds: 90);
      final serverUsable = server?['server_enabled'] == true && server?['is_online'] == true && server?['revoked_at'] == null && serverFresh;
      if (row == null || row['revoked_at'] != null || !serverUsable) {
        final isHost = _pair?['server_device_id'] == localDeviceId;
        _explicitlyClosed = !isHost;
        _cancelReconnect();
        _leaseTimer?.cancel();
        await _disposePeer();
        if (isHost) { _pair = null; _remoteDeviceId = null; }
        _status(PeerStatus.closed, 'This pairing is no longer authorised. Re-pair the devices to continue.');
        return;
      }
      _lastLeaseSuccess = DateTime.now().toUtc();
      _pair = Map<String, dynamic>.from(row);
    } catch (_) {
      if (DateTime.now().toUtc().difference(_lastLeaseSuccess) >= const Duration(seconds: 30)) {
        final isHost = _pair?['server_device_id'] == localDeviceId;
        _explicitlyClosed = !isHost;
        _cancelReconnect();
        _leaseTimer?.cancel();
        await _disposePeer();
        if (isHost) { _pair = null; _remoteDeviceId = null; }
        _status(PeerStatus.failed, 'Access could not be verified for 30 seconds, so PocketCloud disconnected for safety. Reconnect when online.');
      }
    }
  }

  Future<void> _createPeer({required bool initiator}) async {
    await _disposePeer();
    _remoteDescriptionReady = false;
    _pendingCandidates.clear();
    final iceServers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      if (AppConfig.turnUrl.isNotEmpty && AppConfig.turnUsername.isNotEmpty && AppConfig.turnCredential.isNotEmpty)
        {'urls': AppConfig.turnUrl, 'username': AppConfig.turnUsername, 'credential': AppConfig.turnCredential},
    ];
    final peer = await createPeerConnection({'iceServers': iceServers, 'sdpSemantics': 'unified-plan'});
    _peer = peer;
    peer.onIceCandidate = (candidate) {
      if (!identical(_peer, peer) || candidate.candidate == null || _remoteDeviceId == null) return;
      unawaited(_sendSignal('candidate', {'candidate': candidate.candidate, 'sdpMid': candidate.sdpMid, 'sdpMLineIndex': candidate.sdpMLineIndex}));
    };
    peer.onConnectionState = (state) {
      if (!identical(_peer, peer)) return;
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _reconnectAttempts = 0;
          _cancelReconnect();
          _status(PeerStatus.connected, 'Secure peer connection established.');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _status(PeerStatus.connecting, 'Connecting devices…');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          if (_pair?['server_device_id'] == localDeviceId) {
            _handlePeerFailure('Peer disconnected. Waiting for a fresh connection attempt.');
          } else {
            _status(PeerStatus.reconnecting, 'Peer connection dropped. Checking the connection…');
            _scheduleReconnect();
          }
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _handlePeerFailure('Connection failed. A TURN relay may be required on this network.');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _handlePeerFailure('Connection closed.');
          break;
        default:
          break;
      }
    };
    peer.onDataChannel = (channel) { if (identical(_peer, peer)) _bindDataChannel(channel); };
    if (initiator) {
      final channel = await peer.createDataChannel('pocketcloud-files', RTCDataChannelInit()..ordered = true);
      _bindDataChannel(channel);
    }
  }

  void _handlePeerFailure(String message) {
    final isHost = _pair?['server_device_id'] == localDeviceId;
    _status(PeerStatus.failed, message);
    if (isHost) {
      // This server supports one live peer at a time. Clear a failed peer so a
      // fresh offer from any other currently paired device can be evaluated.
      _leaseTimer?.cancel();
      _pair = null;
      _remoteDeviceId = null;
      _pendingCandidates.clear();
      _remoteDescriptionReady = false;
      unawaited(_disposePeer());
    } else {
      _scheduleReconnect();
    }
  }

  void _bindDataChannel(RTCDataChannel channel) {
    _data = channel;
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _reconnectAttempts = 0;
        _cancelReconnect();
        _status(PeerStatus.connected, 'Connected. Your files remain on the peer device until transferred.');
      }
      if (state == RTCDataChannelState.RTCDataChannelClosed) _status(PeerStatus.closed, 'Data channel closed.');
    };
    channel.onMessage = (message) {
      if (!message.isBinary) unawaited(_handleDataMessage(message.text));
    };
  }

  Future<void> _handleSignal(Map<String, dynamic> row) async {
    if (_disposed) return;
    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    if (createdAt != null && DateTime.now().toUtc().difference(createdAt.toUtc()) > const Duration(minutes: 10)) {
      unawaited(_deleteSignal(row['id']?.toString()));
      return;
    }
    final fromId = row['from_device_id']?.toString();
    if (fromId == null || fromId == localDeviceId) return;
    try {
      _pair ??= await _loadActivePair(fromId);
      final isPair = (_pair!['server_device_id'] == localDeviceId && _pair!['client_device_id'] == fromId) ||
          (_pair!['server_device_id'] == fromId && _pair!['client_device_id'] == localDeviceId);
      if (!isPair || _pair!['revoked_at'] != null) return;
      _remoteDeviceId = fromId;
      final payload = Map<String, dynamic>.from(row['payload'] as Map);
      switch (row['message_type']) {
        case 'offer':
          if (_pair!['server_device_id'] != localDeviceId) return;
          _startLeaseChecks();
          await _createPeer(initiator: false);
          await _peer!.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String, 'offer'));
          _remoteDescriptionReady = true;
          await _flushCandidates();
          final answer = await _peer!.createAnswer();
          await _peer!.setLocalDescription(answer);
          final local = await _peer!.getLocalDescription();
          await _sendSignal('answer', {'sdp': local!.sdp, 'type': 'answer'});
          _status(PeerStatus.connecting, 'Answer sent; waiting for secure channel…');
          break;
        case 'answer':
          if (_peer == null) return;
          await _peer!.setRemoteDescription(RTCSessionDescription(payload['sdp'] as String, 'answer'));
          _remoteDescriptionReady = true;
          await _flushCandidates();
          break;
        case 'candidate':
          final c = RTCIceCandidate(payload['candidate'] as String?, payload['sdpMid'] as String?, payload['sdpMLineIndex'] as int?);
          if (_remoteDescriptionReady && _peer != null) {
            await _peer!.addCandidate(c);
          } else {
            if (_pendingCandidates.length >= 256) throw StateError('Too many pending ICE candidates.');
            _pendingCandidates.add(c);
          }
          break;
        case 'hangup':
          final isHost = _pair?['server_device_id'] == localDeviceId;
          _explicitlyClosed = !isHost;
          if (!isHost) _targetServerId = null;
          _cancelReconnect();
          _leaseTimer?.cancel();
          await _disposePeer();
          if (isHost) { _pair = null; _remoteDeviceId = null; }
          _status(PeerStatus.closed, 'The other device ended the connection.');
          break;
        default:
          break;
      }
    } catch (e) {
      _status(PeerStatus.failed, 'Could not process peer signalling. Check pairing and network.');
    } finally {
      unawaited(_deleteSignal(row['id']?.toString()));
    }
  }

  Future<void> _flushCandidates() async {
    if (_peer == null) return;
    for (final candidate in _pendingCandidates) {
      await _peer!.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  Future<void> _sendSignal(String kind, Map<String, dynamic> payload) async {
    final to = _remoteDeviceId;
    final uid = _db.auth.currentUser?.id;
    if (to == null || uid == null) throw StateError('No paired device selected.');
    await _db.from('signaling_messages').insert({'owner_id': uid, 'from_device_id': localDeviceId, 'to_device_id': to, 'message_type': kind, 'payload': payload});
  }

  Future<void> _deleteSignal(String? id) async {
    if (id == null) return;
    try { await _db.from('signaling_messages').delete().eq('id', id); } catch (_) { /* Stale signals are non-fatal. */ }
  }

  Future<void> _sendControl(Map<String, dynamic> body) async {
    if (!connected || _data == null) throw StateError('Peer data channel is not open.');
    _data!.send(RTCDataChannelMessage(jsonEncode(body)));
  }

  Future<List<RemoteFile>> listRemoteFiles() async {
    if (!canList) throw StateError('Listing is not permitted for this pairing.');
    final requestId = _uuid.v4();
    final completer = Completer<List<RemoteFile>>();
    _listWaiters[requestId] = completer;
    try {
      await _sendControl({'type': 'list_request', 'requestId': requestId});
    } catch (_) {
      _listWaiters.remove(requestId);
      _pendingFileLists.remove(requestId);
      rethrow;
    }
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () {
      _listWaiters.remove(requestId);
      _pendingFileLists.remove(requestId);
      throw TimeoutException('The server did not return its file list.');
    });
  }

  Future<File> downloadRemoteFile(String name) async {
    if (!canDownload) throw StateError('Downloads are disabled for this pairing.');
    final requestId = _uuid.v4();
    final completer = Completer<File>();
    _downloadWaiters[requestId] = completer;
    try {
      await _sendControl({'type': 'download_request', 'requestId': requestId, 'name': name});
    } catch (_) {
      _downloadWaiters.remove(requestId);
      rethrow;
    }
    return completer.future.timeout(const Duration(minutes: 3), onTimeout: () {
      _downloadWaiters.remove(requestId);
      throw TimeoutException('Download timed out. Retry when both devices are stable.');
    });
  }

  Future<void> uploadFile(String name, List<int> bytes) async {
    if (!canUpload) throw StateError('Uploads are disabled on this pairing. The server owner must enable upload permission.');
    if (bytes.length > VaultStore.maxFileBytes) throw StateError('File is larger than the 25 MB MVP limit.');
    if (!connected) throw StateError('Connect to the server before uploading.');
    final transferId = _uuid.v4();
    final digest = sha256.convert(bytes).toString();
    final acknowledgement = Completer<void>();
    _uploadWaiters[transferId] = acknowledgement;
    try {
      await _sendControl({'type': 'upload_start', 'transferId': transferId, 'name': name, 'size': bytes.length, 'sha256': digest});
      for (var offset = 0, index = 0; offset < bytes.length; offset += 8000, index++) {
        final end = (offset + 8000 < bytes.length) ? offset + 8000 : bytes.length;
        await _sendControl({'type': 'file_chunk', 'transferId': transferId, 'index': index, 'data': base64Encode(bytes.sublist(offset, end))});
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await _sendControl({'type': 'file_end', 'transferId': transferId});
      await acknowledgement.future.timeout(const Duration(minutes: 2), onTimeout: () {
        _uploadWaiters.remove(transferId);
        throw TimeoutException('The server did not confirm the upload.');
      });
    } catch (_) {
      _uploadWaiters.remove(transferId);
      rethrow;
    }
  }

  Future<void> _handleDataMessage(String text) async {
    if (_disposed) return;
    String? activeTransferId;
    String? activeRequestId;
    try {
      if (text.length > 16000) throw StateError('Transfer message exceeds the MVP message limit.');
      final message = jsonDecode(text) as Map<String, dynamic>;
      final type = message['type'] as String?;
      switch (type) {
        case 'list_request':
          if (_pair?['server_device_id'] != localDeviceId ||
              _pair?['client_device_id'] != _remoteDeviceId ||
              _pair?['can_list'] != true) return;
          final files = await _vault.list();
          const pageSize = 8;
          if (files.isEmpty) {
            await _sendControl({'type': 'list_response', 'requestId': message['requestId'], 'files': <Object>[], 'done': true});
          } else {
            for (var offset = 0; offset < files.length; offset += pageSize) {
              final end = (offset + pageSize < files.length) ? offset + pageSize : files.length;
              await _sendControl({'type': 'list_response', 'requestId': message['requestId'], 'files': files.sublist(offset, end).map((f) => f.toJson()).toList(), 'done': end == files.length});
            }
          }
          break;
        case 'list_response':
          final id = message['requestId']?.toString();
          if (id == null || !_listWaiters.containsKey(id)) break;
          final raw = (message['files'] as List? ?? []).whereType<Map>();
          final page = <RemoteFile>[];
          for (final item in raw) {
            final name = item['name'];
            final size = item['size'];
            if (name is! String || name.isEmpty || name.length > 180 || name.contains('/') || name.contains('\\') || size is! int || size < 0) {
              throw StateError('Invalid file-list entry received from peer.');
            }
            page.add(RemoteFile(name: name, size: size));
          }
          final accumulated = _pendingFileLists.putIfAbsent(id, () => <RemoteFile>[]);
          if (accumulated.length + page.length > 2000) throw StateError('The server returned too many file-list entries.');
          accumulated.addAll(page);
          if (message['done'] == true) {
            final result = _pendingFileLists.remove(id) ?? <RemoteFile>[];
            final completer = _listWaiters.remove(id);
            if (completer != null && !completer.isCompleted) completer.complete(result);
          }
          break;
        case 'download_request':
          if (_pair?['server_device_id'] != localDeviceId ||
              _pair?['client_device_id'] != _remoteDeviceId ||
              _pair?['can_download'] != true) return;
          final requestId = message['requestId']?.toString() ?? _uuid.v4();
          await _sendVaultFile(message['name']?.toString() ?? '', requestId);
          break;
        case 'upload_start':
          final transferId = message['transferId']?.toString() ?? '';
          activeTransferId = transferId;
          final size = (message['size'] as num?)?.toInt() ?? -1;
          final digest = message['sha256']?.toString() ?? '';
          if (_pair?['server_device_id'] != localDeviceId || _pair?['client_device_id'] != _remoteDeviceId || _pair?['can_upload'] != true) {
            await _sendControl({'type': 'transfer_error', 'transferId': transferId, 'message': 'Upload permission denied.'});
            return;
          }
          if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false).hasMatch(transferId) || digest.length != 64 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) || size < 0 || size > VaultStore.maxFileBytes || _incoming.isNotEmpty) {
            await _sendControl({'type': 'transfer_error', 'transferId': transferId, 'message': 'Upload is invalid, too large, or another transfer is active.'});
            return;
          }
          _incoming[transferId] = _IncomingFile(name: _vault.safeName(message['name']?.toString() ?? ''), expectedSize: size, expectedHash: digest, isUpload: true);
          break;
        case 'file_start':
          activeRequestId = message['requestId']?.toString();
          final transferId = message['transferId']?.toString() ?? '';
          activeTransferId = transferId;
          final size = (message['size'] as num?)?.toInt() ?? -1;
          final digest = message['sha256']?.toString() ?? '';
          final requestId = message['requestId']?.toString();
          final permittedDownload = _pair?['server_device_id'] == _remoteDeviceId &&
              _pair?['client_device_id'] == localDeviceId && _pair?['can_download'] == true &&
              message['direction'] == 'download' && requestId != null && _downloadWaiters.containsKey(requestId);
          if (!permittedDownload) throw StateError('Download was not requested or permission is disabled.');
          if (!RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false).hasMatch(transferId) || digest.length != 64 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) || size < 0 || size > VaultStore.maxFileBytes || _incoming.isNotEmpty) throw StateError('Incoming file is invalid, too large, or another transfer is active.');
          _incoming[transferId] = _IncomingFile(name: _vault.safeName(message['name']?.toString() ?? ''), expectedSize: size, expectedHash: digest, requestId: requestId, isUpload: false);
          break;
        case 'file_chunk':
          activeTransferId = message['transferId']?.toString();
          final transfer = _incoming[activeTransferId];
          if (transfer == null) return;
          if (transfer.ended) throw StateError('A completed transfer cannot accept more chunks.');
          final bool authorized;
          if (transfer.isUpload) {
            authorized = _pair?['server_device_id'] == localDeviceId &&
                _pair?['client_device_id'] == _remoteDeviceId &&
                _pair?['can_upload'] == true;
          } else {
            authorized = _pair?['client_device_id'] == localDeviceId &&
                _pair?['server_device_id'] == _remoteDeviceId &&
                _pair?['can_download'] == true;
          }
          if (!authorized) throw StateError('Transfer permission was revoked.');
          final index = (message['index'] as num?)?.toInt() ?? -1;
          if (index != transfer.nextChunk) throw StateError('Invalid or out-of-order chunk.');
          final bytes = base64Decode(message['data'].toString());
          if (transfer.receivedBytes + bytes.length > transfer.expectedSize || transfer.receivedBytes + bytes.length > VaultStore.maxFileBytes) throw StateError('Incoming file exceeded declared size.');
          transfer.nextChunk++;
          transfer.bytes.add(bytes);
          break;
        case 'file_end':
          final transferId = message['transferId']?.toString();
          activeTransferId = transferId;
          final transfer = transferId == null ? null : _incoming[transferId];
          if (transfer == null) return;
          if (transfer.isUpload &&
              !(_pair?['server_device_id'] == localDeviceId &&
                  _pair?['client_device_id'] == _remoteDeviceId &&
                  _pair?['can_upload'] == true)) {
            throw StateError('Upload permission was revoked.');
          }
          if (!transfer.isUpload && !(_pair?['client_device_id'] == localDeviceId && _pair?['server_device_id'] == _remoteDeviceId && _pair?['can_download'] == true)) throw StateError('Download permission was revoked.');
          transfer.ended = true;
          final bytes = transfer.bytes.takeBytes();
          if (bytes.length != transfer.expectedSize) throw StateError('File length mismatch.');
          if (transfer.expectedHash != null && sha256.convert(bytes).toString() != transfer.expectedHash) throw StateError('File integrity check failed.');
          final file = await _vault.saveReceived(transfer.name, bytes);
          _incoming.remove(transferId);
          if (transfer.requestId != null) {
            final completer = _downloadWaiters.remove(transfer.requestId);
            if (completer != null && !completer.isCompleted) completer.complete(file);
          }
          await _sendControl({'type': 'transfer_complete', 'transferId': transferId, 'name': file.uri.pathSegments.last, 'size': bytes.length});
          break;
        case 'transfer_error':
          final transferId = message['transferId']?.toString();
          final transfer = transferId == null ? null : _incoming.remove(transferId);
          final id = message['requestId']?.toString() ?? transfer?.requestId;
          final completer = id == null ? null : _downloadWaiters.remove(id);
          if (completer != null && !completer.isCompleted) completer.completeError(StateError(message['message']?.toString() ?? 'Transfer failed.'));
          final uploadId = transferId;
          final upload = uploadId == null ? null : _uploadWaiters.remove(uploadId);
          if (upload != null && !upload.isCompleted) upload.completeError(StateError(message['message']?.toString() ?? 'Transfer failed.'));
          break;
        case 'transfer_complete':
          final transferId = message['transferId']?.toString();
          final upload = transferId == null ? null : _uploadWaiters.remove(transferId);
          if (upload != null && !upload.isCompleted) upload.complete();
          break;
        default:
          break;
      }
    } catch (_) {
      final incoming = activeTransferId == null ? null : _incoming.remove(activeTransferId);
      final requestId = activeRequestId ?? incoming?.requestId;
      if (requestId != null) {
        final download = _downloadWaiters.remove(requestId);
        if (download != null && !download.isCompleted) download.completeError(StateError('Transfer validation or storage failed.'));
      }
      final upload = activeTransferId == null ? null : _uploadWaiters.remove(activeTransferId);
      if (upload != null && !upload.isCompleted) upload.completeError(StateError('Transfer validation or storage failed.'));
      if ((activeTransferId != null || requestId != null) && connected) {
        try { await _sendControl({'type': 'transfer_error', if (activeTransferId != null) 'transferId': activeTransferId, if (requestId != null) 'requestId': requestId, 'message': 'Transfer validation or storage failed.'}); } catch (_) {}
      }
      _status(PeerStatus.failed, 'A transfer message was invalid or failed validation.');
    }
  }

  Future<void> _sendVaultFile(String rawName, String requestId) async {
    final safeName = _vault.safeName(rawName);
    final file = await _vault.fileForName(safeName);
    if (!await file.exists()) {
      await _sendControl({'type': 'transfer_error', 'requestId': requestId, 'message': 'File not found.'});
      return;
    }
    final size = await file.length();
    if (size > VaultStore.maxFileBytes) {
      await _sendControl({'type': 'transfer_error', 'requestId': requestId, 'message': 'File is larger than the 25 MB MVP limit.'});
      return;
    }
    final bytes = await file.readAsBytes();
    final transferId = _uuid.v4();
    final digest = sha256.convert(bytes).toString();
    await _sendControl({'type': 'file_start', 'transferId': transferId, 'requestId': requestId, 'name': safeName, 'size': bytes.length, 'sha256': digest, 'direction': 'download'});
    for (var offset = 0, index = 0; offset < bytes.length; offset += 8000, index++) {
      final end = (offset + 8000 < bytes.length) ? offset + 8000 : bytes.length;
      await _sendControl({'type': 'file_chunk', 'transferId': transferId, 'index': index, 'data': base64Encode(bytes.sublist(offset, end))});
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await _sendControl({'type': 'file_end', 'transferId': transferId});
  }

  Future<void> hangUp() async {
    _explicitlyClosed = true;
    _targetServerId = null;
    _cancelReconnect();
    _leaseTimer?.cancel();
    if (_remoteDeviceId != null) {
      try { await _sendSignal('hangup', {'at': DateTime.now().toUtc().toIso8601String()}); } catch (_) { /* Best effort. */ }
    }
    await _disposePeer();
    _remoteDeviceId = null;
    _pair = null;
    _status(PeerStatus.closed, 'Disconnected.');
  }

  Future<void> _disposePeer() async {
    final channel = _data;
    final peer = _peer;
    _data = null;
    _peer = null;
    if (channel != null) { try { await channel.close(); } catch (_) {} }
    if (peer != null) { try { await peer.close(); } catch (_) {} try { await peer.dispose(); } catch (_) {} }
  }

  Future<void> dispose() async {
    _disposed = true;
    _explicitlyClosed = true;
    _cancelReconnect();
    _leaseTimer?.cancel();
    final channel = _signalChannel;
    _signalChannel = null;
    if (channel != null) { try { await _db.removeChannel(channel); } catch (_) {} }
    await _disposePeer();
    for (final completer in _listWaiters.values) { if (!completer.isCompleted) completer.completeError(StateError('Connection closed.')); }
    for (final completer in _downloadWaiters.values) { if (!completer.isCompleted) completer.completeError(StateError('Connection closed.')); }
    for (final completer in _uploadWaiters.values) { if (!completer.isCompleted) completer.completeError(StateError('Connection closed.')); }
    _listWaiters.clear(); _pendingFileLists.clear(); _downloadWaiters.clear(); _uploadWaiters.clear(); _incoming.clear();
  }
}

class _IncomingFile {
  _IncomingFile({required this.name, required this.expectedSize, required this.isUpload, this.expectedHash, this.requestId});
  final String name;
  final int expectedSize;
  final bool isUpload;
  bool ended = false;
  final String? expectedHash;
  final String? requestId;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int get receivedBytes => bytes.length;
  int nextChunk = 0;
}
