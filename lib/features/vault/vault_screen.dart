import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  List<FileSystemEntity> _files = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<Directory> _vaultDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/pocketcloud_vault');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dir = await _vaultDir();
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      if (mounted) setState(() => _files = files);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not read the local cloud library.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importFiles() async {
    try {
      // file_picker v12+ returns a List<PlatformFile>, not FilePickerResult.
      // Stream bytes into app-private storage so large imports do not require
      // holding the entire file in RAM and SAF-backed selections work.
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty) return;

      final dir = await _vaultDir();
      var imported = 0;
      for (final item in picked) {
        final name = _safeName(item.name);
        var target = File('${dir.path}/$name');

        if (await target.exists()) {
          final dot = name.lastIndexOf('.');
          final stem = dot > 0 ? name.substring(0, dot) : name;
          final ext = dot > 0 ? name.substring(dot) : '';
          var suffix = DateTime.now().microsecondsSinceEpoch;

          target = File('${dir.path}/${stem}_$suffix$ext');
          while (await target.exists()) {
            suffix++;
            target = File('${dir.path}/${stem}_$suffix$ext');
          }
        }

        var tempStamp = DateTime.now().microsecondsSinceEpoch;
        var temp = File('${dir.path}/.pocketcloud-import-$tempStamp.part');
        while (await temp.exists()) {
          tempStamp++;
          temp = File('${dir.path}/.pocketcloud-import-$tempStamp.part');
        }

        try {
          await item.readAsByteStream().pipe(temp.openWrite());
          // Avoid replacing a file if another import created the same name.
          if (await target.exists()) {
            final dot = name.lastIndexOf('.');
            final stem = dot > 0 ? name.substring(0, dot) : name;
            final ext = dot > 0 ? name.substring(dot) : '';
            var suffix = DateTime.now().microsecondsSinceEpoch;
            do {
              target = File('${dir.path}/${stem}_$suffix$ext');
              suffix++;
            } while (await target.exists());
          }
          await temp.rename(target.path);
          imported++;
        } catch (_) {
          try {
            if (await temp.exists()) await temp.delete();
          } catch (_) {}
          rethrow;
        }
      }

      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$imported file(s) added to this phone’s app-private vault.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed. Check available storage and file access.')),
        );
      }
    }
  }

  String _safeName(String input) => input
      .replaceAll(RegExp(r'[/\\\x00-\x1F]'), '_')
      .replaceAll('..', '_')
      .trim()
      .isEmpty
      ? 'file_${DateTime.now().millisecondsSinceEpoch}'
      : input
          .replaceAll(RegExp(r'[/\\\x00-\x1F]'), '_')
          .replaceAll('..', '_')
          .trim();

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud library'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importFiles,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add files'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _files.isEmpty
                  ? const Center(
                      child: Text('Your vault is empty.'),
                    )
                  : ListView.builder(
                      itemCount: _files.length,
                      itemBuilder: (context, index) {
                        final file = _files[index];
                        final displayName = file.uri.pathSegments.isNotEmpty
                            ? file.uri.pathSegments.last
                            : 'file';

                        return ListTile(
                          title: Text(displayName),
                          subtitle: FutureBuilder<int>(
                            future: file is File ? file.length() : Future.value(0),
                            builder: (context, snapshot) {
                              final bytes = snapshot.data ?? 0;
                              return Text(_formatSize(bytes));
                            },
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.share_rounded),
                            onPressed: () async {
                              if (file is File) {
                                await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Shared from PocketCloud'));
                              }
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}
