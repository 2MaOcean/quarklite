import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/baidu_client.dart';
import '../utils/app_logger.dart';

/// 百度网盘登录态管理（单账号 Cookie 持久化，实验性）。
///
/// 登录方式：浏览器登录百度网盘后，把 Cookie（至少含 BDUSS）粘贴进应用。
class BaiduState extends ChangeNotifier {
  static const _kCookie = 'baidu_cookie';
  static const _kUsername = 'baidu_username';

  static BaiduState? _instance;
  static BaiduState get I => _instance ??= BaiduState._();

  final BaiduClient client = BaiduClient();
  final _secure = const FlutterSecureStorage();

  String username = '';
  String? loginError;
  bool loading = false;
  bool _ready = false;

  bool get isLoggedIn => client.hasLogin;

  BaiduState._();

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      final cookie = await _readCookie();
      if (cookie == null || cookie.isEmpty) return;
      client.setCookie(cookie);
      username = await _read(_kUsername);
    } catch (e) {
      AppLogger.I.e('baidu', '恢复登录态失败: $e');
    }
  }

  Future<String?> _readCookie() async {
    try {
      return await _secure.read(key: _kCookie);
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_kCookie);
      } catch (_) {
        return null;
      }
    }
  }

  Future<String> _read(String key) async {
    try {
      return await _secure.read(key: key) ?? '';
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(key) ?? '';
      } catch (_) {
        return '';
      }
    }
  }

  Future<void> _saveCookie(String cookie) async {
    try {
      await _secure.write(key: _kCookie, value: cookie);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCookie, cookie);
    } catch (_) {}
  }

  Future<void> _saveUsername(String name) async {
    try {
      await _secure.write(key: _kUsername, value: name);
    } catch (_) {}
  }

  Future<void> _clear() async {
    try {
      await _secure.delete(key: _kCookie);
      await _secure.delete(key: _kUsername);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCookie);
      await prefs.remove(_kUsername);
    } catch (_) {}
  }

  /// 登录：设置 Cookie 并验证，返回错误信息（null 表示成功）
  Future<String?> login(String cookie) async {
    try {
      client.setCookie(cookie);
      loading = true;
      loginError = null;
      notifyListeners();
      username = await client.validate();
      await _saveCookie(client.cookie);
      await _saveUsername(username);
      return null;
    } catch (e) {
      client.setCookie('');
      return e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    client.setCookie('');
    username = '';
    await _clear();
    notifyListeners();
  }
}
