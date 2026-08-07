import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

import 'browser_exclusive_lock.dart';
import 'file_system_errors.dart';

abstract class FileSystemEntity {
  const FileSystemEntity(this.path);

  final String path;
}

class FileMode {
  const FileMode._(this.isAppend);

  static const write = FileMode._(false);
  static const append = FileMode._(true);

  final bool isAppend;
}

class File extends FileSystemEntity {
  File(String rawPath) : super(_BrowserFileStore.normalize(rawPath));

  Directory get parent => Directory(_BrowserFileStore.parentOf(path));
  File get absolute => this;

  bool existsSync() => _BrowserFileStore.instance.isFile(path);

  Future<bool> exists() async => existsSync();

  int lengthSync() => _BrowserFileStore.instance.lengthOf(path);

  Future<int> length() async => lengthSync();

  Uint8List readAsBytesSync() => _BrowserFileStore.instance.readSync(path);

  Future<Uint8List> readAsBytes() => _BrowserFileStore.instance.read(path);

  String readAsStringSync({Encoding encoding = utf8}) =>
      encoding.decode(readAsBytesSync());

  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());

  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    await _BrowserFileStore.instance.write(
      path,
      Uint8List.fromList(bytes),
      append: mode.isAppend,
    );
    return this;
  }

  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    _BrowserFileStore.instance.writeSync(
      path,
      Uint8List.fromList(bytes),
      append: mode.isAppend,
    );
  }

  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      writeAsBytes(encoding.encode(contents), mode: mode, flush: flush);

  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    writeAsBytesSync(encoding.encode(contents), mode: mode, flush: flush);
  }

  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    if (exclusive && existsSync()) {
      throw StateError('File already exists: $path');
    }
    if (recursive) {
      await parent.create(recursive: true);
    }
    if (!existsSync()) {
      await writeAsBytes(const <int>[]);
    }
    return this;
  }

  void createSync({bool recursive = false, bool exclusive = false}) {
    if (exclusive && existsSync()) {
      throw StateError('File already exists: $path');
    }
    if (recursive) {
      parent.createSync(recursive: true);
    }
    if (!existsSync()) {
      writeAsBytesSync(const <int>[]);
    }
  }

  Future<File> copy(String newPath) async {
    final target = File(newPath);
    await target.writeAsBytes(await readAsBytes());
    return target;
  }

  Future<File> rename(String newPath) async {
    final target = await copy(newPath);
    await delete();
    return target;
  }

  Future<FileSystemEntity> delete({bool recursive = false}) async {
    await _BrowserFileStore.instance.delete(path);
    return this;
  }
}

class Directory extends FileSystemEntity {
  Directory(String rawPath) : super(_BrowserFileStore.normalize(rawPath));

  static Directory get current => Directory('/tutor1on1');
  static Directory get systemTemp => Directory('/tutor1on1/tmp');

  Directory get parent => Directory(_BrowserFileStore.parentOf(path));
  Directory get absolute => this;

  bool existsSync() => _BrowserFileStore.instance.isDirectory(path);

  Future<bool> exists() async => existsSync();

  Future<Directory> create({bool recursive = false}) async {
    await _BrowserFileStore.instance.createDirectoryAsync(
      path,
      recursive: recursive,
    );
    return this;
  }

  void createSync({bool recursive = false}) {
    _BrowserFileStore.instance.createDirectory(path, recursive: recursive);
  }

  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) =>
      _BrowserFileStore.instance.list(path, recursive: recursive);

  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) =>
      Stream<FileSystemEntity>.fromIterable(listSync(recursive: recursive));

  Future<FileSystemEntity> delete({bool recursive = false}) async {
    if (!recursive && listSync().isNotEmpty) {
      throw StateError('Directory is not empty: $path');
    }
    await _BrowserFileStore.instance
        .deleteDirectory(path, recursive: recursive);
    return this;
  }
}

