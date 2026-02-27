import 'package:archive/archive_io.dart';

Future<void> main() async {
  final input = InputFileStream('tmp_bundle_21_repack.zip');
  final archive = ZipDecoder().decodeBuffer(input);
  input.close();
  print('entries=${archive.length}');
  final out='tmp_extract_21_repack';
  await extractArchiveToDisk(archive,out);
  print('extract ok');
}
