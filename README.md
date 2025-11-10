Synchronized timed collections for keeping transient datasets in sync with
Firebase Firestore from a pure Dart environment. The included example models
call data, but the library is agnostic to the domain.

- `SynchronizedTimedSet<T>` keeps an in-memory view of time-bound entries.
- `FirebaseSyncService<T>` mirrors the set into Firestore via
  [`firedart`](https://pub.dev/packages/firedart) (no Flutter runtime needed).

## Getting started

1. Enable Firestore in your Firebase project.
2. Download a service-account JSON file and export environment variables so the
   CLI scripts can authenticate using Google Application Default Credentials
   (ADC):

   ```powershell
   $env:GOOGLE_APPLICATION_CREDENTIALS="D:\path\to\service-account.json"
   $env:FIREBASE_PROJECT_ID="synchronizedtrackedtimeset"
   ```

   Replace the values with your actual paths/project id. On macOS/Linux use
   `export` instead of `$env:`.

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
- Hooks the set into Firestore through `FirebaseSyncService`.
- Simulates an inbound call being created, updated, and completed.

### 3. Observe the data

Open the [Firestore console](https://console.firebase.google.com/project/synchronizedtrackedtimeset/firestore/databases/-default-/data)
and inspect the `demoCalls` collection to watch the documents change in real
time.

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