class _BrowserFileStore {
  _BrowserFileStore._() {
    _loadIndex();
    createDirectory('/tutor1on1', recursive: true);
    _storageListener = ((web.Event _) {
      _memory.clear();
      _loadIndex();
    }).toJS;
    web.window.addEventListener('storage', _storageListener);
  }

  static final instance = _BrowserFileStore._();
  static const _indexKey = 'tutor1on1.vfs.index.v1';
  static const _cacheName = 'tutor1on1-vfs-v1';
  static const _lockName = 'tutor1on1-vfs-store-v1';

  final Map<String, _FileMetadata> _index = <String, _FileMetadata>{};
  final Map<String, Uint8List> _memory = <String, Uint8List>{};
  final Map<String, Future<void>> _pendingWrites = <String, Future<void>>{};
  late final web.EventListener _storageListener;

  static String normalize(String value) {
    var resolved = value.trim().replaceAll('\\', '/');
    if (resolved.isEmpty || resolved == '.') {
      return '/tutor1on1';
    }
    if (!resolved.startsWith('/')) {
      resolved = '/tutor1on1/$resolved';
    }
    resolved = p.posix.normalize(resolved);
    return resolved.length > 1 && resolved.endsWith('/')
        ? resolved.substring(0, resolved.length - 1)
        : resolved;
  }

  static String parentOf(String value) {
    final parent = p.posix.dirname(normalize(value));
    return parent == '.' ? '/' : parent;
  }

  bool isFile(String value) {
    _loadIndex();
    final resolved = normalize(value);
    return _index[resolved]?.kind == 'file' ||
        (_pendingWrites.containsKey(resolved) && _memory.containsKey(resolved));
  }

  bool isDirectory(String value) {
    _loadIndex();
    return _index[normalize(value)]?.kind == 'directory';
  }

  int lengthOf(String value) {
    _loadIndex();
    final resolved = normalize(value);
    final pendingBytes =
        _pendingWrites.containsKey(resolved) ? _memory[resolved] : null;
    if (pendingBytes != null) {
      return pendingBytes.length;
    }
    final metadata = _index[resolved];
    if (metadata == null || metadata.kind != 'file') {
      throw StateError('File does not exist: $value');
    }
    return metadata.length;
  }

