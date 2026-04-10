import 'package:flutter/material.dart';

ThemeData buildTutor1on1Theme() {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.teal,
    fontFamily: 'Microsoft YaHei UI',
    fontFamilyFallback: const [
      'Microsoft YaHei',
      'Noto Sans CJK SC',
      'Source Han Sans SC',
      'PingFang SC',
      'SimHei',
    ],
  );
}
