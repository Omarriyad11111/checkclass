import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/student/join_screen.dart';
import '../../features/student/vote_screen.dart';
import '../../features/teacher/teacher_session_screen.dart';

abstract class Routes {
  static const home = '/';
  static const join = '/join';
  static String teacherSession(String code) => '/teacher/session/$code';
  static String vote(String code) => '/vote/$code';
}

final GoRouter appRouter = GoRouter(
  initialLocation: Routes.home,
  routes: [
    GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
    GoRoute(
      path: '/teacher/session/:code',
      builder: (_, s) => TeacherSessionScreen(code: s.pathParameters['code']!),
    ),
    GoRoute(path: Routes.join, builder: (_, _) => const JoinScreen()),
    GoRoute(
      path: '/vote/:code',
      builder: (_, s) => VoteScreen(code: s.pathParameters['code']!),
    ),
  ],
);
