Synchronized timed collections for keeping transient datasets in sync with
Firebase Firestore from a pure Dart environment. The included example models
call data, but the library is agnostic to the domain.

- `SynchronizedTimedSet<T>` keeps an in-memory view of time-bound entries.
- `FirebaseSyncService<T>` mirrors the set into Firestore via
  [`firedart`](https://pub.dev/packages/firedart) (no Flutter runtime needed).

## Getting started

1. Enable Firestore in your Firebase project.
2. Place your service-account JSON file at
   `lib/Secrets/synchronizedtrackedtimeset-firebase-adminsdk-fbsvc-67f45a8798.json`
   (or pass a custom path to `initializeFirestoreFromServiceAccountFile`). Set
   the project id for the scripts by exporting `FIREBASE_PROJECT_ID`. The helper
   will also read `project_id` from the JSON file if present:

   ```powershell
   $env:FIREBASE_PROJECT_ID="synchronizedtrackedtimeset"
   ```

   On macOS/Linux use `export` instead of `$env:`.

3. Install dependencies: `dart pub get`.

## Usage

The `example/` folder contains a fully wired emitter/consumer pair.

### 1. Start the consumer

Run this in the first terminal to tail real-time updates:

```bash
dart run example/call_consumer.dart
```

### 2. Drive the emitter

Run the emitter in a second terminal (with the same environment variables):

```bash
dart run example/call_emitter.dart
```

The emitter script:

- Instantiates `SynchronizedTimedSet<Call>` with a custom identity provider so
  each call keeps the same Firestore document id.
- Hooks the set into Firestore through `FirebaseSyncService` and
  `initializeFirestoreFromServiceAccountFile`.
- Streams randomised call traffic for a configurable duration, cycling through
  add/update/remove events while generating realistic phone numbers and tags.

Tweak the behaviour via CLI flags or environment variables, for example:

```bash
dart run example/call_emitter.dart --duration=180 --max-concurrent=10
```

Supported knobs:

- `--duration` / `--duration-seconds` or `EMITTER_DURATION_SECONDS`
- `--max-concurrent` / `EMITTER_MAX_CONCURRENT`
- `--min-interval-ms`, `--max-interval-ms`, or the matching env variables

### 3. Observe the data

Open the [Firestore console](https://console.firebase.google.com/project/synchronizedtrackedtimeset/firestore/databases/-default-/data)
and inspect the `demoCalls` collection to watch the documents change in real
time. Each document includes sync metadata:

- `syncStatus`: `"active"` while the item is present in the timed set, `"removed"`
  when it was explicitly dropped (e.g. call ended), `"expired"` when the lifetime
  elapsed.
- `addedAt`, `expiresAt`, `lastModifiedAt`, `endedAt`: timestamps captured by the
  sync service for auditing and reconciliation.

## Custom identity helpers

Provide `identityProvider` when creating the timed set to define how incoming
items should be matched against existing entries:

```dart
final timedSet = SynchronizedTimedSet<Call>(
  identityProvider: (call) => call.uniqueIdentfier,
);
```

## Authentication options

- The init helper in `example/firestore_setup.dart` defaults to ADC. Ensure
  `GOOGLE_APPLICATION_CREDENTIALS` points to a service-account JSON file.
- To test with a web API key instead, call `initializeFirestore` with
  `useApplicationDefaultAuth: false` and export `FIREBASE_WEB_API_KEY`.
