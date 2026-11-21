import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../api/baidu_client.dart';
import '../../api/quark_client.dart';
import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/baidu_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../state/uc_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/miuix_common.dart';
import '../../widgets/netdisk_logo.dart';

/// 跨网盘聚合搜索：并行搜索已登录的夸克 / UC / 123 / 百度网盘，
/// 结果按网盘分组展示，文件可直接加入下载队列。
class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({super.key});

  @override
  State<AggregateSearchPage> createState() => _AggregateSearchPageState();
}

class _Hit {
  final NetdiskProvider provider;
  final String name;
  final bool isDir;
  final int size;
  final Future<String?> Function() download;

  _Hit({
    required this.provider,
    required this.name,
    required this.isDir,
    required this.size,
    required this.download,
  });
}

class _AggregateSearchPageState extends State<AggregateSearchPage> {
  final TextEditingController _kw = TextEditingController();
  bool _searching = false;
  String? _error;
  final Map<NetdiskProvider, List<_Hit>> _hits = {};
  final Set<String> _busyKeys = {};

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  void _toast(String msg) => MiuixToast.show(msg);

  Future<void> _run() async {
    final keyword = _kw.text.trim();
    if (keyword.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _error = null;
      _hits.clear();
    });

    final tasks = <Future<void> Function()>[];

    if (AppState.I.isLoggedIn) {
      tasks.add(() async {
        final files = await AppState.I.quark.searchFiles(keyword);
        _hits[NetdiskProvider.quark] = [
          for (final f in files)
            if (!f.isDir)
              _Hit(
                provider: NetdiskProvider.quark,
                name: f.fileName,
                isDir: false,
                size: f.size,
                download: () => _downloadQuark(f.fid, f.fileName),
              ),
        ];
      });
    }

    if (UcState.I.isLoggedIn) {
      tasks.add(() async {
        final files = await UcState.I.client.searchFiles(keyword);
        _hits[NetdiskProvider.uc] = [
          for (final f in files)
            if (!f.isDir) _hitForUc(f),
        ];
      });
    }

    if (BaiduState.I.isLoggedIn) {
      tasks.add(() async {
        final files = await BaiduState.I.client.search(keyword);
        _hits[NetdiskProvider.baidu] = [
          for (final f in files)
            if (!f.isDir) _hitForBaidu(f),
        ];
      });
    }

    await Future.wait(tasks.map((t) async {
      try {
        await t();
      } catch (e) {
        AppLogger.I.w('search', '分区搜索失败: $e');
      }
    }).toList());

