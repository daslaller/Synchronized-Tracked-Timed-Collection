import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firedart/firedart.dart';
import 'package:synchronized_tracked_time_list/synchronized_tracked_time_list.dart';

import 'call_model.dart';
import 'firestore_setup.dart';

Future<void> main(List<String> args) async {
  final config = _EmitterConfig.fromArgs(args);
  stdout.writeln(
    '⚙️  Initializing Firestore emitter (duration: ${config.duration.inSeconds}s)...',
  );

  final Firestore firestore = await initializeFirestoreFromServiceAccountFile();
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

  final random = Random();
  final activeCalls = <String, _SimulatedCall>{};
  final simulationDeadline = DateTime.now().add(config.duration);

  await _runSimulationLoop(
    config: config,
    timedSet: timedSet,
    random: random,
    activeCalls: activeCalls,
    deadline: simulationDeadline,
  );

  stdout.writeln('❌ Simulation complete. Clearing remaining calls.');
  timedSet.synchronize({});

  stdout.writeln('🧹 Cleaning up emitter resources');
  syncService.dispose();
  timedSet.dispose();
  await shutdownFirestore(firestore);
}

Future<void> _runSimulationLoop({
  required _EmitterConfig config,
  required SynchronizedTimedSet<Call> timedSet,
  required Random random,
  required Map<String, _SimulatedCall> activeCalls,
  required DateTime deadline,
}) async {
  while (DateTime.now().isBefore(deadline) || activeCalls.isNotEmpty) {
    final now = DateTime.now();
    if (now.isBefore(deadline)) {
      await _simulateNextStep(
        config: config,
        timedSet: timedSet,
        random: random,
        activeCalls: activeCalls,
      );
    } else {
      if (activeCalls.isNotEmpty) {
        final key = activeCalls.keys.first;
        stdout.writeln('🧺 Draining call $key');
        activeCalls.remove(key);
        _pushState(timedSet, activeCalls.values);
      }
    }

    final wait = config.randomInterval(random);
    await Future<void>.delayed(wait);
  }
}

Future<void> _simulateNextStep({
  required _EmitterConfig config,
  required SynchronizedTimedSet<Call> timedSet,
  required Random random,
  required Map<String, _SimulatedCall> activeCalls,
}) async {
  final canAddMore =
      activeCalls.length < config.maxConcurrentCalls || activeCalls.isEmpty;
  final actionRoll = random.nextDouble();

  if (canAddMore && (activeCalls.isEmpty || actionRoll < 0.5)) {
    final call = _SimulatedCall.create(random);
    activeCalls[call.callerId] = call;
    stdout.writeln('➕ Adding call ${call.callerId} (${call.status.label})');
  } else if (activeCalls.isNotEmpty && actionRoll < 0.8) {
    final call = _pickRandom(activeCalls.values, random);
    call.promote(random);
    stdout.writeln('🔄 Updating call ${call.callerId} -> ${call.status.label}');
  } else if (activeCalls.isNotEmpty) {
    final call = _pickRandom(activeCalls.values, random);
    stdout.writeln('📴 Ending call ${call.callerId}');
    activeCalls.remove(call.callerId);
  }

  _pushState(timedSet, activeCalls.values);
}

void _pushState(
  SynchronizedTimedSet<Call> timedSet,
  Iterable<_SimulatedCall> calls,
) {
  final payload = <Call, Duration>{};
  for (final simCall in calls) {
    payload[simCall.snapshot()] = simCall.maxLifetime;
  }
  timedSet.synchronize(payload);
}

T _pickRandom<T>(Iterable<T> items, Random random) {
  final list = items.toList();
  return list[random.nextInt(list.length)];
}

class _EmitterConfig {
  _EmitterConfig({
    required this.duration,
    this.maxConcurrentCalls = 6,
    this.minEventInterval = const Duration(seconds: 1),
    this.maxEventInterval = const Duration(seconds: 4),
  }) : assert(!minEventInterval.isNegative),
       assert(!maxEventInterval.isNegative),
       assert(!duration.isNegative),
       assert(maxEventInterval >= minEventInterval);

  final Duration duration;
  final int maxConcurrentCalls;
  final Duration minEventInterval;
  final Duration maxEventInterval;

  Duration randomInterval(Random random) {
    final delta = maxEventInterval - minEventInterval;
    if (delta.inMilliseconds == 0) return minEventInterval;
    final jitterMs = random.nextInt(delta.inMilliseconds + 1);
    return minEventInterval + Duration(milliseconds: jitterMs);
  }

