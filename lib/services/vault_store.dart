import 'dart:io';
import 'package:path_provider/path_provider.dart';

class VaultEntry {
  const VaultEntry({required this.name, required this.size});
  final String name;
  final int size;
  Map<String, Object> toJson() => {'name': name, 'size': size};
}

class VaultStore {
  static const maxFileBytes = 25 * 1024 * 1024;

  Future<Directory> directory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/pocketcloud_vault');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String safeName(String raw) {
    final name = raw
        .split('/')
        .last
        .split('\\')
        .last
        .replaceAll(RegExp(r'[\x00-\x1F]'), '_')
        .replaceAll('..', '_')
        .trim();
    if (name.isEmpty || name == '.' || name == '..')
      throw const FormatException('Invalid file name');
    return name.length > 180 ? name.substring(name.length - 180) : name;
  }

  Future<List<VaultEntry>> list() async {
    final dir = await directory();
    final result = <VaultEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final name = entity.path.split(Platform.pathSeparator).last;
        final size = await entity.length();
        result.add(VaultEntry(name: name, size: size));
      } on FileSystemException {
        // A file may be deleted while the UI is refreshing it; skip that entry.
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<File> fileForName(String rawName) async {
    final name = safeName(rawName);
    final dir = await directory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    final resolvedDir = await dir.resolveSymbolicLinks();
    final resolvedParent = await file.parent.resolveSymbolicLinks();
    if (resolvedParent != resolvedDir)
      throw const FormatException('Invalid destination');
    return file;
  }

  Future<File> _availableTarget(String name) async {
    var target = await fileForName(name);
    if (!await target.exists()) return target;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var suffix = DateTime.now().microsecondsSinceEpoch;
    do {
      target = await fileForName('${stem}_$suffix$ext');
      suffix++;
    } while (await target.exists());
    return target;
  }

  Future<File> saveReceived(String rawName, List<int> bytes) async {
    if (bytes.length > maxFileBytes)
      throw const FormatException('File exceeds the 25 MB MVP limit');
    final name = safeName(rawName);
    var target = await _availableTarget(name);
    final dir = await directory();
    var suffix = DateTime.now().microsecondsSinceEpoch;
    var temp = File(
      '${dir.path}${Platform.pathSeparator}.pocketcloud-$suffix.part',
    );
    while (await temp.exists()) {
      suffix++;
      temp = File(
        '${dir.path}${Platform.pathSeparator}.pocketcloud-$suffix.part',
      );
    }
    try {
      await temp.writeAsBytes(bytes, flush: true);
      // Recheck immediately before rename to avoid overwriting a colliding import.
      if (await target.exists()) target = await _availableTarget(name);
      return await temp.rename(target.path);
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      rethrow;
    }
  }
}
