import 'package:dio/dio.dart';

import '../utils/types.dart';

/// 百度网盘 API 异常
class BaiduException implements Exception {
  final int errno;
  final String message;

  BaiduException(this.errno, this.message);

  @override
  String toString() => message;
}

/// 百度网盘文件模型（以全路径 path 作为文件标识）
class BaiduFile {
  final String path;
  final String name;
  final bool isDir;
  final int size;
  final int fsId;
  final int mtime;

  const BaiduFile({
    required this.path,
    required this.name,
    required this.isDir,
    required this.size,
    required this.fsId,
    required this.mtime,
  });

  factory BaiduFile.fromJson(Map<String, dynamic> json) {
    final path = json['path']?.toString() ?? '';
    return BaiduFile(
      path: path,
      name: json['server_filename']?.toString() ??
          (path.isEmpty ? '' : path.split('/').last),
      isDir: toInt(json['isdir']) == 1 || json['isdir'] == true,
      size: toInt(json['size']),
      fsId: toInt(json['fs_id']),
      mtime: toInt(json['local_mtime']) * 1000,
    );
  }
}

/// 百度网盘客户端（Cookie 登录，实验性）。
///
/// 使用网页端接口（pan.baidu.com/api/*），登录方式：在浏览器登录
/// 百度网盘后，把 Cookie（至少包含 BDUSS）粘贴进应用。
///
/// 下载直链（dlink）对请求头敏感：请求直链时必须携带与获取时一致的
/// User-Agent 与 Cookie，否则会被拒绝或严重限速。Gopeed 任务创建时
/// 会附带这两项请求头。
class BaiduClient {
  static const _base = 'https://pan.baidu.com';

  /// 统一 UA：列表与直链请求必须保持一致
  static const ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  final Dio _dio;
  String cookie = '';

  BaiduClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  bool get hasLogin => cookie.contains('BDUSS');

  void setCookie(String c) {
    cookie = c.trim();
  }

  Map<String, dynamic> _headers() => {
        'Accept': 'application/json, text/plain, */*',
        'Referer': '$_base/',
        'User-Agent': ua,
        if (cookie.isNotEmpty) 'Cookie': cookie,
      };

  /// 校验响应 errno，失败抛 [BaiduException]
  Map<String, dynamic> _check(Response<dynamic> resp) {
    final body = resp.data;
    if (body is! Map) {
      throw BaiduException(-1, '响应格式异常（可能 Cookie 失效）');
    }
    final map = body.cast<String, dynamic>();
    final errno = toInt(map['errno'], fallback: -1);
    if (errno != 0) {
      throw BaiduException(errno, _errnoText(errno));
    }
    return map;
  }

  static String _errnoText(int errno) {
    switch (errno) {
      case -6:
        return '身份验证失败，Cookie 已失效，请重新登录';
      case 2:
        return '参数错误';
      case 12:
        return '文件/文件夹已存在';
      case 111:
        return '请求过于频繁，请稍后再试';
      case 112:
        return '会话已过期，请重新登录';
      default:
        return '百度网盘返回错误（errno=$errno）';
    }
  }

  Future<Map<String, dynamic>> _get(String path,
      {Map<String, dynamic>? params}) async {
    final resp = await _dio.get<Map<String, dynamic>>('$_base$path',
        queryParameters: params,
        options: Options(
            headers: _headers(), validateStatus: (_) => true));
    return _check(resp);
  }

