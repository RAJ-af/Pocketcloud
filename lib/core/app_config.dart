import 'dart:convert';

class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const turnUrl = String.fromEnvironment('TURN_URL');
  static const turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const turnCredential = String.fromEnvironment('TURN_CREDENTIAL');

  static bool get isConfigured {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment || uri.port != 443 || (uri.path.isNotEmpty && uri.path != '/') ||
        uri.host.split('.').length != 3 || !uri.host.toLowerCase().endsWith('.supabase.co')) {
      return false;
    }
    return _isClientKey(supabasePublishableKey);
  }

  static bool _isClientKey(String key) {
    if (key.startsWith('sb_publishable_') && key.length > 'sb_publishable_'.length) return true;
    // Legacy Supabase anon keys are JWTs with role=anon. Reject service_role.
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return payload is Map && payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }
}
