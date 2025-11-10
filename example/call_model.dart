// ignore_for_file: file_names

import 'dart:convert';
import 'package:crypto/crypto.dart';

enum TelavoxLineStatus {
  connected('up'),
  disconnected('down'),
  ringing('ringing');

  final String label;
  const TelavoxLineStatus(this.label);
  static TelavoxLineStatus fromString(String direction) =>
      values.firstWhere((value) => direction.endsWith(value.label));
}

enum TelavoxDirection {
  incoming('in'),
  outgoing('out'),
  unknown('unknown');

  final String label;
  const TelavoxDirection(this.label);
  static TelavoxDirection fromString(String direction) =>
      values.firstWhere((value) => direction.endsWith(value.label));
}

class Call {
  String callerID;
  final String uniqueIdentfier;
  TelavoxDirection direction;
  TelavoxLineStatus status;
  List<String> tags = [];
  Call({required this.callerID, required this.direction, required this.status})
    : uniqueIdentfier = md5.convert(utf8.encode(callerID)).toString();

  factory Call.fromJSONcallData(data) {
    return Call(
      callerID: data['callerID'],
      direction: TelavoxDirection.fromString(data['direction']),
      status: TelavoxLineStatus.fromString(data['status']),
    );
  }

  /// Converts the Call object to a Map for Firestore.
  Map<String, dynamic> toJson() {
    return {
      'callerID': callerID,
      'uniqueIdentfier': uniqueIdentfier,
      'direction': direction.label,
      'status': status.label,
      'tags': tags,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Call &&
        other.callerID == callerID &&
        other.uniqueIdentfier == uniqueIdentfier &&
        other.direction == direction &&
        other.status == status &&
        _listEquals(other.tags, tags);
  }

  bool _listEquals(List a, List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(callerID, uniqueIdentfier, direction, status, tags);

  @override
  String toString() =>
      'Call(id: $uniqueIdentfier, caller: $callerID, status: ${status.label})';
}
