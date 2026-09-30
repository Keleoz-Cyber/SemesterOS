import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/semester_app.dart';
import 'diagnostics/frame_probe.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installFrameProbe();
  runApp(const ProviderScope(child: SemesterApp()));
}
