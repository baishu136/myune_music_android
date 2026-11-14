import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/plugins/plugin_network.dart';

void main() {
  late SecurityContext trusted, serverContext;
  setUp(() {
    // Public test-only self-signed fixture, valid 2000--2100, never an app key.
    final cert = File('test/fixtures/plugin_tls_cert.txt').readAsBytesSync();
    final key = File('test/fixtures/plugin_tls_key.txt').readAsBytesSync();
    trusted = SecurityContext()..setTrustedCertificatesBytes(cert);
    serverContext = SecurityContext()
      ..useCertificateChainBytes(cert)
      ..usePrivateKeyBytes(key);
  });
  test(
    'pinned IP factory performs TLS with the original host before sending data',
    () async {
      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      final sockets = <Socket>[];
      final received = Completer<String>();
      final subscription = server.listen((socket) {
        sockets.add(socket);
        socket.listen((data) {
          if (!received.isCompleted) received.complete(utf8.decode(data));
          socket.write('encrypted reply');
        });
      });
      addTearDown(() async {
        for (final s in sockets) {
          s.destroy();
        }
        await subscription.cancel();
        await server.close();
      });
      final task = await pluginTlsConnection(
        InternetAddress.loopbackIPv4,
        'localhost',
        port: server.port,
        context: trusted,
      );
      final socket = await task.socket.timeout(const Duration(seconds: 5));
      addTearDown(socket.destroy);
      expect(socket, isA<SecureSocket>());
      expect((socket as SecureSocket).peerCertificate, isNotNull);
      socket.write('encrypted request');
      expect(
        await received.future.timeout(const Duration(seconds: 5)),
        'encrypted request',
      );
      expect(
        utf8.decode(await socket.first.timeout(const Duration(seconds: 5))),
        'encrypted reply',
      );
    },
  );
  test(
    'trusted certificate still rejects the wrong original hostname',
    () async {
      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      final subscription = server.listen(
        (socket) => socket.destroy(),
        onError: (Object _) {},
      );
      addTearDown(() async {
        await subscription.cancel();
        await server.close();
      });
      final task = await pluginTlsConnection(
        InternetAddress.loopbackIPv4,
        'wrong.example',
        port: server.port,
        context: trusted,
      );
      await expectLater(task.socket, throwsA(isA<HandshakeException>()));
    },
  );
  test(
    'cancelling a pending handshake closes its underlying connection',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final subscription = server.listen(sockets.add);
      addTearDown(() async {
        for (final s in sockets) {
          s.destroy();
        }
        await subscription.cancel();
        await server.close();
      });
      final task = await pluginTlsConnection(
        InternetAddress.loopbackIPv4,
        'localhost',
        port: server.port,
        context: trusted,
      );
      final failed = expectLater(
        task.socket,
        throwsA(anyOf(isA<SocketException>(), isA<HandshakeException>())),
      );
      task.cancel();
      await failed.timeout(const Duration(seconds: 5));
    },
  );
}
