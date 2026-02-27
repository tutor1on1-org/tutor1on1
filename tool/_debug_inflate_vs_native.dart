import 'package:archive/archive_io.dart';

Future<void> main() async {
  final input = InputFileStream('tmp_bundle_21.zip');
  final dir = ZipDirectory.read(input);
  final hdr = dir.fileHeaders.first;
  final zf = hdr.file!;
  print('file=${zf.filename} comp=${zf.compressedSize} uncomp=${zf.uncompressedSize} method=${zf.compressionMethod}');
  try {
    final native = zf.content; // triggers native
    print('native ok len=${native.length}');
  } catch (e) {
    print('native fail: $e');
  }
  try {
    final raw = zf.rawContent!;
    final out = Inflate.buffer(raw, zf.uncompressedSize).getBytes();
    print('inflate buffer ok len=${out.length}');
  } catch (e) {
    print('inflate buffer fail: $e');
  }
  input.close();
}
