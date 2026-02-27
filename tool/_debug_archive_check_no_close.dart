import 'package:archive/archive_io.dart';

Future<void> main() async {
  final input = InputFileStream('tmp_bundle_21.zip');
  final archive = ZipDecoder().decodeBuffer(input);
  print('entries=${archive.length}');
  await extractArchiveToDisk(archive, 'tmp_extract_21_no_close');
  input.close();
  print('extract ok no_close');
}
