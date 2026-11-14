import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The factory owns TLS as well as TCP. Supplying a raw Socket to an HTTPS
/// HttpClient connectionFactory does not upgrade it automatically.
Future<ConnectionTask<Socket>> pluginTlsConnection(
  InternetAddress address,
  String hostname, {
  int port = 443,
  SecurityContext? context,
}) async {
  final tcp = await Socket.startConnect(address, port);
  Socket? raw;
  SecureSocket? secure;
  var cancelled = false;
  void cancel() {
    cancelled = true;
    tcp.cancel();
    raw?.destroy();
    secure?.destroy();
  }

  final socket =
      (() async {
        raw = await tcp.socket;
        if (cancelled) {
          raw!.destroy();
          throw const SocketException('Connection cancelled');
        }
        secure = await SecureSocket.secure(
          raw!,
          host: hostname,
          context: context,
        );
        if (cancelled) {
          secure!.destroy();
          throw const SocketException('Connection cancelled');
        }
        return secure! as Socket;
      })().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          cancel();
          throw TimeoutException('TLS connection timed out');
        },
      );
  return ConnectionTask.fromSocket(socket, cancel);
}

/// Resolve once and connect to that checked IP, retaining the original TLS
/// hostname. Redirects are refused, preventing allow-list/DNS-rebinding escapes.
bool pluginPublicAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 4) {
    return !(b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127));
  }
  // Only global unicast; mapped IPv4, loopback, local/link-local are excluded.
  return b.length == 16 && (b[0] & 0xe0) == 0x20;
}

Future<Map<String, dynamic>> pluginFetch(
  Set<String> domains,
  Map<String, dynamic> args,
) async {
  final uri = Uri.tryParse(args['url'] is String ? args['url'] as String : '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      !domains.contains(uri.host) ||
      uri.toString().length > 4096) {
    throw StateError('网络地址未获授权');
  }
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..findProxy = (_) => 'DIRECT';
  try {
    return await (() async {
      final addresses = await InternetAddress.lookup(uri.host);
      if (addresses.isEmpty || addresses.any((a) => !pluginPublicAddress(a))) {
        throw StateError('禁止访问本地网络');
      }
      client.connectionFactory = (url, proxyHost, proxyPort) =>
          pluginTlsConnection(addresses.first, uri.host);
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw StateError('不允许重定向');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 96 * 1024) throw StateError('响应体过大');
        bytes.addAll(chunk);
      }
      return {
        'status': response.statusCode,
        'body': utf8.decode(bytes, allowMalformed: true),
      };
    })().timeout(const Duration(seconds: 4));
  } finally {
    client.close(force: true);
  }
}
