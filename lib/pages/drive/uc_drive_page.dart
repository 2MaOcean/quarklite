import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../api/quark_client.dart';
import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../state/uc_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/file_list_anim.dart';
import '../../widgets/miuix_common.dart';
import '../../widgets/netdisk_logo.dart';
import 'move_target_page.dart';

/// UC 网盘文件浏览页（实验性）：面包屑导航 + 多选下载 + 文件管理操作。
///
/// UC 网盘与夸克同 API 家族，登录采用网页 Cookie 粘贴。
class UcDrivePage extends StatefulWidget {
  const UcDrivePage({super.key});

  @override
  State<UcDrivePage> createState() => _UcDrivePageState();
}

class _UcDrivePageState extends State<UcDrivePage> {
  static const _rootFid = '0';

  List<QuarkFile> _files = [];
  String _parentId = _rootFid;
  String _currentName = '全部文件';
  final List<(String, String)> _crumbs = [(_rootFid, '全部文件')];
  bool _loading = false;
  String? _error;

  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _busy = false;

  UcState get _state => UcState.I;
  QuarkClient get _client => _state.client;

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
      final files = await _client.listFiles(_parentId);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      AppLogger.I.e('uc', '文件列表失败: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _enterDir(QuarkFile dir) {
    setState(() {
      _crumbs.add((_parentId, _currentName));
      _parentId = dir.fid;
      _currentName = dir.fileName;
      _files = [];
      _selectMode = false;
      _selected.clear();
      _loading = true;
    });
    _load();
  }

  void _toBreadcrumb(int index) {
    if (index >= _crumbs.length - 1) return;
    setState(() {
      _crumbs.removeRange(index + 1, _crumbs.length);
      _parentId = _crumbs.last.$1;
      _currentName = _crumbs.last.$2;
      _files = [];
      _error = null;
      _selectMode = false;
      _selected.clear();
      _loading = true;
    });
    _load();
  }

  void _toast(String msg) => MiuixToast.show(msg);

  // ---------------- 登录 ----------------

  Future<void> _login() async {
    final cookie = await miuixInputDialog(
      context,
      title: 'UC 网盘 Cookie 登录',
      hint: '粘贴浏览器登录 pan.uc.cn 后的 Cookie',
      confirmText: '登录',
    );
    if (cookie == null || cookie.trim().isEmpty) return;
    final err = await _state.login(cookie.trim());
    if (!mounted) return;
    if (err != null) {
      _toast('登录失败：$err\n请确认 Cookie 来自已登录的 pan.uc.cn');
      return;
    }
    _toast('登录成功');
    _load();
  }

  // ---------------- 搜索 ----------------

