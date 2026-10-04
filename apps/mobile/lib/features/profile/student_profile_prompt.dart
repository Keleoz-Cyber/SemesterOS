import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import 'profile_scope.dart';

/// Optional first-use guidance stays within the student's current page.
class StudentProfilePrompt extends StatelessWidget {
  const StudentProfilePrompt({super.key});
  @override
  Widget build(BuildContext context) {
    final profile = ProfileScope.maybeOf(context);
    if (profile == null || !profile.needsOnboarding) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '学生资料',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            '用于判断通知对象，选填。',
            style: TextStyle(
              color: CampusColors.muted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              AppTextButton(
                key: const Key('student-profile-setup'),
                onPressed: () {
                  profile.claimGuide();
                  context.push('/profile/setup');
                },
                child: const Text('完善学生资料'),
              ),
              AppTextButton(
                key: const Key('student-profile-later'),
                onPressed: () => unawaited(profile.dismissGuide()),
                child: const Text('稍后填写'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
