import 'dart:async';
import 'dart:io';

import 'package:firedart/firedart.dart';
import 'package:synchronized_tracked_time_list/synchronized_tracked_time_list.dart';

import 'call_model.dart';
import 'firestore_setup.dart';

Future<void> main(List<String> args) async {
  stdout.writeln('⚙️  Initializing Firestore emitter...');
  final firestore = await initializeFirestore();
  final callsCollection = firestore.collection('demoCalls');

  final timedSet = SynchronizedTimedSet<Call>(
    cleanupInterval: const Duration(milliseconds: 250),
    identityProvider: (call) => call.uniqueIdentfier,
  );

  final syncService = FirebaseSyncService<Call>(
    timedSet: timedSet,
    collection: FirestoreCollectionWriter(
      setDocument: (docId, payload) =>
          callsCollection.document(docId).set(payload),
      updateDocument: (docId, payload) =>
          callsCollection.document(docId).update(payload),
    ),
    idProvider: (call) => call.uniqueIdentfier,
    serializer: (call) => call.toJson(),
  );

  final call = Call(
    callerID: '+46 8 555 0101',
    direction: TelavoxDirection.incoming,
    status: TelavoxLineStatus.ringing,
  )..tags = ['vip'];

  stdout.writeln('➕ Adding inbound call ${call.uniqueIdentfier}');
  timedSet.synchronizeSet([call], const Duration(minutes: 5));

  await Future<void>.delayed(const Duration(seconds: 5));

  final connectedCall = Call(
    callerID: call.callerID,
    direction: call.direction,
    status: TelavoxLineStatus.connected,
  )..tags = [...call.tags, 'operator:anna'];

  stdout.writeln('🔄 Updating call to connected state');
  timedSet.synchronizeSet([connectedCall], const Duration(minutes: 4));

  await Future<void>.delayed(const Duration(seconds: 5));

  stdout.writeln('❌ Call completed, marking as ended');
  timedSet.synchronize({});

  await Future<void>.delayed(const Duration(seconds: 2));

  stdout.writeln('🧹 Cleaning up emitter resources');
  syncService.dispose();
  timedSet.dispose();
  Firestore.instance.close();
}
