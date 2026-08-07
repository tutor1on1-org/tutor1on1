class FileSystemDataMissingException implements Exception {
  const FileSystemDataMissingException(this.path);

  final String path;

  @override
  String toString() => 'File data is missing: $path';
}
