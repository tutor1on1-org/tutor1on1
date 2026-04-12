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
        call.method == 'getApplicationDocumentsDirectory' ||
        call.method == 'getApplicationSupportDirectory') {
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
    'extractBundleScaffoldFromFile only materializes scaffold files',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_scaffold_test_',
      );
      try {
        await _withMockTempDir(tempDir.path, () async {
          final zipFile = File(p.join(tempDir.path, 'scaffold_bundle.zip'));
          final archive = Archive();

          final contentsBytes = Uint8List.fromList(
            utf8.encode('1 Root branch\n1.1 Intro lesson\n'),
          );
          final lectureBytes = Uint8List.fromList(
            utf8.encode('Lecture body'),
          );
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
              lectureBytes.length,
              lectureBytes,
            ),
          );
          archive.addFile(
            ArchiveFile(
              'nested_course/1.1_lecture.txt',
              lectureBytes.length,
              lectureBytes,
            ),
          );
          final encoded = ZipEncoder().encode(archive);
          expect(encoded, isNotNull);
          await zipFile.writeAsBytes(encoded!, flush: true);

          final service = CourseBundleService();
          final scaffoldPath = await service.extractBundleScaffoldFromFile(
            bundleFile: zipFile,
            courseName: 'Scaffold Course',
          );

          expect(
            File(p.join(scaffoldPath, 'contents.txt')).existsSync(),
            isTrue,
          );
          expect(
            File(p.join(scaffoldPath, '1_lecture.txt')).existsSync(),
            isFalse,
          );
          expect(
            File(p.join(scaffoldPath, '1.1_lecture.txt')).existsSync(),
            isFalse,
          );
        });
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'extractBundleScaffoldFromFile writes lightweight scaffold and bundle entry reads stay available',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_scaffold_test_',
      );
      try {
        await _withMockTempDir(tempDir.path, () async {
          final zipFile = File(p.join(tempDir.path, 'scaffold_bundle.zip'));
          final archive = Archive();
          final contentsBytes = Uint8List.fromList(
            utf8.encode('1 Root branch\n1.1 Intro lesson\n'),
          );
          final contextBytes = Uint8List.fromList(
            utf8.encode('Context body'),
          );
          final lectureBytes = Uint8List.fromList(
            utf8.encode('Lecture body'),
          );
          final questionBytes = Uint8List.fromList(
            utf8.encode('Question body'),
          );
          archive.addFile(
            ArchiveFile(
              'nested_course/contents.txt',
              contentsBytes.length,
              contentsBytes,
            ),
          );
          archive.addFile(
            ArchiveFile(
              'nested_course/context.txt',
              contextBytes.length,
              contextBytes,
            ),
          );
          archive.addFile(
            ArchiveFile(
              'nested_course/1.1_lecture.txt',
              lectureBytes.length,
              lectureBytes,
            ),
          );
          archive.addFile(
            ArchiveFile(
              'nested_course/1.1_easy.txt',
              questionBytes.length,
              questionBytes,
            ),
          );
          final encoded = ZipEncoder().encode(archive);
          expect(encoded, isNotNull);
          await zipFile.writeAsBytes(encoded!, flush: true);

          final service = CourseBundleService();
          final scaffoldPath = await service.extractBundleScaffoldFromFile(
            bundleFile: zipFile,
            courseName: 'Algebra',
          );

          expect(
              File(p.join(scaffoldPath, 'contents.txt')).existsSync(), isTrue);
          expect(
              File(p.join(scaffoldPath, 'context.txt')).existsSync(), isTrue);
          expect(
            File(p.join(scaffoldPath, '1.1_lecture.txt')).existsSync(),
            isFalse,
          );
          expect(
            await service.readTextEntryFromBundleFile(
              bundleFile: zipFile,
              candidateRelativePaths: const <String>[
                '1.1_lecture.txt',
                '1.1/lecture.txt',
              ],
            ),
            'Lecture body',
          );
          expect(
            await service.readTextEntryFromBundleFile(
              bundleFile: zipFile,
              candidateRelativePaths: const <String>[
                '1.1_easy.txt',
                '1.1/easy/questions.txt',
              ],
            ),
            'Question body',
          );
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
    'computeBundleSemanticHash treats legacy and current prompt metadata forms as equivalent',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_hash_prompt_compat_test_',
      );
      try {
        Future<File> writeBundle({
          required String fileName,
          required String metadataEntryPath,
          required Map<String, dynamic> metadata,
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
          final metadataBytes =
              Uint8List.fromList(utf8.encode(jsonEncode(metadata)));
          archive.addFile(
            ArchiveFile(
              metadataEntryPath,
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

        final legacyBundle = await writeBundle(
          fileName: 'bundle_legacy.zip',
          metadataEntryPath: kLegacyPromptMetadataEntryPath,
          metadata: {
            'schema': kLegacyPromptBundleSchema,
            'teacher_username': 'alice',
            'prompt_templates': [
              {'prompt_name': 'learn', 'content': 'A'}
            ],
          },
        );
        final currentBundle = await writeBundle(
          fileName: 'bundle_current.zip',
          metadataEntryPath: kCurrentPromptMetadataEntryPath,
          metadata: {
            'schema': kCurrentPromptBundleSchema,
            'teacher_username': 'alice',
            'prompt_templates': [
              {'prompt_name': 'learn', 'content': 'A'}
            ],
          },
        );

        final service = CourseBundleService();
        final legacyHash =
            await service.computeBundleSemanticHash(legacyBundle);
        final currentHash =
            await service.computeBundleSemanticHash(currentBundle);

        expect(legacyHash, isNotEmpty);
        expect(legacyHash, equals(currentHash));
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

  test('compareCourseFolderWithBundle reports question bank changes', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'course_bundle_question_diff_test_',
    );
    try {
      final localFolder = Directory(p.join(tempDir.path, 'local_course'))
        ..createSync(recursive: true);
      await File(p.join(localFolder.path, 'contents.txt')).writeAsString(
        '1 Root branch\n',
        encoding: utf8,
      );
      await File(p.join(localFolder.path, '1_lecture.txt')).writeAsString(
        'Lecture unchanged',
        encoding: utf8,
      );
      await File(p.join(localFolder.path, '1_medium.txt')).writeAsString(
        'New question bank',
        encoding: utf8,
      );

      final archive = Archive();
      final contents = Uint8List.fromList(utf8.encode('1 Root branch\n'));
      final lecture = Uint8List.fromList(utf8.encode('Lecture unchanged'));
      final oldQuestions = Uint8List.fromList(utf8.encode('Old question bank'));
      archive.addFile(
        ArchiveFile('contents.txt', contents.length, contents),
      );
      archive.addFile(
        ArchiveFile('1_lecture.txt', lecture.length, lecture),
      );
      archive.addFile(
        ArchiveFile('1_medium.txt', oldQuestions.length, oldQuestions),
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
      expect(diff.addedCount, equals(0));
      expect(diff.removedCount, equals(0));
      expect(diff.updatedCount, equals(1));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'createBundleFromFolder includes course prompt and question bank txt files',
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
          await File(p.join(courseDir.path, '1.1_medium.txt')).writeAsString(
            'Question child',
            encoding: utf8,
          );
          final legacyQuestionDir =
              Directory(p.join(courseDir.path, '1.1', 'hard'))
                ..createSync(recursive: true);
          await File(p.join(legacyQuestionDir.path, 'questions.txt'))
              .writeAsString(
            'Legacy hard question child',
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
              '1.1/hard/questions.txt',
              '1.1_medium.txt',
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

          await File(p.join(courseDir.path, '1_medium.txt')).writeAsString(
            'Question bank content',
            encoding: utf8,
          );
          final bundleWithQuestion =
              await service.createBundleFromFolder(courseDir.path);
          final hashWithQuestion =
              await service.computeBundleSemanticHash(bundleWithQuestion);
          expect(hashWithQuestion, isNot(equals(hashA)));

          await File(lecturePath).writeAsString(
            'Changed lecture content',
            encoding: utf8,
          );
          final bundleC = await service.createBundleFromFolder(courseDir.path);
          final hashC = await service.computeBundleSemanticHash(bundleC);
          expect(hashC, isNot(equals(hashWithQuestion)));
        });
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );

  test(
    'semantic hash ignores prompt metadata transport fields, order, and legacy scope aliases',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'course_bundle_prompt_hash_test_',
      );
      try {
        await _withMockTempDir(tempDir.path, () async {
          final courseDir = Directory(p.join(tempDir.path, 'course'))
            ..createSync(recursive: true);
          await File(p.join(courseDir.path, 'contents.txt')).writeAsString(
            '1 Root branch\n',
            encoding: utf8,
          );
          await File(p.join(courseDir.path, '1_lecture.txt')).writeAsString(
            'Stable lecture content',
            encoding: utf8,
          );

          final service = CourseBundleService();
          final baseBundle =
              await service.createBundleFromFolder(courseDir.path);

          Future<File> buildBundleWithPromptMetadata({
            required String fileName,
            required String metadataEntryPath,
            required Map<String, dynamic> metadata,
          }) async {
            final sourceArchive = ZipDecoder().decodeBytes(
              await baseBundle.readAsBytes(),
            );
            final archive = Archive();
            for (final entry in sourceArchive.files) {
              if (!entry.isFile) {
                continue;
              }
              final normalizedName = entry.name.replaceAll('\\', '/');
              if (normalizedName == kCurrentPromptMetadataEntryPath ||
                  normalizedName == kLegacyPromptMetadataEntryPath) {
                continue;
              }
              archive.addFile(
                ArchiveFile(
                  entry.name,
                  entry.size,
                  List<int>.from(entry.content as List<int>),
                ),
              );
            }
            final metadataBytes = utf8.encode(jsonEncode(metadata));
            archive.addFile(
              ArchiveFile(
                metadataEntryPath,
                metadataBytes.length,
                metadataBytes,
              ),
            );
            final encoded = ZipEncoder().encode(archive);
            expect(encoded, isNotNull);
            final output = File(p.join(tempDir.path, fileName));
            await output.writeAsBytes(encoded!, flush: true);
            return output;
          }

          final bundleA = await buildBundleWithPromptMetadata(
            fileName: 'bundle_a.zip',
            metadataEntryPath: kCurrentPromptMetadataEntryPath,
            metadata: <String, dynamic>{
              'schema': kCurrentPromptBundleSchema,
              'remote_course_id': 111,
              'teacher_username': 'alice',
              'prompt_templates': <Map<String, dynamic>>[
                <String, dynamic>{
                  'prompt_name': 'review',
                  'scope': 'teacher',
                  'content': 'Teacher review prompt',
                  'created_at': '2024-01-01T00:00:00Z',
                },
                <String, dynamic>{
                  'prompt_name': 'learn',
                  'scope': 'student_course',
                  'student_remote_user_id': 77,
                  'student_username': 'amy',
                  'content': 'Student learn prompt',
                  'created_at': '2024-01-02T00:00:00Z',
                },
              ],
              'student_prompt_profiles': <Map<String, dynamic>>[
                <String, dynamic>{
                  'scope': 'student_course',
                  'student_remote_user_id': 77,
                  'student_username': 'amy',
                  'preferred_tone': 'calm',
                  'updated_at': '2024-01-03T00:00:00Z',
                },
              ],
              'student_pass_configs': <Map<String, dynamic>>[
                <String, dynamic>{
                  'student_remote_user_id': 77,
                  'student_username': 'amy',
                  'easy_weight': 1,
                  'medium_weight': 2,
                  'hard_weight': 3,
                  'pass_threshold': 0.7,
                  'updated_at': '2024-01-04T00:00:00Z',
                },
              ],
            },
          );

          final bundleB = await buildBundleWithPromptMetadata(
            fileName: 'bundle_b.zip',
            metadataEntryPath: kLegacyPromptMetadataEntryPath,
            metadata: <String, dynamic>{
              'schema': kLegacyPromptBundleSchema,
              'remote_course_id': 999,
              'teacher_username': 'alice_renamed',
              'prompt_templates': <Map<String, dynamic>>[
                <String, dynamic>{
                  'prompt_name': 'learn',
                  'scope': 'student',
                  'student_remote_user_id': 77,
                  'student_username': 'amy_renamed',
                  'content': 'Student learn prompt',
                  'created_at': '2025-02-02T00:00:00Z',
                },
                <String, dynamic>{
                  'prompt_name': 'review',
                  'scope': 'teacher',
                  'content': 'Teacher review prompt',
                  'created_at': '2025-02-01T00:00:00Z',
                },
              ],
              'student_prompt_profiles': <Map<String, dynamic>>[
                <String, dynamic>{
                  'scope': 'student',
                  'student_remote_user_id': 77,
                  'student_username': 'amy_renamed',
                  'preferred_tone': 'calm',
                  'updated_at': '2025-02-03T00:00:00Z',
                },
              ],
              'student_pass_configs': <Map<String, dynamic>>[
                <String, dynamic>{
                  'student_remote_user_id': 77,
                  'student_username': 'amy_renamed',
                  'easy_weight': 1.0,
                  'medium_weight': 2.0,
                  'hard_weight': 3.0,
                  'pass_threshold': 0.7,
                  'updated_at': '2025-02-04T00:00:00Z',
                },
              ],
            },
          );

          final hashA = await service.computeBundleSemanticHash(bundleA);
          final hashB = await service.computeBundleSemanticHash(bundleB);

          expect(
            hashA,
            equals(
              '6663c7def98c404b383698ca74264b9b8ad3f9182368118c0b9cc64238c25b04',
            ),
          );
          expect(hashB, equals(hashA));
        });
      } finally {
        await tempDir.delete(recursive: true);
      }
    },
  );
}
