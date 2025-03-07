import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lfdi/constants.dart';
import 'package:lfdi/globals.dart';
import 'package:lfdi/handlers/discord_websocket/gateway_message.dart';
import 'package:lfdi/handlers/discord_websocket/message_handlers/handler_data.dart';
import 'package:lfdi/handlers/discord_websocket/message_handlers/handler_factory.dart';
import 'package:lfdi/utils/generate_random_string.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class DiscordWebSoket {
  final baseUrl = 'wss://gateway.discord.gg/?v=6&encoding=json';
  IOWebSocketChannel? webSocketChannel;

  /// Used for heartbeating
  int? lastSequence;

  /// Stores all handlers
  final GatewayHandlerFactory handlerFactory = GatewayHandlerFactory();

  /// Stores all listeners
  Map<String, Function> listeners = {};

  /// Used for checking timer heartbeat
  bool heartbeatIsConfigured = false;
  Timer? heartbeatTimer;

  /// Session token (random string?)
  String sessionToken = getRandomString(32);

  /// Session ID (even more random string?)
  String sessionId = getRandomString(16);

  /// Used for reconnecting state
  bool isReconnecting = false;

  /// Initialize websokcet
  void init() {
    logger.info('Creating connection', name: 'DWS: Main');
    webSocketChannel = IOWebSocketChannel.connect(Uri.parse(baseUrl), headers: {
      'User-Agent': userAgent,
    });

    logger.info('Starting listen to events', name: 'DWS: Main');
    webSocketChannel!.stream.listen((message) {
      if (message is Uint8List) {
        logger.info('Gateway sent array of bytes.', name: 'DWS: Main');

        return;
      }
      Map webSocketMessage = jsonDecode(message);
      logger.info('New message.', name: 'DWS: Main');

      // Start Manager updating if needed
      if (isReconnecting) {
        listeners['onReconnected_Manager']!();
        isReconnecting = false;
      }

      // Handle a message
      webSocketMessagesHandler(webSocketMessage);
    }, onDone: () async {
      logger.error('WebSocket connection was closed.', name: 'DWS: Main');
      logger.error(
        'WebSocket close code: ${webSocketChannel?.closeCode}',
        name: 'DWS: Main',
      );

      // If disconnection is not the user's will
      if (webSocketChannel?.closeCode != null &&
          webSocketChannel?.closeCode == 1005) {
        if (listeners['onDisconnect'] != null) {
          heartbeatTimer?.cancel();
          isReconnecting = true;
          await Future.delayed(const Duration(seconds: 1));
          init();
        }
      }
      // Stop WebSocketManager death process if WebSocket trying reconnect
      if (isReconnecting) {
        // Stop updates from Manager (if started)

        listeners['onReconnect_Manager']!();
        if (listeners['onReconnect_showSnackbar'] != null) {
          listeners['onReconnect_showSnackbar']!();
        }
        return;
      }

      // When OP Code `7` has recieved
      if (listeners['on_resume_hadler'] != null) {
        listeners['on_resume_hadler']!();

        if (listeners['onReconnectOp7_Manager'] != null) {
          listeners['onReconnectOp7_Manager']!();

          if (listeners['onReconnect_showSnackbar'] != null) {
            listeners['onReconnect_showSnackbar']!();
          }
        }

        return;
      }
      listeners['onClose_Manager']!();

      if (listeners['onClose'] != null) {
        listeners['onClose']!();
      }
      heartbeatTimer?.cancel();
    }, onError: (error) async {
      logger.error('WebSocket error $error.', name: 'DWS: Main');

      if (error is WebSocketChannelException) {
        logger.info('Reconnecting to WebSocket...', name: 'DWS: Main');
        heartbeatTimer?.cancel();
        isReconnecting = true;
        await Future.delayed(const Duration(seconds: 1));
        init();
      }
    });
  }

  /// Handles all incoming messages from Gateway
  void webSocketMessagesHandler(Map message) {
    // Make a class
    final DiscordGatewayMessage gatewayMessage =
        DiscordGatewayMessage.fromWebSocketMessage(message);
    logger.info(
      'Message info: OP Code is ${gatewayMessage.operationCode} (${opToName[gatewayMessage.operationCode]}). ${gatewayMessage.eventName != null ? 'Event name: ${gatewayMessage.eventName}' : ''}',
      name: 'DWS: WSMessageHandler',
    );

    // Select a handler from opcode
    final handler =
        handlerFactory.getHandlerByOpcode(gatewayMessage.operationCode);
    if (gatewayMessage.operationCode != 0) {
      logger.info(' Selected handler: $handler', name: 'DWS: WSMessageHandler');
    }

    // Set up message to a handler
    handler.setUpMessage(gatewayMessage);

    // All handlers must return data, regardless of whether they are empty
    // Return class is `GatewayHandlerData`
    final GatewayHandlerData dataFromHandler = handler.handle(this);
    if (gatewayMessage.operationCode != 0) {
      logger.info(
        'Handler returns data: ${dataFromHandler.toString()}',
        name: 'DWS: WSMessageHandler',
      );
    }

    // Set lastSequence
    lastSequence = gatewayMessage.sequence;

    // Check for heartbeat
    if (gatewayMessage.operationCode == 10) {
      if (dataFromHandler.data != null &&
          dataFromHandler.data!['configureHeartbeat'] != null) {
        if (!heartbeatIsConfigured) {
          logger.info('Setup heartbeat timer.', name: 'DWS: WSMessageHandler');
          if (listeners['onConnect_showSnackbar'] != null) {
            listeners['onConnect_showSnackbar']!();
          }

          heartbeatTimer = Timer.periodic(
            Duration(milliseconds: gatewayMessage.data['heartbeat_interval']),
            (timer) {
              final DiscordGatewayMessage messageToSent = DiscordGatewayMessage(
                operationCode: 1,
                data: lastSequence,
                eventName: null,
                sequence: null,
              );
              logger.info(
                'Send heartbeat. Last sequence number is: $lastSequence',
                name: 'DWS: Heartbeat Timer',
              );
              webSocketChannel!.sink.add(messageToSent.toJsonString());
            },
          );
        }
      }
    }

    // Check for Invalid Session (opcode 9)
    if (gatewayMessage.operationCode == 9) {
      if (listeners['onInvalidSession_Manager'] != null) {
        listeners['onInvalidSession_Manager']!();
      }
    }
  }

  /// Returns the last sequence number
  ///
  /// Used for HelloHandler,
  /// that sends last sequence number
  /// once at `heartbeat_interval` milliseconds
  int? getlastSequence() {
    return lastSequence;
  }

  /// Sends the message to Gateway
  void sendMessage(DiscordGatewayMessage messageToSend) {
    String message = messageToSend.toJsonString();
    logger.info('Sending message: $message', name: 'DWS: Main');
    webSocketChannel!.sink.add(message);
  }

  /// Closes the connection
  void closeConnection() {
    logger.info('Closing connection', name: 'DWS: Main');

    webSocketChannel?.sink.close();
  }

  /// Dispose the WebSocket
  void dispose() {
    logger.debug('Triggered dispose', name: 'DWS: Main');
    closeConnection();

    heartbeatIsConfigured = false;
    heartbeatTimer?.cancel();

    Future.delayed(const Duration(milliseconds: 200))
        .then((value) => removeAllListeners());
  }

  /// Set up listeners (must before init)
  void setUpListeners(Map<String, Function> listeners) {
    this.listeners = listeners;
  }

  void addListener({
    required String name,
    required Function listener,
  }) {
    listeners[name] = listener;
  }

  void removeListener({required String listenerName}) {
    listeners.remove(listenerName);
  }

  void removeAllListeners() {
    listeners.clear();
  }
}

Map<int, String> opToName = {
  0: 'Dispatch',
  10: 'Hello',
  11: 'Heartbeat ACK',
};