  Future<void> _search() async {
    final kw = await miuixInputDialog(
      context,
      title: '搜索 UC 网盘',
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
      final files = await _client.searchFiles(kw.trim());
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

  void _enterSelectMode(QuarkFile file) {
    setState(() {
      _selectMode = true;
      _selected.add(file.fid);
    });
  }

  void _toggleSelect(QuarkFile file) {
    setState(() {
      if (!_selected.remove(file.fid)) {
        _selected.add(file.fid);
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
          _files.where((f) => _selected.contains(f.fid)).toList();
      final items = await _expandSelection(targets, '');
      if (items.isEmpty) {
        _toast('没有可下载的文件');
        return;
      }
      var added = 0;
      final base = await AppState.I.effectiveDownloadDir();
      for (final (f, rel) in items) {
        try {
          final (infos, cookie) = await _client.getDownloadInfo([f.fid]);
          if (infos.isEmpty || infos.first.url.isEmpty) continue;
          final path = rel.isEmpty ? base : '$base/$rel';
          final err = await DownloadService.addDirectUrl(
            url: infos.first.url,
            fileName: infos.first.fileName.isNotEmpty
                ? infos.first.fileName
                : f.fileName,
            cookie: cookie,
            path: path,
            batchTotal: items.length,
            referer: 'https://pan.uc.cn/',
            userAgent: QuarkClient.uaPc,
          );
          if (err == null) added++;
        } catch (e) {
          AppLogger.I.e('uc', '取直链失败 ${f.fileName}: $e');
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
  Future<List<(QuarkFile, String)>> _expandSelection(
      List<QuarkFile> selected, String relBase) async {
    final result = <(QuarkFile, String)>[];
    for (final f in selected) {
      if (f.isDir) {
        final children = await _client.listFiles(f.fid);
        result.addAll(await _expandSelection(children, '$relBase${f.fileName}/'));
      } else {
        result.add((f, relBase));
      }
    }
    return result;
  }

  // ---------------- 文件操作 ----------------

  void _showFileMenu(QuarkFile file) {
    MiuixActionSheet.show<String>(context, title: file.fileName, actions: [
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
          await _moveFiles({file.fid});
        case 'delete':
          await _deleteFiles({file.fid});
      }
    });
  }

  Future<void> _downloadSingle(QuarkFile file) async {
    try {
      final (infos, cookie) = await _client.getDownloadInfo([file.fid]);
      if (infos.isEmpty) {
        _toast('未获取到下载地址');
        return;
      }
      final base = await AppState.I.effectiveDownloadDir();
      final err = await DownloadService.addDirectUrl(
        url: infos.first.url,
        fileName: infos.first.fileName.isNotEmpty
            ? infos.first.fileName
            : file.fileName,
        cookie: cookie,
        path: base,
        referer: 'https://pan.uc.cn/',
        userAgent: QuarkClient.uaPc,
      );
      if (err != null) throw Exception(err);
      _toast('已加入下载队列');
      DownloadManager.I.startPolling();
    } catch (e) {
      _toast('下载失败: $e');
    }
  }

  Future<void> _renameFile(QuarkFile file) async {
    final name = await miuixInputDialog(
      context,
      title: '重命名',
      hint: '新名称',
      initialText: file.fileName,
      confirmText: '保存',
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == file.fileName) return;
    try {
      await _client.renameFile(file.fid, trimmed);
      _toast('已重命名');
      _load();
    } catch (e) {
      _toast('重命名失败: $e');
    }
  }

  Future<void> _moveFiles(Set<String> fids) async {
    final toFid = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MoveTargetPage(
          movedFids: fids,
          listDirs: (fid) => _client.listFiles(fid),
        ),
      ),
    );
    if (toFid == null || !mounted) return;
    try {
      await _client.moveFiles(fids.toList(), toFid);
      _toast('已移动');
      _load();
    } catch (e) {
      _toast('移动失败: $e');
    }
  }

  Future<void> _deleteFiles(Set<String> fids) async {
    final ok = await confirmMiuix(
      context,
      title: '删除 ${fids.length} 项',
      content: '删除后将移入 UC 网盘回收站，确定吗？',
      confirmText: '删除',
      danger: true,
    );
    if (ok != true) return;
    try {
      await _client.deleteFiles(fids.toList());
      _toast('已删除');
      _load();
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
    try {
      await _client.createFolder(_parentId, trimmed);
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
        title: 'UC 网盘',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: MiuixTheme.of(context).colors.onSurfaceContainer,
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
                  if (_selectMode)
                    _buildSelectBar(colors, padding),
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
          const NetdiskTextBadge(text: 'UC', size: 64),
          const SizedBox(height: 16),
          MiuixText('UC 网盘（实验性）',
              color: colors.onSurfaceContainer, fontSize: 16),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: MiuixText(
              '在电脑或手机浏览器登录 pan.uc.cn 后，'
              '把 Cookie 粘贴进来即可使用。\n接口与夸克同族，'
              '若遇到异常请反馈。',
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
            MiuixText(_error!,
                color: colors.onSurfaceSecondary,
                fontSize: 13,
                textAlign: TextAlign.center),
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
          itemBuilder: (_, i) =>
              StaggeredFileItem(index: i, child: _buildFileTile(_files[i], colors)),
        ),
      ),
    );
  }

  Widget _buildFileTile(QuarkFile f, MiuixColors colors) {
    final selected = _selected.contains(f.fid);
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
              if (f.isDir && !_selectMode) {
                _enterSelectMode(f);
              } else {
                _showFileMenu(f);
              }
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            FileIcon(isDir: f.isDir, name: f.fileName, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(
                    f.fileName,
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
            else if (!f.isDir)
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
            top: BorderSide(color: colors.onSurfaceSecondary.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          MiuixTextButton('取消', onPressed: _exitSelectMode),
          const Spacer(),
          MiuixText('已选 ${_selected.length} 项',
              color: colors.onSurfaceSecondary, fontSize: 12),
          const Spacer(),
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
