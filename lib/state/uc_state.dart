import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/uc_client.dart';
import '../api/quark_models.dart';
import '../utils/app_logger.dart';

/// UC 网盘登录态管理（单账号 Cookie 持久化，实验性）。
///
/// UC 网盘与夸克同 API 家族，登录采用与夸克一致的网页 Cookie 方案：
/// 用户在浏览器登录 pan.uc.cn 后，把 Cookie 粘贴进应用。
class UcState extends ChangeNotifier {
  static const _kCookie = 'uc_cookie';
  static const _kUserCache = 'uc_user_cache';

  static UcState? _instance;
  static UcState get I => _instance ??= UcState._();

  final UcClient client = UcClient();
  final _secure = const FlutterSecureStorage();

  QuarkUserInfo? user;
  String? loginError;
  bool loading = false;
  bool _ready = false;

  bool get isLoggedIn => client.hasLogin;

  UcState._();

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      final cookie = await _readCookie();
      if (cookie == null || cookie.isEmpty) return;
      client.setCookie(cookie);
      user = await _readCachedUser();
      // 后台刷新用户信息，失败不登出（网络抖动常见）
      refreshUser();
    } catch (e) {
      AppLogger.I.e('uc', '恢复登录态失败: $e');
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

  Future<void> _saveCookie(String cookie) async {
    try {
      await _secure.write(key: _kCookie, value: cookie);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCookie, cookie);
    } catch (_) {}
  }

  Future<void> _clearCookie() async {
    try {
      await _secure.delete(key: _kCookie);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCookie);
      await prefs.remove(_kUserCache);
    } catch (_) {}
  }

  /// 登录：设置 Cookie 并验证，返回错误信息（null 表示成功）
  Future<String?> login(String cookie) async {
    try {
      client.setCookie(cookie);
      loading = true;
      notifyListeners();
      user = await client.getUserInfo();
      loginError = null;
      await _saveCookie(client.cookie);
      await _cacheUser(user!);
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
    user = null;
    await _clearCookie();
    notifyListeners();
  }

  Future<void> refreshUser() async {
    if (!isLoggedIn) return;
    loading = true;
    notifyListeners();
    try {
      user = await client.getUserInfo();
      loginError = null;
      await _cacheUser(user!);
    } catch (e) {
      if (user == null) loginError = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _cacheUser(QuarkUserInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUserCache, info.nickname);
    } catch (_) {}
  }

  Future<QuarkUserInfo?> _readCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_kUserCache) ?? '';
      if (name.isEmpty) return null;
      return QuarkUserInfo(
          nickname: name, avatar: '', userId: '', totalSize: 0, usedSize: 0);
    } catch (_) {
      return null;
    }
  }
}
