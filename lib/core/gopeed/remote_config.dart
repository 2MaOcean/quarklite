import 'package:shared_preferences/shared_preferences.dart';

/// 远程 Gopeed 转发配置。
///
/// iOS 未内嵌 Gopeed 内核，开启后把网盘下载直链发送到局域网 / 远程
/// Gopeed 实例（电脑、NAS、安卓手机上的 Gopeed）的多线程下载引擎。
/// 配置同时被 [GopeedEngine]（core 层，直接读 SharedPreferences）
/// 与设置页（AppState）共用，key 必须保持一致。
class RemoteGopeedConfig {
  static const _kEnabled = 'gopeed_remote_enabled';
  static const _kHost = 'gopeed_remote_host';
  static const _kPort = 'gopeed_remote_port';
  static const _kToken = 'gopeed_remote_token';
  static const _kDir = 'gopeed_remote_dir';

  static const defaultPort = 9999;

  final bool enabled;
  final String host;
  final int port;
  final String token;

  /// 远程下载目录（可选）。空字符串表示使用远程 Gopeed 自身的默认目录。
  final String dir;

  const RemoteGopeedConfig({
    required this.enabled,
    required this.host,
    required this.port,
    required this.token,
    required this.dir,
  });

  const RemoteGopeedConfig.disabled()
      : enabled = false,
        host = '',
        port = defaultPort,
        token = '',
        dir = '';

  /// 当前是否应启用远程转发：开关打开且地址已填写
  bool get isActive => enabled && host.trim().isNotEmpty;

  /// REST API 根地址
  String get baseUrl => 'http://${host.trim()}:${port <= 0 ? defaultPort : port}';

  /// 读取远程转发配置；未启用或地址为空时返回 null（回落本机下载器）
  static Future<RemoteGopeedConfig?> load() async {
    final cfg = await loadRaw();
    return cfg.isActive ? cfg : null;
  }

  /// 读取配置原始值（不过滤启用状态），供设置页回显
  static Future<RemoteGopeedConfig> loadRaw() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return RemoteGopeedConfig(
        enabled: prefs.getBool(_kEnabled) ?? false,
        host: prefs.getString(_kHost)?.trim() ?? '',
        port: prefs.getInt(_kPort) ?? defaultPort,
        token: prefs.getString(_kToken)?.trim() ?? '',
        dir: prefs.getString(_kDir)?.trim() ?? '',
      );
    } catch (_) {
      return const RemoteGopeedConfig.disabled();
    }
  }

  /// 写入配置（设置页保存时调用）
  static Future<void> save(RemoteGopeedConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, cfg.enabled);
    await prefs.setString(_kHost, cfg.host.trim());
    await prefs.setInt(_kPort, cfg.port <= 0 ? defaultPort : cfg.port);
    await prefs.setString(_kToken, cfg.token.trim());
    await prefs.setString(_kDir, cfg.dir.trim());
  }

  RemoteGopeedConfig copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? token,
    String? dir,
  }) {
    return RemoteGopeedConfig(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      dir: dir ?? this.dir,
    );
  }
}