    if (!mounted) return;
    setState(() {
      _searching = false;
      _hits.removeWhere((_, v) => v.isEmpty);
    });
  }

  _Hit _hitForUc(QuarkFile f) {
    return _Hit(
      provider: NetdiskProvider.uc,
      name: f.fileName,
      isDir: false,
      size: f.size,
      download: () => _downloadQuarkLike(
        UcState.I.client,
        f.fid,
        f.fileName,
        referer: 'https://pan.uc.cn/',
        userAgent: QuarkClient.uaPc,
      ),
    );
  }

  _Hit _hitForBaidu(BaiduFile f) {
    return _Hit(
      provider: NetdiskProvider.baidu,
      name: f.name,
      isDir: false,
      size: f.size,
      download: () async {
        final url = await BaiduState.I.client.downloadUrl(f.path);
        final base = await AppState.I.effectiveDownloadDir();
        return DownloadService.addDirectUrl(
          url: url,
          fileName: f.name,
          cookie: BaiduState.I.client.cookie,
          path: base,
          referer: 'https://pan.baidu.com/',
          userAgent: BaiduClient.ua,
        );
      },
    );
  }

  Future<String?> _downloadQuark(String fid, String name) async {
    final (infos, cookie) = await AppState.I.quark.getDownloadInfo([fid]);
    if (infos.isEmpty) throw Exception('未获取到下载地址');
    final base = await AppState.I.effectiveDownloadDir();
    return DownloadService.addDirectUrl(
      url: infos.first.url,
      fileName:
          infos.first.fileName.isNotEmpty ? infos.first.fileName : name,
      cookie: cookie,
      path: base,
    );
  }

  Future<String?> _downloadQuarkLike(
    QuarkClient client,
    String fid,
    String name, {
    required String referer,
    required String userAgent,
  }) async {
    final (infos, cookie) = await client.getDownloadInfo([fid]);
    if (infos.isEmpty) throw Exception('未获取到下载地址');
    final base = await AppState.I.effectiveDownloadDir();
    return DownloadService.addDirectUrl(
      url: infos.first.url,
      fileName:
          infos.first.fileName.isNotEmpty ? infos.first.fileName : name,
      cookie: cookie,
      path: base,
      referer: referer,
      userAgent: userAgent,
    );
  }

  Future<void> _downloadHit(_Hit hit, String key) async {
    setState(() => _busyKeys.add(key));
    try {
      final err = await hit.download();
      if (!mounted) return;
      if (err == null) {
        _toast('已加入下载队列');
        DownloadManager.I.startPolling();
      } else {
        _toast(err);
      }
    } catch (e) {
      _toast('下载失败: $e');
    } finally {
      if (mounted) setState(() => _busyKeys.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '聚合搜索',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceContainer,
              size: 20),
        ),
      ),
      content: (padding) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: MiuixTextField(
                      controller: _kw,
                      label: '搜索已登录的网盘文件',
                      useLabelAsPlaceholder: true,
                      singleLine: true,
                      onSubmitted: (_) => _run(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MiuixButton(
                    onPressed: _searching ? null : _run,
                    colors: MiuixButtonColors(
                      color: colors.primary,
                      disabledColor: colors.primaryVariant,
                      contentColor: Colors.white,
                      disabledContentColor: Colors.white,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: _searching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: MiuixCircularProgressIndicator(
                                  colors: MiuixProgressIndicatorColors(
                                      foregroundColor: Colors.white)),
                            )
                          : const MiuixText('搜索',
                              color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(colors, padding)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(MiuixColors colors, EdgeInsets padding) {
    if (_searching) {
      return const Center(child: MiuixCircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyView(
          icon: Icons.cloud_off_rounded, text: '搜索失败', subText: _error);
    }
    if (_hits.isEmpty) {
      return const EmptyView(
          icon: Icons.search_rounded,
          text: '输入关键词开始搜索',
          subText: '同时搜索已登录的夸克 / UC / 123 / 百度网盘');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final entry in _hits.entries) ...[
          _buildSection(entry.key, entry.value, colors),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildSection(
      NetdiskProvider provider, List<_Hit> hits, MiuixColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (provider == NetdiskProvider.uc ||
                provider == NetdiskProvider.baidu)
              NetdiskTextBadge(
                text: provider == NetdiskProvider.uc ? 'UC' : '百度',
                color: provider == NetdiskProvider.uc
                    ? const Color(0xFFFF7A21)
                    : const Color(0xFF06A7FF),
                size: 22,
                radius: 6,
              )
            else
              NetdiskLogo(provider: provider, size: 22, radius: 6),
            const SizedBox(width: 8),
            MiuixText('${_providerName(provider)} · ${hits.length} 个结果',
                fontSize: 13, color: colors.onSurfaceSecondary),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < hits.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildHitTile(hits[i], '${provider.name}_$i', colors),
          ),
      ],
    );
  }

  String _providerName(NetdiskProvider p) {
    switch (p) {
      case NetdiskProvider.quark:
        return '夸克网盘';
      case NetdiskProvider.xunlei:
        return '迅雷云盘';
      case NetdiskProvider.netdisk123:
        return '123 网盘';
      case NetdiskProvider.uc:
        return 'UC 网盘';
      case NetdiskProvider.baidu:
        return '百度网盘';
    }
  }

  Widget _buildHitTile(_Hit hit, String key, MiuixColors colors) {
    final busy = _busyKeys.contains(key);
    return MiuixCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            FileIcon(isDir: hit.isDir, name: hit.name, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MiuixText(hit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      color: colors.onSurfaceContainer,
                      fontSize: 13),
                  const SizedBox(height: 2),
                  MiuixText(formatBytes(hit.size),
                      color: colors.onSurfaceSecondary, fontSize: 11),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MiuixTextButton(
              busy ? '…' : '下载',
              onPressed: busy ? null : () => _downloadHit(hit, key),
            ),
          ],
        ),
      ),
    );
  }
}
