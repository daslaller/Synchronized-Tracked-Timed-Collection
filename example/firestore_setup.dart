import 'dart:io';

import 'package:firedart/firedart.dart';

/// Initializes Firestore for CLI usage.
///
/// By default the initializer attempts to use Google Application Default
/// Credentials (ADC). Set the `GOOGLE_APPLICATION_CREDENTIALS` environment
/// variable to point at a service account JSON export and provide
/// `FIREBASE_PROJECT_ID` with your Firebase project id.
///
/// When [useApplicationDefaultAuth] is false, the initializer expects
/// `FIREBASE_WEB_API_KEY` to be available so it can bootstrap `FirebaseAuth`
/// with an API key and in-memory token store.
Future<Firestore> initializeFirestore({
  bool useApplicationDefaultAuth = true,
  String? projectIdOverride,
  String? apiKeyOverride,
}) async {
  final projectId =
      projectIdOverride ?? Platform.environment['FIREBASE_PROJECT_ID'];
  if (projectId == null || projectId.isEmpty) {
    throw StateError(
      'Missing Firebase project id. Set FIREBASE_PROJECT_ID or provide '
      'projectIdOverride.',
    );
  }

  if (useApplicationDefaultAuth) {
    final credentialsPath =
        Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'];
    if (credentialsPath == null || credentialsPath.isEmpty) {
      throw StateError(
        'GOOGLE_APPLICATION_CREDENTIALS is not set. Export it with the path '
        'to a service account JSON file downloaded from Firebase console.',
      );
    }

    if (!Firestore.initialized) {
      Firestore.initialize(projectId, useApplicationDefaultAuth: true);
    }
  } else {
    final apiKey =
        apiKeyOverride ?? Platform.environment['FIREBASE_WEB_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError(
        'FIREBASE_WEB_API_KEY is not set. Export it or pass apiKeyOverride '
        'when calling initializeFirestore.',
      );
    }

    if (!FirebaseAuth.initialized) {
      FirebaseAuth.initialize(apiKey, VolatileStore());
    }
    if (!Firestore.initialized) {
      Firestore.initialize(projectId);
    }
  }

  return Firestore.instance;
}
