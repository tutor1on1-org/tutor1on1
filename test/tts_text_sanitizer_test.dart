import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/services/tts_text_sanitizer.dart';

void main() {
  group('TtsTextSanitizer', () {
    final sanitizer = TtsTextSanitizer();

    test('bold punctuation is preserved without \$1 artifacts', () {
      const input =
          '**Practice Q2 (answer in one line using inequality notation):**'
          'A mass is rounded to **7.4 kg** to the **nearest 0.1 kg**. '
          'Write the **lower and upper bounds** for the true mass \\(m\\). '
          '(Use: lower <= m < upper.)';
      final output = sanitizer.sanitizeForTts(input);
      expect(output, contains('Practice Q2'));
      expect(output, contains('7.4 kg'));
      expect(output, contains('nearest 0.1 kg'));
      expect(output, contains('lower and upper bounds'));
      expect(RegExp(r'\$1(?!\d)').hasMatch(output), isFalse);
    });

    test('unbalanced dollars do not corrupt content', () {
      const input = 'Price is \$10 and equation \$x+1\$ and open \$x+2';
      final output = sanitizer.sanitizeForTts(input);
      expect(output, contains('\$10'));
      expect(output, contains('x+1'));
      expect(RegExp(r'\$1(?!\d)').hasMatch(output), isFalse);
    });

    test('escaped dollars and currency are preserved', () {
      const input = 'Ticket costs \\\$5 and tax is \$10. Equation: \$x+2\$.';
      final output = sanitizer.sanitizeForTts(input);
      expect(output, contains('\$5'));
      expect(output, contains('\$10'));
      expect(output, contains('x+2'));
    });

    test('code spans and blocks ignore math delimiters', () {
      const input = 'Use `\$x\$` and ```\n\\(y+1\\)\n``` outside \$z+1\$.';
      final output = sanitizer.sanitizeForTts(input);
      expect(output, contains('\$x\$'));
      expect(output, contains(r'\(y+1\)'));
      expect(output, contains('z+1'));
    });

    test('multiple math segments with nested braces', () {
      const input =
          'Compute \$\\frac{1}{2}\$ and \\(\\sqrt{1+\\frac{a}{b}}\\).';
      final output = sanitizer.sanitizeForTts(input);
      expect(output, contains('1 over 2'));
      expect(output, contains('square root of'));
      expect(output, contains('a over b'));
    });
  });
}
