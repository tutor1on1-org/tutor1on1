import 'dart:io';
import 'package:archive/archive_io.dart';

Future<void> main(List<String> args) async {
  final files = ['tmp_bundle_19.zip', 'tmp_bundle_20.zip', 'tmp_bundle_21.zip'];
  for (final path in files) {
    stdout.writeln('checking $path');
    final input = InputFileStream(path);
    final archive = ZipDecoder().decodeBuffer(input);
    input.close();
    stdout.writeln('entries=${archive.length}');
    final outDir = Directory('tmp_extract_${path.split('_').last.replaceAll('.zip', '')}');
    if (outDir.existsSync()) {
      outDir.deleteSync(recursive: true);
    }
    outDir.createSync(recursive: true);
    await extractArchiveToDisk(archive, outDir.path);
    stdout.writeln('extract ok: ${outDir.path}');
  }
}
