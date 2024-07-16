import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

part 'web_socket_manager.g.dart';

enum WebSocketChannelState {
  /// The initial state when a client attempts to establish a WebSocket connection.
  connecting,

  /// Once the connection is successfully established, it enters the open state.
  open,

  /// When the client initiates a close handshake to terminate the connection,
  /// the WebSocket enters the closing state.
  closing,

  /// After the close handshake is completed or if the connection is terminated
  /// abruptly (e.g., due to an error), the WebSocket enters the closed state.
  closed;
}

const channelName = 'SinglesCasualChannel';

@Riverpod(keepAlive: true)
class WebSocketManager extends _$WebSocketManager {
  WebSocketChannel? _channel;
  int _retryCount = 0;
  final int _retryIntervalBase = 2;
  Timer? _retryTimer;
  DateTime lastCheckedAt = DateTime.now();

  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  WebSocketChannelState build() {
    connectAndSubscribe();

    ref.onDispose(
      () {
        _retryTimer?.cancel();
        close();
      },
    );

    return WebSocketChannelState.closed;
  }

  Future<void> connectAndSubscribe() async {
    // If connection already exists, don't create new one for preventing duplicated subscription.
    if (state != WebSocketChannelState.closed) return;
    state = WebSocketChannelState.connecting;
    _connect();
  }

  void _connect() {
    print('Connecting to the WebSocket server...');
    _channel = IOWebSocketChannel.connect('ws://echo.websocket.org');

    _channel?.stream.listen(
      _onMessageData,
      onError: _onError,
      onDone: _onClosed,
      cancelOnError: false,
    );

    _onConnected();

    ref.onDispose(() {
      close();
    });
  }

  Future<void> _onMessageData(dynamic data) async {
    print('Received data: $data');

    if (data == '"App is in the background"') {
      playMusic();
      print('Playing music');
    } else if (data == '"App is in the foreground"') {
      stopMusic();
      print('Stopping music');
    }
  }

  void _onError(dynamic error, StackTrace stackTrace) {
    print('WebSocket error occurred: $error');
  }

  void _onClosed() {
    switch (state) {
      case WebSocketChannelState.connecting:
        // If the connection is closed while connecting, try to reconnect.
        // This happens when the connection is closed before the connection is established.
        // (e.g., when authentication fails or the server is down)
        state = WebSocketChannelState.closed;
        _reconnect();
        break;
      case WebSocketChannelState.open:
        // Try to reconnect if the connection is closed unexpectedly.
        state = WebSocketChannelState.closed;
        _reconnect();
        break;
      case WebSocketChannelState.closing:
        // The connection is closed by the client.
        state = WebSocketChannelState.closed;
        break;
      case WebSocketChannelState.closed:
        break;
    }
  }

  void _reconnect() {
    final retryInterval =
        Duration(seconds: pow(_retryIntervalBase, _retryCount).toInt());

    _retryCount++;

    _retryTimer = Timer(retryInterval, () {
      connectAndSubscribe();
    });
  }

  void _onConnected() {
    print('Connected to the WebSocket server.');
    _retryCount = 0;
    state = WebSocketChannelState.open;
  }

  void close() async {
    state = WebSocketChannelState.closing;
    _channel?.sink.close();
  }

  void sendMessage(message) {
    if (state == WebSocketChannelState.open) {
      _channel?.sink.add(json.encode(message));
    } else {}
  }

  void playMusic() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(UrlSource(
        'https://2u039f-a.akamaihd.net/downloads/ringtones/files/mp3/dharni-beatbox-63102.mp3',
      ));
    } catch (e) {
      print('Failed to play music: $e');
    }
  }

  void stopMusic() async {
    await _audioPlayer.stop();
  }
}

enum WebSocketErrorType {
  connectionFailed,
  unexpectedlyClosed,
  authenticationFailed;

  @override
  String toString() {
    switch (this) {
      case WebSocketErrorType.connectionFailed:
        return 'Failed to establish a WebSocket connection.';
      case WebSocketErrorType.unexpectedlyClosed:
        return 'WebSocket connection is closed unexpectedly.';
      case WebSocketErrorType.authenticationFailed:
        return 'Failed to authenticate the WebSocket connection.';
    }
  }
}
