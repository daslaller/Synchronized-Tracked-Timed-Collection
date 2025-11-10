import 'dart:convert';
import 'dart:io';

import 'package:firedart/firedart.dart';
import 'package:firedart/firestore/token_authenticator.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

const _defaultServiceAccountPath =
    'lib/Secrets/synchronizedtrackedtimeset-firebase-adminsdk-fbsvc-67f45a8798.json';

ServiceAccountAuthenticator? _globalServiceAccountAuthenticator;

/// Initializes Firestore for CLI usage.
///
/// The default flow favours service-account based authentication using the JSON
/// that lives under `lib/Secrets/`. Override [serviceAccountPath] if you store
/// the credential elsewhere, or set [useApplicationDefaultAuth] to false if you
/// prefer the Firebase web API key sign-in path.
Future<Firestore> initializeFirestore({
  bool useApplicationDefaultAuth = true,
  String? projectIdOverride,
  String? apiKeyOverride,
  String? serviceAccountPath,
  List<String>? serviceAccountScopes,
}) async {
  if (useApplicationDefaultAuth) {
    return initializeFirestoreFromServiceAccountFile(
      projectId: projectIdOverride,
      serviceAccountPath: serviceAccountPath,
      scopes: serviceAccountScopes,
    );
  } else {
    final projectId = _resolveProjectId(projectIdOverride);
    final apiKey =
        apiKeyOverride ?? Platform.environment['FIREBASE_WEB_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError(
        'FIREBASE_WEB_API_KEY is not set. Export it or pass apiKeyOverride '
        'when calling initializeFirestore.',
      );
    }
    return initializeFirestoreWithApiKey(projectId: projectId, apiKey: apiKey);
  }
}

Future<Firestore> initializeFirestoreFromServiceAccountFile({
  String? projectId,
  String? serviceAccountPath,
  List<String>? scopes,
}) async {
  final resolvedPath = await _resolveServiceAccountPath(serviceAccountPath);
  final account = await _readServiceAccount(resolvedPath);
  final resolvedProjectId = _resolveProjectId(
    projectId,
    fallback: account.projectId,
  );

  await _globalServiceAccountAuthenticator?.close();
  _globalServiceAccountAuthenticator = ServiceAccountAuthenticator(
    account.credentials,
    scopes: scopes,
  );

  return Firestore(
    resolvedProjectId,
    authenticator: _globalServiceAccountAuthenticator!.authenticate,
  );
}

Future<Firestore> initializeFirestoreWithApiKey({
  required String projectId,
  required String apiKey,
}) async {
  if (!FirebaseAuth.initialized) {
    FirebaseAuth.initialize(apiKey, VolatileStore());
  }

  final auth = FirebaseAuth.instance;
  final tokenAuthenticator = TokenAuthenticator.from(auth);
  return Firestore(projectId, authenticator: tokenAuthenticator?.authenticate);
}

Future<void> shutdownFirestore(Firestore firestore) async {
  await Future.sync(firestore.close);
  await _globalServiceAccountAuthenticator?.close();
  _globalServiceAccountAuthenticator = null;
}

Future<String> _resolveServiceAccountPath(String? override) async {
  final envPath = Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'];
  final candidatePaths = [
    override,
    envPath,
    _defaultServiceAccountPath,
  ].whereType<String>();

  for (final path in candidatePaths) {
    final file = File(path);
    if (await file.exists()) {
      return file.path;
    }
  }

  throw StateError(
    'No service-account credential found. Provide serviceAccountPath, set '
    'GOOGLE_APPLICATION_CREDENTIALS, or place the file at '
    '$_defaultServiceAccountPath.',
  );
}

Future<({ServiceAccountCredentials credentials, String? projectId})>
_readServiceAccount(String path) async {
  final file = File(path);
  final raw = await file.readAsString();
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return (
    credentials: ServiceAccountCredentials.fromJson(json),
    projectId: json['project_id'] as String?,
  );
}

String _resolveProjectId(String? override, {String? fallback}) {
  final envProjectId = Platform.environment['FIREBASE_PROJECT_ID'];
  final candidate = override ?? fallback ?? envProjectId;
  if (candidate == null || candidate.isEmpty) {
    throw StateError(
      'Missing Firebase project id. Provide projectId, set FIREBASE_PROJECT_ID, '
      'or ensure the service-account JSON contains "project_id".',
    );
  }
  return candidate;
}

class ServiceAccountAuthenticator {
  ServiceAccountAuthenticator(
    ServiceAccountCredentials credentials, {
    List<String>? scopes,
  }) : _credentials = credentials,
       _scopes = scopes ?? const ['https://www.googleapis.com/auth/datastore'],
       _client = http.Client();

  final ServiceAccountCredentials _credentials;
  final List<String> _scopes;
  final http.Client _client;
  AccessCredentials? _cachedCredentials;

  Future<void> authenticate(Map<String, String> metadata, String uri) async {
    final access = await _obtainAccessCredentials();
    metadata['authorization'] = 'Bearer ${access.accessToken.data}';
  }

  Future<void> close() async {
    _cachedCredentials = null;
    _client.close();
  }

  Future<AccessCredentials> _obtainAccessCredentials() async {
    final current = _cachedCredentials;
    final now = DateTime.now();
    if (current != null) {
      final expiry = current.accessToken.expiry;
      if (expiry.isAfter(now.add(const Duration(minutes: 1)))) {
        return current;
      }
    }

    _cachedCredentials = await obtainAccessCredentialsViaServiceAccount(
      _credentials,
      _scopes,
      _client,
    );
    return _cachedCredentials!;
  }
}
