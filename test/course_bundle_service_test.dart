import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:tutor1on1/services/course_bundle_service.dart';
import 'package:tutor1on1/services/prompt_bundle_compat.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

Future<void> _withMockTempDir(
  String tempDirPath,
  Future<void> Function() body,
) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_pathProviderChannel, (call) async {
    if (call.method == 'getTemporaryDirectory' ||
        call.method == 'getApplicationDocumentsDirectory') {
      return tempDirPath;
    }
    return null;
  });
  try {
    await body();
  } finally {
    messenger.setMockMethodCallHandler(_pathProviderChannel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'validateBundleForImport handles large zip entries without stream-lifecycle errors',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_service_test_',
      );
      try {
        final zipFile = File(p.join(tempDir.path, 'large_bundle.zip'));
        final archive = Archive();

        final contentsBytes = Uint8List.fromList(
          '1 Root branch\n1.1 Intro lesson\n'.codeUnits,
        );
        archive.addFile(
          ArchiveFile('contents.txt', contentsBytes.length, contentsBytes),
        );

        final lectureBytes =
            Uint8List.fromList('This is the lecture body.'.codeUnits);
        archive.addFile(
            ArchiveFile('1_lecture.txt', lectureBytes.length, lectureBytes));
        archive.addFile(
          ArchiveFile('1.1_lecture.txt', lectureBytes.length, lectureBytes),
        );

        // Keep the archive over the archive package file-buffer window (1 MB)
        // so lazy entry reads must access the underlying stream correctly.
        final random = Random(20260226);
        final filler = Uint8List.fromList(
          List<int>.generate(
            2 * 1024 * 1024,
            (_) => random.nextInt(256),
          ),
        );
        archive
            .addFile(ArchiveFile('filler/random.bin', filler.length, filler));

        final encoded = ZipEncoder().encode(archive);
        expect(encoded, isNotNull);
        await zipFile.writeAsBytes(encoded!, flush: true);

        final service = CourseBundleService();
        await expectLater(service.validateBundleForImport(zipFile), completes);
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'extractBundleFromFile returns an import-ready course root immediately',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_extract_test_',
      );
      try {
        await _withMockTempDir(tempDir.path, () async {
          final zipFile = File(p.join(tempDir.path, 'nested_bundle.zip'));
          final archive = Archive();

          final contentsBytes = Uint8List.fromList(
            utf8.encode('1 Root branch\n1.1 Intro lesson\n'),
          );
          final lectureRoot = Uint8List.fromList(utf8.encode('Root lecture'));
          final lectureChild = Uint8List.fromList(utf8.encode('Child lecture'));
          archive.addFile(
            ArchiveFile(
              'nested_course/contents.txt',
              contentsBytes.length,
              contentsBytes,
            ),
          );
          archive.addFile(
            ArchiveFile(
              'nested_course/1_lecture.txt',
              lectureRoot.length,
              lectureRoot,
            ),
          );
          archive.addFile(
            ArchiveFile(
              'nested_course/1.1_lecture.txt',
              lectureChild.length,
              lectureChild,
            ),
          );

          // Keep extracted payload large so the test catches missing await
          // behavior in extraction/import ordering.
          final random = Random(20260227);
          final filler = Uint8List.fromList(
            List<int>.generate(
              2 * 1024 * 1024,
              (_) => random.nextInt(256),
            ),
          );
          archive.addFile(
            ArchiveFile(
                'nested_course/assets/large.bin', filler.length, filler),
          );

          final encoded = ZipEncoder().encode(archive);
          expect(encoded, isNotNull);
          await zipFile.writeAsBytes(encoded!, flush: true);

          final service = CourseBundleService();
          final extractedPath = await service.extractBundleFromFile(
            bundleFile: zipFile,
            courseName: 'Algebra',
          );

          expect(
            File(p.join(extractedPath, 'contents.txt')).existsSync(),
            isTrue,
          );
          expect(
            File(p.join(extractedPath, '1_lecture.txt')).existsSync(),
            isTrue,
          );
          expect(
            File(p.join(extractedPath, '1.1_lecture.txt')).existsSync(),
            isTrue,
          );

          final diff = await service.compareCourseFolderWithBundle(
            folderPath: extractedPath,
            bundleFile: zipFile,
          );
          expect(diff.addedCount, equals(0));
          expect(diff.removedCount, equals(0));
          expect(diff.updatedCount, equals(0));
        });
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'readPromptMetadataFromBundleFile handles large zip entries without stream-lifecycle errors',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_metadata_test_',
      );
      try {
        final zipFile = File(p.join(tempDir.path, 'metadata_bundle.zip'));
        final archive = Archive();
        final contentsBytes = Uint8List.fromList(
          utf8.encode('1 Root branch\n'),
        );
        final lectureBytes = Uint8List.fromList(utf8.encode('Lecture body'));
        archive.addFile(
          ArchiveFile('contents.txt', contentsBytes.length, contentsBytes),
        );
        archive.addFile(
          ArchiveFile('1_lecture.txt', lectureBytes.length, lectureBytes),
        );

        final random = Random(20260227);
        final filler = Uint8List.fromList(
          List<int>.generate(
            2 * 1024 * 1024,
            (_) => random.nextInt(256),
          ),
        );
        archive.addFile(
          ArchiveFile('filler/random.bin', filler.length, filler),
        );

        final metadata = {
          'schema': kCurrentPromptBundleSchema,
          'teacher_username': 'alice',
          'prompt_templates': [
            {'prompt_name': 'learn', 'content': 'Use examples'}
          ],
        };
        final metadataBytes =
            Uint8List.fromList(utf8.encode(jsonEncode(metadata)));
        archive.addFile(
          ArchiveFile(
            CourseBundleService.promptMetadataEntryPath,
            metadataBytes.length,
            metadataBytes,
          ),
        );

        final encoded = ZipEncoder().encode(archive);
        expect(encoded, isNotNull);
        await zipFile.writeAsBytes(encoded!, flush: true);

        final service = CourseBundleService();
        final actual = await service.readPromptMetadataFromBundleFile(zipFile);
        expect(actual, isNotNull);
        expect(actual!['schema'], equals(kCurrentPromptBundleSchema));
        expect(actual['teacher_username'], equals('alice'));
        final templates = (actual['prompt_templates'] as List?) ?? const [];
        expect(templates.length, equals(1));
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'computeBundleSemanticHash ignores prompt metadata generated_at field',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_hash_test_',
      );
      try {
        Future<File> writeBundle({
          required String fileName,
          required String metadataJson,
        }) async {
          final archive = Archive();
          final contentsBytes = Uint8List.fromList(
            utf8.encode('1 Root branch\n1.1 Intro lesson\n'),
          );
          archive.addFile(
            ArchiveFile('contents.txt', contentsBytes.length, contentsBytes),
          );
          final lecture1 = Uint8List.fromList(utf8.encode('Lecture 1'));
          final lecture2 = Uint8List.fromList(utf8.encode('Lecture 1.1'));
          archive.addFile(
            ArchiveFile('1_lecture.txt', lecture1.length, lecture1),
          );
          archive.addFile(
            ArchiveFile('1.1_lecture.txt', lecture2.length, lecture2),
          );
          final metadataBytes = Uint8List.fromList(utf8.encode(metadataJson));
          archive.addFile(
            ArchiveFile(
              CourseBundleService.promptMetadataEntryPath,
              metadataBytes.length,
              metadataBytes,
            ),
          );
          final zipBytes = ZipEncoder().encode(archive);
          expect(zipBytes, isNotNull);
          final file = File(p.join(tempDir.path, fileName));
          await file.writeAsBytes(zipBytes!, flush: true);
          return file;
        }

        final bundleA = await writeBundle(
          fileName: 'bundle_a.zip',
          metadataJson: jsonEncode({
            'schema': kCurrentPromptBundleSchema,
            'generated_at': '2026-02-27T10:00:00Z',
            'teacher_username': 'alice',
            'prompt_templates': [
              {'prompt_name': 'learn', 'content': 'A'}
            ],
          }),
        );
        final bundleB = await writeBundle(
          fileName: 'bundle_b.zip',
          metadataJson: jsonEncode({
            'teacher_username': 'alice',
            'prompt_templates': [
              {'content': 'A', 'prompt_name': 'learn'}
            ],
            'generated_at': '2026-02-27T10:05:00Z',
            'schema': kCurrentPromptBundleSchema,
          }),
        );

        final service = CourseBundleService();
        final hashA = await service.computeBundleSemanticHash(bundleA);
        final hashB = await service.computeBundleSemanticHash(bundleB);
        expect(hashA, isNotEmpty);
        expect(hashA, equals(hashB));
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'compareCourseFolderWithBundle reports added removed and updated KP counts',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_diff_test_',
      );
      try {
        final localFolder = Directory(p.join(tempDir.path, 'local_course'))
          ..createSync(recursive: true);
        await File(p.join(localFolder.path, 'contents.txt')).writeAsString(
          '1 Root branch\n1.1 Updated lesson title\n2 Newly added branch\n',
          encoding: utf8,
        );
        await File(p.join(localFolder.path, '1_lecture.txt')).writeAsString(
          'Lecture root unchanged',
          encoding: utf8,
        );
        await File(p.join(localFolder.path, '1.1_lecture.txt')).writeAsString(
          'Lecture updated content',
          encoding: utf8,
        );
        await File(p.join(localFolder.path, '2_lecture.txt')).writeAsString(
          'Lecture for new node',
          encoding: utf8,
        );

        final archive = Archive();
        final oldContents = Uint8List.fromList(
          utf8.encode(
              '1 Root branch\n1.1 Old lesson title\n3 Removed branch\n'),
        );
        archive.addFile(
          ArchiveFile('contents.txt', oldContents.length, oldContents),
        );
        final oldLecture1 = Uint8List.fromList(
          utf8.encode('Lecture root unchanged'),
        );
        final oldLecture11 =
            Uint8List.fromList(utf8.encode('Lecture old content'));
        final oldLecture3 =
            Uint8List.fromList(utf8.encode('Lecture removed node'));
        archive.addFile(
          ArchiveFile('1_lecture.txt', oldLecture1.length, oldLecture1),
        );
        archive.addFile(
          ArchiveFile('1.1_lecture.txt', oldLecture11.length, oldLecture11),
        );
        archive.addFile(
          ArchiveFile('3_lecture.txt', oldLecture3.length, oldLecture3),
        );
        final zipBytes = ZipEncoder().encode(archive);
        expect(zipBytes, isNotNull);
        final oldBundle = File(p.join(tempDir.path, 'old_bundle.zip'));
        await oldBundle.writeAsBytes(zipBytes!, flush: true);

        final service = CourseBundleService();
        final diff = await service.compareCourseFolderWithBundle(
          folderPath: localFolder.path,
          bundleFile: oldBundle,
        );
        expect(diff.addedCount, equals(1));
        expect(diff.removedCount, equals(1));
        expect(diff.updatedCount, equals(1));
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'createBundleFromFolder includes only required course/prompt txt files',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_create_test_',
      );
      try {
        await _withMockTempDir(tempDir.path, () async {
          final courseDir = Directory(p.join(tempDir.path, 'course'))
            ..createSync(recursive: true);
          await File(p.join(courseDir.path, 'contents.txt')).writeAsString(
            '1 Root branch\n1.1 Child branch\n',
            encoding: utf8,
          );
          await File(p.join(courseDir.path, '1_lecture.txt')).writeAsString(
            'Lecture root',
            encoding: utf8,
          );
          await File(p.join(courseDir.path, '1.1_lecture.txt')).writeAsString(
            'Lecture child',
            encoding: utf8,
          );
          final promptsDir = Directory(p.join(courseDir.path, 'prompts'))
            ..createSync(recursive: true);
          await File(p.join(promptsDir.path, 'learn.txt')).writeAsString(
            'Prompt content',
            encoding: utf8,
          );
          await File(p.join(courseDir.path, 'notes.md')).writeAsString(
            'Not required',
            encoding: utf8,
          );
          await File(p.join(courseDir.path, 'cache.bin')).writeAsBytes(
            Uint8List.fromList([1, 2, 3, 4]),
            flush: true,
          );
          final macDir = Directory(p.join(courseDir.path, '__MACOSX'))
            ..createSync(recursive: true);
          await File(p.join(macDir.path, 'junk.txt')).writeAsString(
            'junk',
            encoding: utf8,
          );

          final service = CourseBundleService();
          final bundle = await service.createBundleFromFolder(
            courseDir.path,
            promptMetadata: {
              'schema': kCurrentPromptBundleSchema,
              'teacher_username': 'alice',
            },
          );

          final archive = ZipDecoder().decodeBytes(await bundle.readAsBytes());
          final names = archive.files
              .where((entry) => entry.isFile)
              .map((entry) => entry.name.replaceAll('\\', '/'))
              .toSet();

          expect(
            names,
            equals({
              'contents.txt',
              '1_lecture.txt',
              '1.1_lecture.txt',
              'prompts/learn.txt',
              CourseBundleService.promptMetadataEntryPath,
            }),
          );
        });
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'irrelevant non-required files do not change semantic hash',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_hash_stability_test_',
      );
      try {
        await _withMockTempDir(tempDir.path, () async {
          final courseDir = Directory(p.join(tempDir.path, 'course'))
            ..createSync(recursive: true);
          await File(p.join(courseDir.path, 'contents.txt')).writeAsString(
            '1 Root branch\n',
            encoding: utf8,
          );
          final lecturePath = p.join(courseDir.path, '1_lecture.txt');
          await File(lecturePath).writeAsString(
            'Stable lecture content',
            encoding: utf8,
          );

          final service = CourseBundleService();
          final bundleA = await service.createBundleFromFolder(courseDir.path);
          final hashA = await service.computeBundleSemanticHash(bundleA);

          await File(p.join(courseDir.path, 'random.log')).writeAsString(
            'noise ${DateTime.now().millisecondsSinceEpoch}',
            encoding: utf8,
          );
          await File(p.join(courseDir.path, 'README.md')).writeAsString(
            'markdown noise',
            encoding: utf8,
          );
          final macDir = Directory(p.join(courseDir.path, '__MACOSX'))
            ..createSync(recursive: true);
          await File(p.join(macDir.path, 'noise.txt')).writeAsString(
            'ignored noise',
            encoding: utf8,
          );

          final bundleB = await service.createBundleFromFolder(courseDir.path);
          final hashB = await service.computeBundleSemanticHash(bundleB);

          expect(hashB, equals(hashA));

          await File(lecturePath).writeAsString(
            'Changed lecture content',
            encoding: utf8,
          );
          final bundleC = await service.createBundleFromFolder(courseDir.path);
          final hashC = await service.computeBundleSemanticHash(bundleC);
          expect(hashC, isNot(equals(hashA)));
        });
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );
}
