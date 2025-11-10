import 'dart:async';
import 'dart:io';

import 'package:firedart/firedart.dart';

import 'firestore_setup.dart';
import 'realtime_example.dart';

final bool _isWindows = Platform.isWindows;

Future<void> main(List<String> args) async {
  stdout.writeln('⚙️  Initializing Firestore consumer...');
  final Firestore firestore = await initializeFirestoreFromServiceAccountFile();
  final callsCollection = firestore.collection('demoCalls');

  final display = RealtimeStatusDisplay(collection: callsCollection);

  stdout.writeln('📡 Consumer running. Press Ctrl+C to quit.');

  final completer = Completer<void>();
  var isShuttingDown = false;

  Future<void> shutdown() async {
    if (isShuttingDown || completer.isCompleted) return;
    isShuttingDown = true;
    stdout.writeln('\n👋 Shutting down consumer.');
    display.dispose();
    await shutdownFirestore(firestore);
    completer.complete();
  }

  ProcessSignal.sigint.watch().listen((_) {
    unawaited(shutdown());
  });

  if (!_isWindows) {
    ProcessSignal.sigterm.watch().listen((_) {
      unawaited(shutdown());
    });
  } else {
    stdout.writeln('ℹ️ SIGTERM handling not supported on Windows. Use Ctrl+C.');
  }

  await completer.future;
}
