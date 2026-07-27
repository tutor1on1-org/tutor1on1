import 'package:flutter/material.dart';

import 'skill_tree_page.dart';

class CourseEditorPage extends StatelessWidget {
  const CourseEditorPage({
    super.key,
    required this.courseVersionId,
  });

  final int courseVersionId;

  @override
  Widget build(BuildContext context) {
    return SkillTreePage(
      courseVersionId: courseVersionId,
      isTeacherView: false,
      titleOverride: 'Course Editor',
      enableSessionNavigation: false,
      enableCourseEditorActions: true,
      allowTextbookOnly: true,
    );
  }
}
