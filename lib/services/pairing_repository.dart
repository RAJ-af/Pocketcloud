import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PairingCodeInfo {
  const PairingCodeInfo({
    required this.plaintextCode,
    required this.serverDeviceId,
    required this.expiresAt,
    required this.canUpload,
  });

  final String plaintextCode;
  final String serverDeviceId;
  final DateTime expiresAt;
  final bool canUpload;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  Duration get remainingTime {
    final diff = expiresAt.toUtc().difference(DateTime.now().toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }
}

class PairingRepository {
  final SupabaseClient _db = Supabase.instance.client;

  static String generateRandomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<PairingCodeInfo> createPairingCode({
    required String serverDeviceId,
    bool canUpload = false,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null)
      throw StateError('Sign-in required to create pairing codes');

    final code = generateRandomCode();
    final hash = sha256.convert(utf8.encode(code)).toString();
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 5));

    await _db.from('pairing_codes').insert({
      'owner_id': user.id,
      'server_device_id': serverDeviceId,
      'code_hash': hash,
      'can_upload': canUpload,
    });

    return PairingCodeInfo(
      plaintextCode: code,
      serverDeviceId: serverDeviceId,
      expiresAt: expiresAt,
      canUpload: canUpload,
    );
  }
}
