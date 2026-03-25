class PromptRenderer {
  String render(String template, Map<String, Object?> values) {
    var output = template;
    values.forEach((key, value) {
      final replacement = value?.toString() ?? '';
      output = output.replaceAll(RegExp('{{\\s*$key\\s*}}'), replacement);
    });
    return output;
  }
}
