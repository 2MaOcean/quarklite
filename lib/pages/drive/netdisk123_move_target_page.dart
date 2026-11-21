import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../api/netdisk123_client.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/miuix_common.dart';

/// 123 网盘移动目标选择页：只展示文件夹，禁止进入被移动的文件夹内部，
/// 底部固定「移动到此处」按钮返回目标目录 id（根目录 id 为 '0'）。
class Netdisk123MoveTargetPage extends StatefulWidget {
  /// 被移动的文件 id 集合（含文件夹本身），用于禁止移入自身
  final Set<String> movedIds;

  /// 目录列表提供方
  final Future<List<Netdisk123File>> Function(String parentId) listDirs;

  const Netdisk123MoveTargetPage({
    super.key,
    required this.movedIds,
    required this.listDirs,
  });

  @override
  State<Netdisk123MoveTargetPage> createState() =>
      _Netdisk123MoveTargetPageState();
}

class _Netdisk123MoveTargetPageState extends State<Netdisk123MoveTargetPage> {
  String _parentId = Netdisk123Client.rootParentId;
  String _currentName = '全部文件';
  final List<(String, String)> _crumbs = [
    (Netdisk123Client.rootParentId, '全部文件'),
  ];
  List<Netdisk123File> _files = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await widget.listDirs(_parentId);
      if (mounted) {
        setState(() {
          _files = files.where((f) => f.isDir).toList();
          _loading = false;
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

  void _enterDir(Netdisk123File dir) {
    if (widget.movedIds.contains(dir.id)) return; // 禁止移入自身
    setState(() {
      _crumbs.add((_parentId, _currentName));
      _parentId = dir.id;
      _currentName = dir.name;
      _files = [];
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '选择移动目标',
        navigationIcon: MiuixIconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: MiuixIcon(
              icon: Icons.arrow_back_ios_new_rounded,
              tint: colors.onSurfaceContainer,
              size: 20),
        ),
      ),
      content: (padding) => Padding(
        padding: padding,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _crumbs.length; i++) ...[
                      if (i > 0)
                        MiuixIcon(
                            icon: Icons.chevron_right_rounded,
                            size: 16,
                            tint: colors.onSurfaceSecondary),
                      MiuixPressable(
                        onPressed: () {
                          if (i >= _crumbs.length - 1) return;
                          setState(() {
                            _crumbs.removeRange(i + 1, _crumbs.length);
                            _parentId = _crumbs.last.$1;
                          });
                          _load();
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          child: MiuixText(
                            _crumbs[i].$2,
                            fontSize: 13,
                            color: i == _crumbs.length - 1
                                ? colors.primary
                                : colors.onSurfaceSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(child: _buildBody(colors)),
            _buildBottomBar(colors, padding),
          ],
        ),
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
                color: colors.onSurfaceSecondary, fontSize: 13),
            const SizedBox(height: 12),
            MiuixTextButton('重试', onPressed: _load),
          ],
        ),
      );
    }
    if (_files.isEmpty) {
      return const EmptyView(
          icon: Icons.folder_open_rounded, text: '没有子文件夹');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _files.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final dir = _files[i];
        final blocked = widget.movedIds.contains(dir.id);
        return MiuixCard(
          onPressed: blocked ? null : () => _enterDir(dir),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FileIcon(isDir: true, name: dir.name, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: MiuixText(
                    dir.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: blocked
                        ? colors.onSurfaceSecondary
                        : colors.onSurfaceContainer,
                    fontSize: 14,
                  ),
                ),
                MiuixIcon(
                    icon: blocked
                        ? Icons.block_rounded
                        : Icons.chevron_right_rounded,
                    size: 18,
                    tint: colors.onSurfaceSecondary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(MiuixColors colors, EdgeInsets padding) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(
            top: BorderSide(color: colors.dividerLine, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: MiuixButton(
            onPressed: () => Navigator.pop(context, _parentId),
            colors: MiuixButtonColors(
              color: colors.primary,
              disabledColor: colors.primaryVariant,
              contentColor: Colors.white,
              disabledContentColor: Colors.white,
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: MiuixText('移动到此处', color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }
}
