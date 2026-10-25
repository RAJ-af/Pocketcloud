import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_theme.dart';
import '../../services/device_repository.dart';
import '../devices/devices_screen.dart';
import '../security/security_screen.dart';
import '../../services/webrtc_transfer_service.dart';
import '../vault/vault_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = DeviceRepository();
  Map<String, dynamic>? _device;
  bool _serverEnabled = false;
  bool _working = true;
  String _network = 'Checking network';
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  Timer? _heartbeat;
  WebRtcTransferService? _hostTransfer;

  @override
  void initState() {
    super.initState();
    _load();
    _connectivity = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() => _network = results.any((r) => r != ConnectivityResult.none) ? 'Online' : 'Offline');
      }
    });
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    _heartbeat?.cancel();
    final id = _device?['id']?.toString();
    if (id != null) {
      unawaited(_repo.markOffline(id).catchError((Object _) {}));
    }
    unawaited(_stopHostListener());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _working = true);
    try {
      final device = await _repo.ensureThisDevice();
      if (!mounted) return;
      setState(() {
        _device = device;
        _serverEnabled = device['server_enabled'] == true;
      });
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_repo.markOnline(device['id'] as String).catchError((Object _) {})));
      // The database flag survives app navigation/relaunch; the actual peer
      // listener does not. Recreate it while this Flutter process is alive.
      if (device['server_enabled'] == true) {
        await _startHostListener(device['id'] as String);
      }
    } catch (_) {
      if (mounted) _message('Could not register this device. Check the database migration and sign-in.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggleServer(bool on) async {
    if (_device == null) return;
    setState(() => _working = true);
    try {
      final id = _device!['id'] as String;
      await _repo.setServerEnabled(id, on);
      if (mounted) {
        setState(() {
          _serverEnabled = on;
          _device = {..._device!, 'server_enabled': on, 'role': on ? 'server' : 'client'};
        });
      }
      if (on) {
        final started = await _startHostListener(id);
        if (started) {
          _message('Server mode enabled. Keep PocketCloud open for this MVP; background survival is not guaranteed on every Android device.');
        }
      } else {
        await _stopHostListener();
      }
    } catch (_) {
      if (mounted) _message('Could not update server status.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _startHostListener(String id) async {
    if (_hostTransfer != null) return true;
    if (!mounted) return false;

    final service = WebRtcTransferService(localDeviceId: id, onStatus: (status, message) {
      if (mounted && status == PeerStatus.failed) _message(message);
    });
    _hostTransfer = service;
    try {
      await service.startListening();
      return true;
    } catch (_) {
      _hostTransfer = null;
      await service.dispose();
      try {
        await _repo.setServerEnabled(id, false);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _serverEnabled = false;
          if (_device != null) {
            _device = {..._device!, 'server_enabled': false, 'role': 'client'};
          }
        });
      }
      _message('Could not start peer listener. Server mode was switched off. Check Realtime settings.');
      return false;
    }
  }

  Future<void> _stopHostListener() async {
    final service = _hostTransfer;
    _hostTransfer = null;
    if (service != null) await service.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? 'Personal cloud';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.cloud_done_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'PocketCloud',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                'Make space\nfor more.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 10),
              Text(
                'Turn a spare phone into storage you can reach from anywhere.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 22),
              _ServerHero(
                enabled: _serverEnabled,
                working: _working,
                onToggle: _toggleServer,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.wifi_rounded,
                      title: 'Network',
                      value: _network,
                      accent: AppColors.aqua,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.folder_shared_rounded,
                      title: 'Vault',
                      value: _device?['server_enabled'] == true ? 'Online' : 'Ready',
                      accent: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Your cloud tools', style: Theme.of(context).textTheme.titleLarge),
                  Text('MVP', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.muted)),
                ],
              ),
              const SizedBox(height: 13),
              _ActionTile(
                icon: Icons.folder_open_rounded,
                title: 'Cloud library',
                detail: 'Choose files to keep on this phone',
                color: AppColors.accent,
                onTap: () => _open(const VaultScreen()),
              ),
              const SizedBox(height: 10),
              _ActionTile(
                icon: Icons.devices_other_rounded,
                title: 'Connected devices',
                detail: 'Pair, view and revoke access',
                color: AppColors.aqua,
                onTap: () => _open(const DevicesScreen()),
              ),
              const SizedBox(height: 10),
              _ActionTile(
                icon: Icons.security_rounded,
                title: 'Security',
                detail: 'Review account safety and permissions',
                color: AppColors.warning,
                onTap: () => _open(const SecurityScreen()),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _working ? 'Syncing your device state…' : 'Everything is ready to keep your cloud library in sync.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _message('PocketCloud is running in MVP mode.'),
                    child: const Text('Details'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Sign out?'),
                          content: const Text('This will disconnect this app from your PocketCloud account.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sign out')),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await Supabase.instance.client.auth.signOut();
                      }
                    },
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerHero extends StatelessWidget {
  const _ServerHero({required this.enabled, required this.working, required this.onToggle});

  final bool enabled;
  final bool working;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent, AppColors.aqua],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: enabled ? AppColors.accent : AppColors.muted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                enabled ? 'Server active' : 'Server offline',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            enabled ? 'Your cloud is\nready to host.' : 'Your phone can\ndo more.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            enabled ? 'This device is marked as a server in your account.' : 'Enable server mode to register this device as your personal host.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: working ? null : () => onToggle(!enabled),
              style: FilledButton.styleFrom(backgroundColor: enabled ? Colors.white : AppColors.accentDark),
              child: Text(enabled ? 'Disable server' : 'Enable server'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.title, required this.value, required this.accent});

  final IconData icon;
  final String title;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.detail, required this.color, required this.onTap});

  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(detail, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

