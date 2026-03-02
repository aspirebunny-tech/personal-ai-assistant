import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SpeechService {
  static const MethodChannel _channel = MethodChannel('speech_recognition');
  final Function(String text, bool isFinal) onResult;
  final Function(String status) onStatus;
  final Function(String error) onError;

  SpeechService({
    required this.onResult,
    required this.onStatus,
    required this.onError,
  }) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSpeechResult':
        final String text = call.arguments['text'] ?? '';
        final bool isFinal = call.arguments['isFinal'] ?? false;
        onResult(text, isFinal);
        break;
      case 'onStatusChanged':
        final String status = call.arguments ?? '';
        onStatus(status);
        break;
      case 'onError':
        final String error = call.arguments ?? 'Unknown error';
        onError(error);
        break;
      default:
        debugPrint('Unknown method ${call.method}');
    }
  }

  Future<bool> initialize() async {
    try {
      final bool available = await _channel.invokeMethod('initialize');
      return available;
    } on PlatformException catch (e) {
      onError(e.message ?? 'Initialization failed');
      return false;
    }
  }

  Future<void> startListening({required String localeId}) async {
    try {
      await _channel.invokeMethod('startListening', {'localeId': localeId});
    } on PlatformException catch (e) {
      onError(e.message ?? 'Start listening failed');
    }
  }

  Future<void> stopListening() async {
    try {
      await _channel.invokeMethod('stopListening');
    } on PlatformException catch (e) {
      onError(e.message ?? 'Stop listening failed');
    }
  }
}
