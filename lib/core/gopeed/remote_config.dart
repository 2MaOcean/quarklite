import 'package:shared_preferences/shared_preferences.dart';

/// 「发送到 Gopeed」转发配置。
///
/// iOS 未内嵌 Gopeed 内核，开启后把网盘下载直链发送到设备上安装的
/// Gopeed iOS 版（内核监听 127.0.0.1 的随机端口，端口由自动扫描发现），
/// 也可以填局域网内电脑 / NAS 上 Gopeed 的地址实现远程下载。
/// 配置同时被 [GopeedEngine]（core 层，直接读 SharedPreferences）
/// 与设置页（AppState）共用，key 必须保持一致。
class RemoteGopeedConfig {
  static const _kEnabled = 'gopeed_remote_enabled';
  static const _kHost = 'gopeed_remote_host';
  static const _kPort = 'gopeed_remote_port';
  static const _kToken = 'gopeed_remote_token';
  static const _kDir = 'gopeed_remote_dir';

  /// 本机 Gopeed（iOS 版）的固定地址
  static const localHost = '127.0.0.1';

  final bool enabled;
  final String host;
  final int port;
  final String token;

  /// 下载目录（可选）。空字符串表示使用 Gopeed 自身的默认下载目录
  /// （iOS 版 Gopeed 文件在其沙箱内，通常无需填写）。
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
        host = localHost,
        port = 0,
        token = '',
        dir = '';

  /// 当前是否可用：开关打开、地址已填写且端口已扫描到（>0）
  bool get isActive => enabled && host.trim().isNotEmpty && port > 0;

  /// REST API 根地址（port 无效时返回空串，调用方不应使用）
  String get baseUrl =>
      port > 0 ? 'http://${host.trim()}:$port' : '';

  /// 读取转发配置；未启用、地址为空或端口未设置时返回 null（回落本机下载器）
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
        port: prefs.getInt(_kPort) ?? 0,
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
    await prefs.setInt(_kPort, cfg.port);
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
