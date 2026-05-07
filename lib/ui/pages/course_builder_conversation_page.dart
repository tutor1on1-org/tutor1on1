import 'package:flutter/material.dart';

import '../../db/app_database.dart';
import '../app_close_button.dart';
import '../widgets/teacher_course_builder_panel.dart';

class CourseBuilderConversationPage extends StatelessWidget {
  const CourseBuilderConversationPage({
    super.key,
    required this.courseVersion,
    required this.kpKey,
    required this.kpTitle,
  });

  final CourseVersion courseVersion;
  final String kpKey;
  final String kpTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$kpKey $kpTitle'),
        actions: buildAppBarActionsWithClose(context),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final height = (constraints.maxHeight - 240).clamp(220.0, 640.0);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: TeacherCourseBuilderPanel(
              courseVersion: courseVersion,
              kpKey: kpKey,
              kpTitle: kpTitle,
              messageHeight: height,
            ),
          );
        },
      ),
    );
  }
}
