import 'package:archive/archive_io.dart';

void main() {
  const path = 'tmp_bundle_21_repack.zip';
  final input = InputFileStream(path);
  final archive = ZipDecoder().decodeBuffer(input);
  input.close();
  print('entries=${archive.length}');
  var idx=0;
  for (final file in archive) {
    idx++;
    if (!file.isFile) continue;
    try {
      final d=file.content as List<int>;
      if (idx % 2000==0) print('ok idx=$idx name=${file.name} size=${d.length}');
    } catch(e) {
      print('FAIL idx=$idx name=${file.name} size=${file.size}');
      print(e);
      return;
    }
  }
  print('all ok');
}