  /// 表单 POST（百度网页接口使用 urlencoded 表单）
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> form,
      {Map<String, dynamic>? params}) async {
    final resp = await _dio.request<dynamic>('$_base$path',
        data: form,
        queryParameters: params,
        options: Options(
            method: 'POST',
            headers: {
              ..._headers(),
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            validateStatus: (_) => true));
    return _check(resp);
  }

  // ---------------- 账号 ----------------

  /// 验证 Cookie 有效性并返回用户名
  Future<String> validate() async {
    final map = await _get('/api/quota',
        params: {'checkfree': 1, 'checkexpire': 1, 'web': 1, 'clienttype': 'web'});
    // quota 不含用户名，再取一次用户信息接口（失败不阻塞）
    try {
      final info = await _get('/rest/2.0/xpan/nas',
          params: {'method': 'uinfo', 'web': 1, 'clienttype': 'web'});
      final name = info['user_name']?.toString() ?? '';
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return '百度账号';
  }

  /// 容量信息（总/已用，字节）
  Future<(int, int)> quota() async {
    final map = await _get('/api/quota',
        params: {'checkfree': 1, 'checkexpire': 1, 'web': 1, 'clienttype': 'web'});
    return (toInt(map['total']), toInt(map['used']));
  }

  // ---------------- 文件 ----------------

  List<BaiduFile> _parseList(Map<String, dynamic> map) {
    final list = map['list'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => BaiduFile.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// 列出目录内容（[dir] 为以 / 开头的完整路径）
  Future<List<BaiduFile>> list(String dir) async {
    final map = await _get('/api/list', params: {
      'dir': dir,
      'web': 1,
      'clienttype': 'web',
      'order': 'name',
      'desc': 0,
      'showempty': 0,
      'num': 1000,
    });
    return _parseList(map);
  }

  /// 全盘搜索（文件名关键词）
  Future<List<BaiduFile>> search(String keyword) async {
    final map = await _get('/api/search', params: {
      'key': keyword,
      'web': 1,
      'clienttype': 'web',
      'dir': '/',
      'recursion': 1,
    });
    return _parseList(map);
  }

  /// 获取下载直链（附带 Cookie；请求直链时必须用 [ua] 与本客户端 Cookie）
  Future<String> downloadUrl(String path) async {
    final map = await _get('/api/filemetas', params: {
      'target': '["$path"]',
      'dlink': 1,
      'web': 1,
      'clienttype': 'web',
    });
    final info = map['info'];
    if (info is List && info.isNotEmpty) {
      final dlink = (info.first as Map)['dlink']?.toString() ?? '';
      if (dlink.isNotEmpty) return dlink;
    }
    throw BaiduException(-1, '未获取到下载直链');
  }

  // ---------------- 文件管理操作 ----------------

  /// 获取 bdstoken（新建文件夹等提交接口需要）
  Future<String> _bdstoken() async {
    final map = await _get('/api/gettemplatevariable', params: {
      'clienttype': 'web',
      'web': 1,
      'fields': '["bdstoken"]',
    });
    final result = map['result'];
    if (result is Map) {
      return result['bdstoken']?.toString() ?? '';
    }
    return '';
  }

  /// 重命名（path 为文件全路径）
  Future<void> renameFile(String path, String newName) async {
    await _post('/api/filemanager/rename', {
      'filelist': '[{"path":"$path","newname":"$newName"}]',
      'async': 1,
      'ondup': 'fail',
    }, params: {'web': 1, 'clienttype': 'web'});
  }

  /// 删除（移入百度网盘回收站）
  Future<void> deleteFiles(List<String> paths) async {
    await _post('/api/filemanager/delete', {
      'filelist': '[${paths.map((p) => '"$p"').join(',')}]',
      'async': 1,
    }, params: {'web': 1, 'clienttype': 'web'});
  }

  /// 移动到目标目录（dest 为目录全路径）
  Future<void> moveFiles(List<String> paths, String dest) async {
    await _post('/api/filemanager/move', {
      'filelist': '[${paths.map((p) => '"$p"').join(',')}]',
      'dest': dest,
      'async': 1,
      'ondup': 'newcopy',
    }, params: {'web': 1, 'clienttype': 'web'});
  }

  /// 新建文件夹（[dirPath] 为新目录的完整路径）
  Future<void> createFolder(String dirPath) async {
    final token = await _bdstoken();
    await _post('/api/create', {
      'path': dirPath,
      'isdir': 1,
      'block_list': '[]',
      'async': 1,
    }, params: {
      'a': 'commit',
      'bdstoken': token,
      'clienttype': 'web',
      'web': 1,
    });
  }
}