  Uint8List readSync(String value) {
    _loadIndex();
    final resolved = normalize(value);
    if (_index[resolved]?.kind != 'file' &&
        !_pendingWrites.containsKey(resolved)) {
      _memory.remove(resolved);
      throw StateError('File does not exist: $resolved');
    }
    final bytes = _memory[resolved];
    if (bytes == null) {
      throw StateError('File must be loaded asynchronously first: $resolved');
    }
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> read(String value) async {
    final resolved = normalize(value);
    final pending = _pendingWrites[resolved];
    if (pending != null) {
      await pending;
    }
    final bytes = await runWithBrowserExclusiveLock<Uint8List>(
      _lockName,
      () async {
        _loadIndex();
        if (_index[resolved]?.kind != 'file') {
          _memory.remove(resolved);
          throw StateError('File does not exist: $resolved');
        }
        final stored = await _readStoredFresh(resolved);
        _memory[resolved] = Uint8List.fromList(stored);
        return Uint8List.fromList(stored);
      },
    );
    if (bytes == null) {
      throw StateError('Browser file lock was not acquired: $resolved');
    }
    return bytes;
  }

  Future<void> write(
    String value,
    Uint8List bytes, {
    required bool append,
  }) async {
    final resolved = normalize(value);
    final previous = _pendingWrites[resolved] ?? Future<void>.value();
    final operation = previous.then(
      (_) => _commitFile(resolved, bytes, append: append),
    );
    _pendingWrites[resolved] = operation;
    try {
      await operation;
    } finally {
      if (identical(_pendingWrites[resolved], operation)) {
        _pendingWrites.remove(resolved);
      }
    }
  }

  void writeSync(
    String value,
    Uint8List bytes, {
    required bool append,
  }) {
    final resolved = normalize(value);
    _loadIndex();
    final current = append ? _memory[resolved] : null;
    final hasStoredOrPendingFile = _index[resolved]?.kind == 'file' ||
        _pendingWrites.containsKey(resolved);
    if (append && hasStoredOrPendingFile && current == null) {
      throw StateError('Append requires an asynchronous read first: $resolved');
    }
    final combined = current == null
        ? Uint8List.fromList(bytes)
        : Uint8List.fromList(<int>[...current, ...bytes]);
    createDirectory(parentOf(resolved), recursive: true);
    _memory[resolved] = Uint8List.fromList(combined);
    final previous = _pendingWrites[resolved] ?? Future<void>.value();
    final operation = previous.then(
      (_) => _commitFile(resolved, combined, append: false),
    );
    _pendingWrites[resolved] = operation;
    unawaited(operation.whenComplete(() {
      if (identical(_pendingWrites[resolved], operation)) {
        _pendingWrites.remove(resolved);
      }
    }));
  }

  void createDirectory(String value, {required bool recursive}) {
    _loadIndex();
    _recordDirectory(value, recursive: recursive);
    _saveIndex();
  }

  Future<void> createDirectoryAsync(
    String value, {
    required bool recursive,
  }) async {
    await runWithBrowserExclusiveLock<void>(_lockName, () async {
      _loadIndex();
      _recordDirectory(value, recursive: recursive);
      _saveIndex();
    });
  }

  void _recordDirectory(String value, {required bool recursive}) {
    final resolved = normalize(value);
    if (recursive) {
      var cursor = resolved;
      final parents = <String>[];
      while (cursor != '/' && cursor.isNotEmpty) {
        parents.add(cursor);
        cursor = parentOf(cursor);
      }
      for (final directory in parents.reversed) {
        _index[directory] = const _FileMetadata.directory();
      }
    } else {
      final parent = parentOf(resolved);
      if (resolved != '/' && _index[parent]?.kind != 'directory') {
        throw StateError('Parent directory does not exist: $parent');
      }
      _index[resolved] = const _FileMetadata.directory();
    }
  }

  List<FileSystemEntity> list(String value, {required bool recursive}) {
    _loadIndex();
    final resolved = normalize(value);
    if (_index[resolved]?.kind != 'directory') {
      return const <FileSystemEntity>[];
    }
    final prefix = resolved == '/' ? '/' : '$resolved/';
    final result = <FileSystemEntity>[];
    for (final entry in _index.entries) {
      if (!entry.key.startsWith(prefix) || entry.key == resolved) {
        continue;
      }
      final remainder = entry.key.substring(prefix.length);
      if (!recursive && remainder.contains('/')) {
        continue;
      }
      result.add(
          entry.value.kind == 'file' ? File(entry.key) : Directory(entry.key));
    }
    result.sort((left, right) => left.path.compareTo(right.path));
    return result;
  }

  Future<void> delete(String value) async {
    final resolved = normalize(value);
    final pending = _pendingWrites[resolved];
    if (pending != null) {
      await pending;
    }
    await runWithBrowserExclusiveLock<void>(_lockName, () async {
      final cache = await web.window.caches.open(_cacheName).toDart;
      await cache.delete(_request(resolved)).toDart;
      _loadIndex();
      _index.remove(resolved);
      _memory.remove(resolved);
      _saveIndex();
    });
  }

  Future<void> deleteDirectory(String value, {required bool recursive}) async {
    final resolved = normalize(value);
    final pending = _pendingWrites.values.toList(growable: false);
    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
    await runWithBrowserExclusiveLock<void>(_lockName, () async {
      _loadIndex();
      final prefix = '$resolved/';
      final descendants = _index.keys
          .where((key) => key.startsWith(prefix))
          .toList(growable: false);
      if (!recursive && descendants.isNotEmpty) {
        throw StateError('Directory is not empty: $resolved');
      }
      final files = _index.entries
          .where(
            (entry) =>
                entry.value.kind == 'file' &&
                (entry.key == resolved || entry.key.startsWith(prefix)),
          )
          .map((entry) => entry.key)
          .toList(growable: false);
      final cache = await web.window.caches.open(_cacheName).toDart;
      for (final file in files) {
        await cache.delete(_request(file)).toDart;
      }
      _index.removeWhere(
        (key, _) => key == resolved || key.startsWith(prefix),
      );
      for (final key in <String>[resolved, ...descendants]) {
        _memory.remove(key);
      }
      _saveIndex();
    });
  }

  Future<void> _commitFile(
    String resolved,
    Uint8List bytes, {
    required bool append,
  }) async {
    await runWithBrowserExclusiveLock<void>(_lockName, () async {
      _loadIndex();
      final combined = append && _index[resolved]?.kind == 'file'
          ? Uint8List.fromList(
              <int>[...await _readStoredFresh(resolved), ...bytes],
            )
          : Uint8List.fromList(bytes);
      await _persistFile(resolved, combined);
      _recordDirectory(parentOf(resolved), recursive: true);
      _index[resolved] = _FileMetadata.file(combined.length);
      _memory[resolved] = Uint8List.fromList(combined);
      _saveIndex();
    });
  }

  Future<void> _persistFile(String resolved, Uint8List bytes) async {
    final blob = web.Blob(
      <web.BlobPart>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final cache = await web.window.caches.open(_cacheName).toDart;
    await cache.put(_request(resolved), web.Response(blob)).toDart;
  }

  Future<Uint8List> _readStoredFresh(String resolved) async {
    final cache = await web.window.caches.open(_cacheName).toDart;
    final response = await cache.match(_request(resolved)).toDart;
    if (response == null) {
      _removeStaleFileMetadata(resolved);
      throw FileSystemDataMissingException(resolved);
    }
    final buffer = await response.arrayBuffer().toDart;
    return Uint8List.view(buffer.toDart);
  }

  void _removeStaleFileMetadata(String resolved) {
    _loadIndex();
    if (_index.remove(resolved) != null) {
      _saveIndex();
    }
    _memory.remove(resolved);
  }

  web.Request _request(String resolved) {
    final encoded = base64Url.encode(utf8.encode(resolved));
    final url = Uri.base.resolve('__tutor1on1_vfs__/$encoded').toString();
    return web.Request(url.toJS);
  }

  void _loadIndex() {
    try {
      _index.clear();
      final raw = web.window.localStorage.getItem(_indexKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            _index[normalize(entry.key.toString())] = _FileMetadata.fromJson(
                Map<String, dynamic>.from(entry.value as Map));
          }
        }
      }
    } catch (_) {
      _index.clear();
    }
  }

  void _saveIndex() {
    final data = _index.map((key, value) => MapEntry(key, value.toJson()));
    web.window.localStorage.setItem(_indexKey, jsonEncode(data));
  }
}

class _FileMetadata {
  const _FileMetadata._(this.kind, this.length);
  const _FileMetadata.directory() : this._('directory', 0);
  const _FileMetadata.file(int length) : this._('file', length);

  factory _FileMetadata.fromJson(Map<String, dynamic> json) => _FileMetadata._(
        json['kind'] == 'file' ? 'file' : 'directory',
        (json['length'] as num?)?.toInt() ?? 0,
      );

  final String kind;
  final int length;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'length': length,
      };
}

class IOSink {
  Never _unsupported() => throw UnsupportedError('IOSink is not used on web.');
  void add(List<int> data) => _unsupported();
  Future<void> addStream(Stream<List<int>> stream) => _unsupported();
  Future<void> flush() => _unsupported();
  Future<void> close() => _unsupported();
}
