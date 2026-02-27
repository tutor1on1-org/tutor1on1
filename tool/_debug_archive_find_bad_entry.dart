import 'dart:io';
import 'package:archive/archive_io.dart';

void main() {
  const path = 'tmp_bundle_21.zip';
  final input = InputFileStream(path);
  final archive = ZipDecoder().decodeBuffer(input);
  input.close();
  stdout.writeln('entries=${archive.length}');
  var idx = 0;
  for (final file in archive) {
    idx++;
    if (!file.isFile) {
      continue;
    }
    try {
      final data = file.content as List<int>;
      if (idx % 500 == 0) {
        stdout.writeln('ok idx=$idx name=${file.name} size=${data.length}');
      }
    } catch (e) {
      stdout.writeln('FAILED idx=$idx name=${file.name} size=${file.size}');
      stdout.writeln('error=$e');
      exit(1);
    }
  }
  stdout.writeln('all entries readable');
}
