import 'dart:async';
import 'dart:io';

import 'package:firedart/firedart.dart';

import 'firestore_setup.dart';
import 'realtime_example.dart';

Future<void> main(List<String> args) async {
  stdout.writeln('⚙️  Initializing Firestore consumer...');
  final firestore = await initializeFirestore();
  final callsCollection = firestore.collection('demoCalls');

  final display = RealtimeStatusDisplay(collection: callsCollection);

  stdout.writeln('📡 Consumer running. Press Ctrl+C to quit.');

  final completer = Completer<void>();

  void shutdown() {
    if (completer.isCompleted) return;
    stdout.writeln('\n👋 Shutting down consumer.');
    display.dispose();
    Firestore.instance.close();
    completer.complete();
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  ProcessSignal.sigterm.watch().listen((_) => shutdown());

  await completer.future;
}
