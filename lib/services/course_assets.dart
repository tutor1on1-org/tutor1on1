import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class CourseAssetResolution {
  CourseAssetResolution({
    required this.contentsPath,
    required this.basePath,
    required this.assetKeys,
    required this.options,
    required this.isFileSystem,
  });

  final String? contentsPath;
  final String? basePath;
  final Set<String> assetKeys;
  final List<String> options;
  final bool isFileSystem;

  bool get hasMatch => contentsPath != null && basePath != null;

  String resolvePath(String relativePath) {
    if (basePath == null) {
      return relativePath;
    }
    if (!isFileSystem) {
      return '$basePath$relativePath';
    }
    final segments = relativePath.split('/');
    return p.join(basePath!, ...segments);
  }

  bool exists(String resolvedPath) {
    if (isFileSystem) {
      return File(resolvedPath).existsSync();
    }
    return assetKeys.contains(resolvedPath);
  }

  Future<String> loadText(String resolvedPath) async {
    if (isFileSystem) {
      return File(resolvedPath).readAsString(encoding: utf8);
    }
    return rootBundle.loadString(resolvedPath);
  }

  Future<String> loadContents() async {
    final path = contentsPath;
    if (path == null) {
      throw StateError('contents.txt path is missing.');
    }
    return loadText(path);
  }
}

class CourseAssetResolver {
  static Future<CourseAssetResolution> resolve({
    required String teacherName,
    required String courseName,
  }) async {
    final fsScan = _scanFileSystem(
      teacherName: teacherName,
      courseName: courseName,
    );
    if (fsScan.match != null) {
      return CourseAssetResolution(
        contentsPath: fsScan.match!.contentsPath,
        basePath: fsScan.match!.basePath,
        assetKeys: const {},
        options: fsScan.options,
        isFileSystem: true,
      );
    }

    Iterable<String> keys;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      keys = manifest.listAssets();
    } catch (_) {
      final manifestRaw = await rootBundle.loadString('AssetManifest.json');
      final manifest = jsonDecode(manifestRaw) as Map<String, dynamic>;
      keys = manifest.keys;
    }
    final assetKeys = keys.toSet();
    final teacherNorm = _normalizeToken(teacherName);
    final courseNorm = _normalizeToken(courseName);
    String? bestMatch;
    var bestDepth = 999;
    final options = {...fsScan.options};

    for (final asset in keys) {
      if (!asset.startsWith('assets/teachers/')) {
        continue;
      }
      if (!asset.endsWith('/contents.txt')) {
        continue;
      }
      final parts = asset.split('/');
      if (parts.length < 5) {
        continue;
      }
      final teacherPart = parts[2];
      final coursePart = parts[3];
      options.add('$teacherPart/$coursePart');
      if (_normalizeToken(teacherPart) == teacherNorm &&
          _normalizeToken(coursePart) == courseNorm) {
        final depth = parts.length;
        if (depth < bestDepth) {
          bestDepth = depth;
          bestMatch = asset;
        }
      }
    }

    final basePath = bestMatch == null
        ? null
        : bestMatch.substring(0, bestMatch.length - 'contents.txt'.length);
    final optionList = options.toList()..sort();
    return CourseAssetResolution(
      contentsPath: bestMatch,
      basePath: basePath,
      assetKeys: assetKeys,
      options: optionList,
      isFileSystem: false,
    );
  }

  static String buildMissingContentsMessage({
    required String teacherName,
    required String courseName,
    required List<String> options,
  }) {
    if (options.isEmpty) {
      return 'No contents.txt assets found. Expected assets/teachers/$teacherName/$courseName/contents.txt.';
    }
    final available = options.join(', ');
    return 'No contents.txt asset found for $teacherName/$courseName. Available: $available';
  }

  static String _normalizeToken(String value) {
    return value.toLowerCase().replaceAll(' ', '');
  }

  static _FileSystemScan _scanFileSystem({
    required String teacherName,
    required String courseName,
  }) {
    final options = <String>{};
    final teacherNorm = _normalizeToken(teacherName);
    final courseNorm = _normalizeToken(courseName);

    _FileSystemMatch? match;
    for (final root in _candidateRoots()) {
      final teachersRoot = p.join(root, 'assets', 'teachers');
      final teachersDir = Directory(teachersRoot);
      if (!teachersDir.existsSync()) {
        continue;
      }
      final teacherDirs =
          teachersDir.listSync(followLinks: false).whereType<Directory>();
      for (final teacherDir in teacherDirs) {
        final teacherPart = p.basename(teacherDir.path);
        final courseDirs =
            teacherDir.listSync(followLinks: false).whereType<Directory>();
        for (final courseDir in courseDirs) {
          final coursePart = p.basename(courseDir.path);
          final contentsPath = p.join(courseDir.path, 'contents.txt');
          if (File(contentsPath).existsSync()) {
            options.add('$teacherPart/$coursePart');
          }
          if (match == null &&
              _normalizeToken(teacherPart) == teacherNorm &&
              _normalizeToken(coursePart) == courseNorm &&
              File(contentsPath).existsSync()) {
            match = _FileSystemMatch(
              contentsPath: contentsPath,
              basePath: courseDir.path,
            );
          }
        }
      }
      if (match != null) {
        break;
      }
    }

    final optionList = options.toList()..sort();
    return _FileSystemScan(match: match, options: optionList);
  }

  static Iterable<String> _candidateRoots() sync* {
    yield Directory.current.path;
    final appRoot = p.join(Directory.current.path, 'app');
    if (appRoot != Directory.current.path) {
      yield appRoot;
    }
  }
}

class _FileSystemScan {
  _FileSystemScan({
    required this.match,
    required this.options,
  });

  final _FileSystemMatch? match;
  final List<String> options;
}

class _FileSystemMatch {
  _FileSystemMatch({
    required this.contentsPath,
    required this.basePath,
  });

  final String contentsPath;
  final String basePath;
}
