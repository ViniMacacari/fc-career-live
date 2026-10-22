import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

abstract final class BackgroundData {
  static Future<void> _tail = Zone.root.run(() => Future<void>.value());
  static int _pending = 0;
  @visibleForTesting
  static int get pendingJobs => _pending;

  static Future<R> run<Q, R>(
    ComputeCallback<Q, R> callback,
    Q message, {
    required String label,
    bool background = true,
  }) async {
    if (!background) return callback(message);
    final previous = _tail;
    final released = Zone.root.run(() => Completer<void>());
    _tail = released.future;
    _pending++;
    await previous;
    try {
      return await compute(callback, message, debugLabel: label);
    } finally {
      _pending--;
      released.complete();
    }
  }

  static Future<Object?> jsonBytes(Uint8List bytes) => run(
    _decodeBytes,
    bytes,
    label: 'API JSON',
    background: bytes.length >= 65536,
  );
  static Future<Object?> jsonString(String source) => run(
    jsonDecode,
    source,
    label: 'saved JSON',
    background: source.length >= 65536,
  );
  static Object? _decodeBytes(Uint8List bytes) =>
      jsonDecode(utf8.decode(bytes));
}
