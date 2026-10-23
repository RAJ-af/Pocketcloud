import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class DeviceRepository {
  final SupabaseClient _db = Supabase.instance.client;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const _installKey = 'pocketcloud.install_id';

  Future<Map<String, dynamic>> ensureThisDevice() async {
    final user = _db.auth.currentUser;
    if (user == null) throw StateError('Sign-in required');
    var installId = await _secureStorage.read(key: _installKey);
    if (installId == null || installId.isEmpty) {
      installId = const Uuid().v4();
      await _secureStorage.write(key: _installKey, value: installId);
    }
    final existing = await _db.from('devices').select().eq('user_id', user.id).eq('install_id', installId).maybeSingle();
    if (existing != null) {
      if (existing['revoked_at'] != null) throw StateError('This installation has been revoked. Sign out and contact the account owner before using it again.');
      final updated = await _db.from('devices').update({'last_seen_at': DateTime.now().toUtc().toIso8601String(), 'is_online': true, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', existing['id']).eq('user_id', user.id).select().single();
      return Map<String, dynamic>.from(updated);
    }
    final platform = _safePlatform();
    final label = Platform.isAndroid ? 'Android phone' : '${platform[0].toUpperCase()}${platform.substring(1)} device';
    final row = await _db.from('devices').insert({'user_id': user.id, 'install_id': installId, 'name': label, 'platform': platform, 'role': 'client', 'is_online': true, 'last_seen_at': DateTime.now().toUtc().toIso8601String()}).select().single();
    return Map<String, dynamic>.from(row);
  }

  String _safePlatform() {
    final platform = Platform.operatingSystem;
    const allowed = {'android', 'ios', 'web', 'windows', 'macos', 'linux'};
    return allowed.contains(platform) ? platform : 'unknown';
  }

  Future<void> markOnline(String deviceId) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.from('devices').update({'is_online': true, 'last_seen_at': now, 'updated_at': now})
        .eq('id', deviceId).eq('user_id', user.id).isFilter('revoked_at', null);
  }

  Future<void> markOffline(String deviceId) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.from('devices').update({'is_online': false, 'last_seen_at': now, 'updated_at': now})
        .eq('id', deviceId).eq('user_id', user.id).isFilter('revoked_at', null);
  }

  Future<void> setServerEnabled(String deviceId, bool enabled) async {
    final userId = _db.auth.currentUser!.id;
    await _db.from('devices').update({'role': enabled ? 'server' : 'client', 'server_enabled': enabled, 'is_online': true, 'last_seen_at': DateTime.now().toUtc().toIso8601String(), 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', deviceId).eq('user_id', userId);
  }

  Future<List<Map<String, dynamic>>> listDevices() async {
    final rows = await _db.from('devices').select('id,name,platform,role,is_online,last_seen_at,server_enabled,revoked_at,created_at').order('created_at', ascending: false);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<Map<String, dynamic>>> listPairs() async {
    final rows = await _db.from('device_pairs').select().isFilter('revoked_at', null).order('created_at', ascending: false);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> revokeDevice(String id) async {
    await _db.functions.invoke('revoke-device', body: {'deviceId': id});
  }
}
