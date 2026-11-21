import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 本机回环地址上的 Gopeed REST 端口扫描器。
///
/// 背景：iOS 版 Gopeed 内核监听 `127.0.0.1:0`（系统随机分配端口），
/// 且其设置界面的协议/地址项在 iOS 上不可修改，无法固定端口。
/// 同一设备上 App 之间访问 loopback 端口不受沙箱限制，因此通过
/// 扫描本机端口、识别 REST 响应特征即可定位 Gopeed。
class GopeedPortScanner {
  GopeedPortScanner._();

  /// 常见固定端口优先尝试（桌面版默认 9999、容器映射等）
  static const _commonPorts = [9999, 9998, 18080, 58080];

  /// iOS 系统临时端口范围（net.inet.ip.portrange.first/last）
  static const _ephemeralFirst = 49152;
  static const _ephemeralLast = 65535;

  static const _connectTimeout = Duration(milliseconds: 120);
  static const _responseTimeout = Duration(milliseconds: 400);
  static const _concurrency = 128;

  /// 扫描本机 127.0.0.1 上的 Gopeed REST API。
  ///
  /// 识别依据：`GET /api/v1/info` 返回 200 且 body 含 `"code":0` 与
  /// `"version"` 字段（Gopeed REST 响应的固定结构）。
  /// 返回命中的端口；未找到返回 null。
  /// [onProgress] 每 256 个端口回调一次已扫描数（用于进度提示）。
  static Future<int?> scan({
    void Function(int scanned, int total)? onProgress,
  }) async {
    final candidates = <int>[
      ..._commonPorts,
      for (var p = _ephemeralFirst; p <= _ephemeralLast; p++) p,
    ];
    final total = candidates.length;
    var scanned = 0;
    var cancelled = false;

    int? next() {
      if (candidates.isEmpty || cancelled) return null;
      return candidates.removeLast();
    }

    Future<int?> worker() async {
      while (true) {
        final port = next();
        if (port == null) return null;
        final hit = await _probe(port);
        scanned++;
        if (hit) return port;
        if (scanned % 256 == 0) onProgress?.call(scanned, total);
      }
    }

    try {
      final workers = List.generate(_concurrency, (_) => worker());
      while (workers.isNotEmpty) {
        final done = await Future.any(workers);
        final port = await done;
        if (port != null) {
          cancelled = true;
          return port;
        }
        workers.remove(done);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 探测单个端口：先 TCP 连通，再发 HTTP 请求验证 Gopeed 特征
  static Future<bool> _probe(int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: _connectTimeout,
      );
      socket.add(utf8.encode(
          'GET /api/v1/info HTTP/1.1\r\nHost: 127.0.0.1\r\n'
          'Connection: close\r\n\r\n'));
      final body = await _readAll(socket)
          .timeout(_responseTimeout, onTimeout: () => '');
      return body.startsWith('HTTP/1.') &&
          body.contains('"version"') &&
          body.contains('"code":0');
    } catch (_) {
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// 读取全部响应文本：先收集字节再一次性解码，
  /// 避免 Utf8Decoder 直接 transform Uint8List 流的泛型不匹配
  static Future<String> _readAll(Socket socket) async {
    final builder = BytesBuilder();
    await for (final chunk in socket) {
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }
}
