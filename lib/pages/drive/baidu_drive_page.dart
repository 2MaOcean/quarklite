import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../api/baidu_client.dart';
import '../../state/app_state.dart';
import '../../state/baidu_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';
import '../../widgets/netdisk_logo.dart';
import 'baidu_move_target_page.dart';

/// 百度网盘文件浏览页（实验性）：面包屑导航 + 多选下载 + 文件管理操作。
///
/// 使用网页端接口（Cookie 登录），下载直链对请求头敏感，
/// Gopeed 任务会附带与获取时一致的 Cookie 与 User-Agent。
class BaiduDrivePage extends StatefulWidget {
  const BaiduDrivePage({super.key});

  @override
  State<BaiduDrivePage> createState() => _BaiduDrivePageState();
}

class _BaiduDrivePageState extends State<BaiduDrivePage> {
  List<BaiduFile> _files = [];
  String _dir = '/';
  String _currentName = '全部文件';
  bool _loading = false;
  String? _error;

  bool _selectMode = false;
  final Set<String> _selected = {}; // 文件全路径
  bool _busy = false;

  BaiduState get _state => BaiduState.I;
  BaiduClient get _client => _state.client;

  @override
  void initState() {
    super.initState();
    _state.init().then((_) => _load());
  }

  Future<void> _load() async {
    if (!_state.isLoggedIn) {
      if (mounted) {
        setState(() {
          _files = [];
          _error = '未登录';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await _client.list(_dir);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      AppLogger.I.e('baidu', '文件列表失败: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _enterDir(BaiduFile dir) {
    setState(() {
      _dir = dir.path;
      _currentName = dir.name;
      _files = [];
      _selectMode = false;
      _selected.clear();
      _loading = true;
    });
    _load();
  }

  void _toBreadcrumb(int index) {
    final crumbs = _crumbs;
    if (index >= crumbs.length - 1) return;
    setState(() {
      _dir = crumbs[index].$1;
      _currentName = crumbs[index].$2;
      _files = [];
      _error = null;
      _selectMode = false;
      _selected.clear();
      _loading = true;
    });
    _load();
  }

  /// 当前路径的面包屑段
  List<(String, String)> get _crumbs {
    final segs = _dir.split('/').where((s) => s.isNotEmpty).toList();
    final crumbs = <(String, String)>[('/', '全部文件')];
    var acc = '';
    for (final s in segs) {
      acc += '/$s';
      crumbs.add((acc, s));
    }
    return crumbs;
  }

  void _toast(String msg) => MiuixToast.show(msg);

  // ---------------- 登录 ----------------

  Future<void> _login() async {
    final cookie = await miuixInputDialog(
      context,
      title: '百度网盘 Cookie 登录',
      hint: '粘贴浏览器登录 pan.baidu.com 后的 Cookie（含 BDUSS）',
      confirmText: '登录',
    );
    if (cookie == null || cookie.trim().isEmpty) return;
    final err = await _state.login(cookie.trim());
    if (!mounted) return;
    if (err != null) {
      _toast('登录失败：$err');
      return;
    }
    _toast('登录成功');
    _load();
  }

  // ---------------- 搜索 ----------------

  Future<void> _search() async {
    final kw = await miuixInputDialog(
      context,
      title: '搜索百度网盘',
      hint: '输入文件名关键词',
      confirmText: '搜索',
    );
    if (kw == null || kw.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _selectMode = false;
      _selected.clear();
    });
    try {
      final files = await _client.search(kw.trim());
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
          _currentName = '搜索：${kw.trim()}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  // ---------------- 多选下载 ----------------

  void _enterSelectMode(BaiduFile file) {
    setState(() {
      _selectMode = true;
      _selected.add(file.path);
    });
  }

  void _toggleSelect(BaiduFile file) {
    setState(() {
      if (!_selected.remove(file.path)) {
        _selected.add(file.path);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  Future<void> _batchDownload() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final targets =
          _files.where((f) => _selected.contains(f.path)).toList();
      final items = await _expandSelection(targets, '');
      if (items.isEmpty) {
        _toast('没有可下载的文件');
        return;
      }
      var added = 0;
      final base = await AppState.I.effectiveDownloadDir();
      for (final (f, rel) in items) {
        try {
          final url = await _client.downloadUrl(f.path);
          if (url.isEmpty) continue;
          final path = rel.isEmpty ? base : '$base/$rel';
          final err = await DownloadService.addDirectUrl(
            url: url,
            fileName: f.name,
            cookie: _client.cookie,
            path: path,
            batchTotal: items.length,
            referer: 'https://pan.baidu.com/',
            userAgent: BaiduClient.ua,
          );
          if (err == null) added++;
        } catch (e) {
          AppLogger.I.e('baidu', '取直链失败 ${f.name}: $e');
        }
      }
      _toast('已添加 $added 个下载任务');
      DownloadManager.I.startPolling();
      _exitSelectMode();
    } catch (e) {
      _toast('批量下载失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 展开选中项为 (file, 相对路径) 列表（文件夹递归收集）
  Future<List<(BaiduFile, String)>> _expandSelection(
      List<BaiduFile> selected, String relBase) async {
    final result = <(BaiduFile, String)>[];
    for (final f in selected) {
      if (f.isDir) {
        final children = await _client.list(f.path);
        result.addAll(await _expandSelection(children, '$relBase${f.name}/'));
      } else {
        result.add((f, relBase));
      }
    }
    return result;
  }

  // ---------------- 文件操作 ----------------

  void _showFileMenu(BaiduFile file) {
    MiuixActionSheet.show<String>(context, title: file.name, actions: [
      if (!file.isDir)
        (
          icon: Icons.download_rounded,
          text: '下载',
          value: 'download',
          color: null,
        ),
      (
        icon: Icons.drive_file_rename_outline_rounded,
        text: '重命名',
        value: 'rename',
        color: null,
      ),
      (
        icon: Icons.drive_file_move_rounded,
        text: '移动到…',
        value: 'move',
        color: null,
      ),
      (
        icon: Icons.delete_outline_rounded,
        text: '删除',
        value: 'delete',
        color: AppColors.red,
      ),
    ]).then((v) async {
      if (v == null) return;
      switch (v) {
        case 'download':
          await _downloadSingle(file);
        case 'rename':
          await _renameFile(file);
        case 'move':
          await _moveFiles({file.path});
        case 'delete':
          await _deleteFiles({file.path});
      }
    });
  }

  Future<void> _downloadSingle(BaiduFile file) async {
    try {
      final url = await _client.downloadUrl(file.path);
      final base = await AppState.I.effectiveDownloadDir();
      final err = await DownloadService.addDirectUrl(
        url: url,
        fileName: file.name,
        cookie: _client.cookie,
        path: base,
        referer: 'https://pan.baidu.com/',
        userAgent: BaiduClient.ua,
      );
      if (err != null) throw Exception(err);
      _toast('已加入下载队列');
      DownloadManager.I.startPolling();
    } catch (e) {
      _toast('下载失败: $e');
    }
  }

  Future<void> _renameFile(BaiduFile file) async {
    final name = await miuixInputDialog(
      context,
      title: '重命名',
      hint: '新名称',
      initialText: file.name,
      confirmText: '保存',
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == file.name) return;
    try {
      await _client.renameFile(file.path, trimmed);
      _toast('已重命名');
      _load();
    } catch (e) {
      _toast('重命名失败: $e');
    }
  }

  Future<void> _moveFiles(Set<String> paths) async {
    final dest = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BaiduMoveTargetPage(
          movedPaths: paths,
          listDirs: (dir) => _client.list(dir),
        ),
      ),
    );
    if (dest == null || !mounted) return;
    try {
      await _client.moveFiles(paths.toList(), dest);
      _toast('已移动');
      _load();
    } catch (e) {
      _toast('移动失败: $e');
    }
  }

  Future<void> _deleteFiles(Set<String> paths) async {
    final ok = await confirmMiuix(
      context,
      title: '删除 ${paths.length} 项',
      content: '删除后将移入百度网盘回收站，确定吗？',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true) return;
    try {
      await _client.deleteFiles(paths.toList());
      _toast('已删除');
      _load();
      if (mounted) {
        setState(() {
          _selectMode = false;
          _selected.clear();
        });
      }
    } catch (e) {
      _toast('删除失败: $e');
    }
  }

  Future<void> _createFolder() async {
    final name = await miuixInputDialog(
      context,
      title: '新建文件夹',
      hint: '文件夹名称',
      confirmText: '创建',
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final parent = _dir == '/' ? '' : _dir;
    try {
      await _client.createFolder('$parent/$trimmed');
      _toast('已创建');
      _load();
    } catch (e) {
      _toast('创建失败: $e');
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '百度网盘',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceContainer,
              size: 20),
        ),
        actions: [
          MiuixIconButton(
              onPressed: _search,
              child: MiuixIcon(icon: Icons.search_rounded, tint: colors.primary)),
          MiuixIconButton(
              onPressed: _createFolder,
              child: MiuixIcon(
                  icon: Icons.create_new_folder_rounded, tint: colors.primary)),
          MiuixIconButton(
              onPressed: _showMoreMenu,
              child: MiuixIcon(
                  icon: Icons.more_vert_rounded, tint: colors.primary)),
        ],
      ),
      content: (padding) => SafeArea(
        child: !_state.isLoggedIn
            ? _buildLoginView(colors)
            : Column(
                children: [
                  _buildBreadcrumb(colors),
                  Expanded(child: _buildBody(colors)),
                  if (_selectMode) _buildSelectBar(colors, padding),
                ],
              ),
      ),
    );
  }

  Widget _buildLoginView(MiuixColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NetdiskTextBadge(text: '百度', size: 64),
          const SizedBox(height: 16),
          MiuixText('百度网盘（实验性）',
              color: colors.onSurfaceContainer, fontSize: 16),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: MiuixText(
              '在浏览器登录 pan.baidu.com 后，把 Cookie（至少含 BDUSS）'
              '粘贴进来即可。\n下载走 Gopeed 多线程，非会员账号有速度上限。',
              textAlign: TextAlign.center,
              color: colors.onSurfaceSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          MiuixButton(
            onPressed: _login,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: MiuixText('粘贴 Cookie 登录'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(MiuixColors colors) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _crumbs.length,
        separatorBuilder: (_, _) =>
            const Icon(Icons.chevron_right_rounded, size: 16),
        itemBuilder: (_, i) {
          final active = i == _crumbs.length - 1;
          return GestureDetector(
            onTap: () => _toBreadcrumb(i),
            child: Center(
              child: MiuixText(
                _crumbs[i].$2,
                fontSize: 13,
                maxLines: 1,
                color: active
                    ? colors.onSurfaceContainer
                    : colors.onSurfaceSecondary,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(MiuixColors colors) {
    if (_loading && _files.isEmpty) {
      return const Center(child: MiuixCircularProgressIndicator());
    }
    if (_error != null && _files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: MiuixText(_error!,
                  color: colors.onSurfaceSecondary,
                  fontSize: 13,
                  textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            MiuixButton(
              onPressed: _load,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: MiuixText('重试'),
              ),
            ),
          ],
        ),
      );
    }
    if (_files.isEmpty) {
      return const BodySwitcher(
          child: EmptyView(icon: Icons.folder_open_rounded, text: '这里空空如也'));
    }
    return BodySwitcher(
      child: MiuixPullToRefresh(
        isRefreshing: _loading,
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: _files.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => StaggeredFileItem(
              index: i, child: _buildFileTile(_files[i], colors)),
        ),
      ),
    );
  }

  Widget _buildFileTile(BaiduFile f, MiuixColors colors) {
    final selected = _selected.contains(f.path);
    return MiuixCard(
      onPressed: () {
        if (_selectMode) {
          _toggleSelect(f);
        } else if (f.isDir) {
          _enterDir(f);
        }
      },
      onLongPress: _selectMode
          ? null
          : () {
              if (f.isDir) {
                _enterSelectMode(f);
              } else {
                _showFileMenu(f);
              }
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            FileIcon(isDir: f.isDir, name: f.name, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: colors.onSurfaceContainer,
                    fontSize: 14,
                  ),
                  const SizedBox(height: 3),
                  MiuixText(
                    f.isDir ? '文件夹' : formatBytes(f.size),
                    color: colors.onSurfaceSecondary,
                    fontSize: 11,
                  ),
                ],
              ),
            ),
            if (_selectMode)
              MiuixIcon(
                icon: selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                tint: selected ? colors.primary : colors.onSurfaceSecondary,
                size: 22,
              )
            else
              MiuixIconButton(
                onPressed: () => _showFileMenu(f),
                child: MiuixIcon(
                    icon: Icons.more_vert_rounded,
                    tint: colors.onSurfaceSecondary,
                    size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectBar(MiuixColors colors, EdgeInsets padding) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(
            top: BorderSide(
                color: colors.onSurfaceSecondary.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          MiuixTextButton('取消', onPressed: _exitSelectMode),
          const Spacer(),
          MiuixText('已选 ${_selected.length} 项',
              color: colors.onSurfaceSecondary, fontSize: 12),
          const Spacer(),
          MiuixTextButton(
            '移动',
            onPressed:
                _selected.isEmpty ? null : () => _moveFiles(_selected.toSet()),
          ),
          const SizedBox(width: 8),
          MiuixTextButton(
            '删除',
            onPressed:
                _selected.isEmpty ? null : () => _deleteFiles(_selected.toSet()),
          ),
          const SizedBox(width: 8),
          MiuixTextButton(
            _busy ? '扫描中…' : '下载',
            onPressed: _busy ? null : _batchDownload,
          ),
        ],
      ),
    );
  }

  Future<void> _showMoreMenu() async {
    MiuixActionSheet.show<String>(context, title: '更多', actions: [
      (
        icon: Icons.login_rounded,
        text: _state.isLoggedIn ? '更换账号 Cookie' : '登录',
        value: 'login',
        color: null,
      ),
      (
        icon: Icons.logout_rounded,
        text: '退出登录',
        value: 'logout',
        color: AppColors.red,
      ),
    ]).then((v) async {
      switch (v) {
        case 'login':
          await _login();
        case 'logout':
          await _state.logout();
          if (mounted) {
            setState(() {
              _files = [];
              _error = '未登录';
            });
          }
      }
    });
  }
}
