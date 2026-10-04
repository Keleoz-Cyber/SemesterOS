import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory(
    Platform.environment['NOTICE_UI_OUTPUT'] ??
        '../../output/verification/20260930-device',
  )..createSync(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) return false;
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return bytes.isNotEmpty;
    },
    responseDataCallback: (data) async {
      final evidence = {...?data}..remove('screenshots');
      await writeResponseData(
        evidence,
        testOutputFilename: 'notice-ui-results',
        destinationDirectory: directory.path,
      );
    },
    writeResponseOnFailure: true,
  );
}
