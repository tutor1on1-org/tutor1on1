import 'dart:io';

import 'package:path/path.dart' as p;

class SingleInstanceService {
  SingleInstanceService(this._lockName);

  final String _lockName;
  RandomAccessFile? _lockFile;

  Future<bool> acquire() async {
    final lockPath = p.join(Directory.systemTemp.path, '$_lockName.lock');
    final file = File(lockPath);
    try {
      _lockFile = await file.open(mode: FileMode.write);
      await _lockFile!.lock(FileLock.exclusive);
      return true;
    } catch (_) {
      await _lockFile?.close();
      _lockFile = null;
      return false;
    }
  }

  Future<void> release() async {
    try {
      await _lockFile?.unlock();
    } catch (_) {}
    await _lockFile?.close();
    _lockFile = null;
  }
}
