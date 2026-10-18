// Pumps the Projects screen against a [FakeProjectsApi], inside a router that
// has the pages the screens navigate to.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:senclaw_desktop/core/transport/connection.dart';
import 'package:senclaw_desktop/features/projects/projects_provider.dart';
import 'package:senclaw_desktop/features/projects/projects_screen.dart';
import 'package:senclaw_desktop/theme/app_theme.dart';

import 'fake_projects_api.dart';

class ProjectsHarness {
  ProjectsHarness(this.api, this.container, this.router);
  final FakeProjectsApi api;
  final ProviderContainer container;
  final GoRouter router;

  /// Where the router is now, for "tapping it went to the kanban page".
  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

/// [picked] is what the system folder chooser answers; [open] opens that
/// project's page straight away.
Future<ProjectsHarness> pumpProjects(
  WidgetTester tester, {
  FakeProjectsApi? api,
  String? picked,
  String? open,
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = api ?? FakeProjectsApi();
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(fake),
    folderPickerProvider.overrideWithValue((_) async => picked),
  ]);
  addTearDown(container.dispose);
  if (open != null) container.read(openProjectProvider.notifier).state = open;
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: ProjectsScreen())),
    GoRoute(path: '/kanban', builder: (_, _) => const Text('kanban page')),
    GoRoute(path: '/chat', builder: (_, _) => const Text('chat page')),
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return ProjectsHarness(fake, container, router);
}