  static _EmitterConfig fromArgs(List<String> args) {
    Duration? duration;
    int? maxConcurrent;
    Duration? minInterval;
    Duration? maxInterval;

    for (final arg in args) {
      if (arg.startsWith('--duration=')) {
        duration = _parseSeconds(arg.split('=').last);
      } else if (arg.startsWith('--duration-seconds=')) {
        duration = _parseSeconds(arg.split('=').last);
      } else if (arg.startsWith('--max-concurrent=')) {
        maxConcurrent = int.tryParse(arg.split('=').last);
      } else if (arg.startsWith('--min-interval-ms=')) {
        minInterval = _parseMilliseconds(arg.split('=').last);
      } else if (arg.startsWith('--max-interval-ms=')) {
        maxInterval = _parseMilliseconds(arg.split('=').last);
      }
    }

    duration ??= _readDurationFromEnv() ?? const Duration(seconds: 60);
    maxConcurrent ??= _readIntEnv('EMITTER_MAX_CONCURRENT')?.clamp(1, 50) ?? 6;
    minInterval ??=
        _parseMilliseconds(Platform.environment['EMITTER_MIN_INTERVAL_MS']) ??
        const Duration(milliseconds: 800);
    maxInterval ??=
        _parseMilliseconds(Platform.environment['EMITTER_MAX_INTERVAL_MS']) ??
        const Duration(milliseconds: 2500);

    if (maxInterval < minInterval) {
      stderr.writeln(
        '⚠️  max interval smaller than min interval. Using min interval for both.',
      );
      maxInterval = minInterval;
    }

    return _EmitterConfig(
      duration: duration,
      maxConcurrentCalls: maxConcurrent,
      minEventInterval: minInterval,
      maxEventInterval: maxInterval,
    );
  }
}

class _SimulatedCall {
  _SimulatedCall({
    required this.callerId,
    required this.direction,
    required this.status,
    required this.maxLifetime,
    List<String>? tags,
  }) : tags = tags ?? <String>[];

  final String callerId;
  TelavoxDirection direction;
  TelavoxLineStatus status;
  final Duration maxLifetime;
  final List<String> tags;

  Call snapshot() =>
      Call(callerID: callerId, direction: direction, status: status)
        ..tags = List<String>.from(tags);

  void promote(Random random) {
    switch (status) {
      case TelavoxLineStatus.ringing:
        status = TelavoxLineStatus.connected;
        tags.add('agent:${_randomAgent(random)}');
        break;
      case TelavoxLineStatus.connected:
        status = TelavoxLineStatus.disconnected;
        break;
      case TelavoxLineStatus.disconnected:
        status = TelavoxLineStatus.connected;
        break;
    }
  }

  static _SimulatedCall create(Random random) {
    final callerId = _randomPhoneNumber(random);
    final direction = random.nextBool()
        ? TelavoxDirection.incoming
        : TelavoxDirection.outgoing;
    final status = TelavoxLineStatus.ringing;
    final lifetimeSeconds = random.nextInt(120) + 60;
    final lifetime = Duration(seconds: lifetimeSeconds);
    final tags = <String>['queue:${_randomQueue(random)}'];

    return _SimulatedCall(
      callerId: callerId,
      direction: direction,
      status: status,
      maxLifetime: lifetime,
      tags: tags,
    );
  }
}

Duration? _parseSeconds(String? value) {
  final seconds = double.tryParse(value ?? '');
  if (seconds == null || seconds.isNaN || seconds.isInfinite) return null;
  return Duration(milliseconds: (seconds * 1000).round());
}

Duration? _parseMilliseconds(String? value) {
  final milliseconds = double.tryParse(value ?? '');
  if (milliseconds == null || milliseconds.isNaN || milliseconds.isInfinite) {
    return null;
  }
  return Duration(milliseconds: milliseconds.round());
}

Duration? _readDurationFromEnv() =>
    _parseSeconds(Platform.environment['EMITTER_DURATION_SECONDS']);

int? _readIntEnv(String key) => int.tryParse(Platform.environment[key] ?? '');

String _randomPhoneNumber(Random random) {
  final buffer = StringBuffer('+46 ');
  buffer.write(random.nextInt(9) + 1);
  buffer.write(' ');
  for (var i = 0; i < 7; i++) {
    if (i == 3) buffer.write(' ');
    buffer.write(random.nextInt(10));
  }
  return buffer.toString();
}

String _randomQueue(Random random) {
  const queues = ['sales', 'support', 'vip', 'billing'];
  return queues[random.nextInt(queues.length)];
}

String _randomAgent(Random random) {
  const agents = ['alex', 'sam', 'jamie', 'lee', 'nova'];
  return agents[random.nextInt(agents.length)];
}
