import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../core/gopeed/gopeed_client.dart';
import '../../core/gopeed/port_scanner.dart';
import '../../core/gopeed/remote_config.dart';
import '../../core/notify/download_notifier.dart';
import '../../core/update_checker.dart';
import '../../state/app_state.dart';
import '../../state/netdisk123_state.dart';
import '../../state/upload_manager.dart';
import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../widgets/miuix_common.dart';
import '../../widgets/netdisk_logo.dart';
import '../../widgets/storage_capacity.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, XunleiState.I, Netdisk123State.I]),
      builder: (context, _) {
        final app = AppState.I;
        final colors = MiuixTheme.of(context).colors;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: MiuixText('我的',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurfaceContainer),
              ),
              _buildAccountCard(context, app),
              const SizedBox(height: 16),
              _buildSettingsCard(context, app),
              const SizedBox(height: 16),
              _buildAboutCard(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccountCard(BuildContext context, AppState app) {
    return MiuixCard(
      child: Column(
        children: [
          _buildAccountRow(
            context: context,
            icon: const NetdiskLogo(provider: NetdiskProvider.quark),
            title: '夸克网盘',
            subtitle: app.isLoggedIn
                ? (app.user?.nickname.isNotEmpty == true
                    ? app.user!.nickname
                    : '已登录')
                : '未登录，请到「网盘」页登录',
            capability: app.isLoggedIn &&
                    app.user != null &&
                    app.user!.totalSize > 0
                ? StorageCapacityRow(
                    totalSize: app.user!.totalSize,
                    usedSize: app.user!.usedSize,
                  )
                : null,
            trailing: app.isLoggedIn
                ? _LogoutButton(
                    onPressed: () => _confirmLogout(context, '夸克网盘',
                        () => app.logout()),
                  )
                : null,
          ),
          const MiuixHorizontalDivider(),
          _buildAccountRow(
            context: context,
            icon: const NetdiskLogo(provider: NetdiskProvider.xunlei),
            title: '迅雷云盘',
            subtitle: XunleiState.I.isLoggedIn
                ? (XunleiState.I.username?.isNotEmpty == true
                    ? XunleiState.I.username!
                    : '已登录')
                : '未登录，请到「网盘」页登录',
            capability: XunleiState.I.isLoggedIn && XunleiState.I.hasQuota
                ? StorageCapacityRow(
                    totalSize: XunleiState.I.totalSize,
                    usedSize: XunleiState.I.usedSize,
                  )
                : null,
            trailing: XunleiState.I.isLoggedIn
                ? _LogoutButton(
                    onPressed: () => _confirmLogout(context, '迅雷云盘',
                        () => XunleiState.I.logout()),
                  )
                : null,
          ),
          const MiuixHorizontalDivider(),
          _buildAccountRow(
            context: context,
            icon: const NetdiskLogo(provider: NetdiskProvider.netdisk123),
            title: '123 网盘',
            subtitle: Netdisk123State.I.isLoggedIn
                ? (Netdisk123State.I.username?.isNotEmpty == true
                    ? Netdisk123State.I.username!
                    : '已登录')
                : '未登录，请到「网盘」页登录',
            capability: Netdisk123State.I.isLoggedIn && Netdisk123State.I.hasQuota
                ? StorageCapacityRow(
                    totalSize: Netdisk123State.I.totalSize,
                    usedSize: Netdisk123State.I.usedSize,
                  )
                : null,
            trailing: Netdisk123State.I.isLoggedIn
                ? _LogoutButton(
                    onPressed: () => _confirmLogout(context, '123 网盘',
                        () => Netdisk123State.I.logout()),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRow({
    required BuildContext context,
    required Widget icon,
    required String title,
    required String subtitle,
    Widget? capability,
    Widget? trailing,
  }) {
    final colors = MiuixTheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MiuixText(title,
                    color: colors.onSurfaceContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
                const SizedBox(height: 2),
                MiuixText(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: colors.onSurfaceSecondary,
                    fontSize: 12),
                if (capability != null) ...[
                  const SizedBox(height: 10),
                  capability,
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Future<void> _confirmLogout(
      BuildContext context, String name, Future<void> Function() action) async {
    final ok = await confirmMiuix(context, title: '退出$name', content: '确定退出登录吗？', confirmText: '退出', danger: true);
    if (ok == true) {
      await action();
    }
  }

  Widget _buildSettingsCard(BuildContext context, AppState app) {
    final isIOS = !kIsWeb && Platform.isIOS;
    Widget leading(IconData icon) => MiuixIcon(
        icon: icon,
        size: 22,
        tint: MiuixTheme.of(context).colors.primary);
    Widget arrowPref({
      required String title,
      required String summary,
      required IconData icon,
      required VoidCallback onClick,
    }) =>
        MiuixArrowPreference(
          title: title,
          summary: summary,
          startAction: leading(icon),
          insideMargin:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          onClick: onClick,
        );
    return MiuixCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          arrowPref(
              title: '外观模式',
              summary: _themeModeLabel(app.themeMode),
              icon: Icons.dark_mode_rounded,
              onClick: () => _editThemeMode(context, app)),
          const MiuixHorizontalDivider(),
          arrowPref(
            title: '下载目录',
            summary: isIOS
                ? '文件 App / 我的 iPhone / Quarklite'
                : app.downloadDir,
            icon: Icons.folder_rounded,
            onClick: isIOS
                ? () => MiuixToast.show('iOS 下载文件可在“文件”App中查看')
                : () => _editDownloadDir(context, app),
          ),
          if (isIOS) ...[
            const MiuixHorizontalDivider(),
            arrowPref(
              title: 'iOS 后台下载',
              summary: app.gopeedRemoteEnabled
                  ? '已切换为远程 Gopeed 下载'
                  : '系统 URLSession 后台下载，可暂停恢复',
              icon: Icons.speed_rounded,
              onClick: () => MiuixToast.show('切换应用或锁屏后，系统仍可继续下载'),
            ),
            const MiuixHorizontalDivider(),
            arrowPref(
              title: '发送到 Gopeed',
              summary: app.gopeedRemoteEnabled
                  ? '已开启 · ${app.gopeedRemoteHost}:${app.gopeedRemotePort}'
                  : '关闭 · 把下载直链发送到设备上的 Gopeed',
              icon: Icons.send_rounded,
              onClick: () => _editRemoteGopeed(context),
            ),
          ] else ...[
            const MiuixHorizontalDivider(),
            arrowPref(
                title: '夸克下载线程',
                summary: '单任务最大 ${app.connections} 线程',
                icon: Icons.speed_rounded,
                onClick: () => _editConnections(context, app)),
            const MiuixHorizontalDivider(),
            arrowPref(
                title: '迅雷下载线程',
                summary: '单任务最大 ${app.xunleiConnections} 线程',
                icon: Icons.bolt_rounded,
                onClick: () => _editXunleiConnections(context, app)),
            const MiuixHorizontalDivider(),
            arrowPref(
                title: '123下载线程',
                summary: '单任务最大 ${app.netdisk123Connections} 线程',
                icon: Icons.cloud_upload_rounded,
                onClick: () => _editNetdisk123Connections(context, app)),
          ],
          const MiuixHorizontalDivider(),
          arrowPref(
              title: '同时下载任务数',
              summary: '最多 ${app.maxRunning} 个任务并发，其余排队',
              icon: Icons.low_priority_rounded,
              onClick: () => _editMaxRunning(context, app)),
          const MiuixHorizontalDivider(),
          arrowPref(
              title: '上传并行数',
              summary: '同时上传 ${app.uploadParallelism} 个文件',
              icon: Icons.cloud_upload_rounded,
              onClick: () => _editUploadParallelism(context, app)),
          if (!isIOS) ...[
            const MiuixHorizontalDivider(),
            arrowPref(
                title: '连接预算',
                summary: '所有任务总连接数上限 ${app.connectionBudget}，防系统卡顿',
                icon: Icons.tune_rounded,
                onClick: () => _editConnectionBudget(context, app)),
            const MiuixHorizontalDivider(),
            arrowPref(
                title: '存储权限',
                summary: '访问下载目录所需权限',
                icon: Icons.storage_rounded,
                onClick: () => app.openAllFilesAccess()),
          ],
          const MiuixHorizontalDivider(),
          arrowPref(
              title: '检查更新',
              summary: '检查 GitHub Release 是否有新版本',
              icon: Icons.system_update_rounded,
              onClick: () =>
                  UpdateChecker.checkAndPrompt(context, manual: true)),
          if (!kIsWeb && Platform.isWindows) ...[
            const MiuixHorizontalDivider(),
            arrowPref(
                title: '关闭窗口时',
                summary: _closeActionLabel(app.closeAction),
                icon: Icons.close_fullscreen_rounded,
                onClick: () => _editCloseAction(context, app)),
          ],
        ],
      ),
    );
  }

    String _themeModeLabel(String mode) {
    switch (mode) {
      case 'light':
        return '浅色';
      case 'dark':
        return '深色';
      default:
        return '跟随系统';
    }
  }

  void _editThemeMode(BuildContext context, AppState app) {
    final options = <(String, String)>[
      ('system', '跟随系统'),
      ('light', '浅色'),
      ('dark', '深色'),
    ];
    miuixChoiceDialog<String>(
      context,
      title: '外观模式',
      options: options.map((e) => e.$1).toList(),
      current: app.themeMode,
      labelOf: (v) => options.firstWhere((e) => e.$1 == v).$2,
    ).then((v) {
      if (v != null) app.setThemeMode(v);
    });
  }

  String _closeActionLabel(String action) {
    switch (action) {
      case 'minimize':
        return '最小化到托盘（后台继续下载）';
      case 'exit':
        return '直接退出';
      case 'ask':
        return '每次询问';
      default:
        return '首次询问后记住（默认）';
    }
  }

  void _editCloseAction(BuildContext context, AppState app) {
    final options = <(String, String)>[
      ('ask_once', '首次询问后记住（默认）'),
      ('minimize', '最小化到托盘（后台继续下载）'),
      ('exit', '直接退出'),
      ('ask', '每次询问'),
    ];
    miuixChoiceDialog<String>(
      context,
      title: '关闭窗口时',
      options: options.map((e) => e.$1).toList(),
      current: app.closeAction,
      labelOf: (v) => options.firstWhere((e) => e.$1 == v).$2,
    ).then((v) {
      if (v != null) app.setCloseAction(v);
    });
  }

  Widget _buildAboutCard(BuildContext context) {
    Widget leading(IconData icon) => MiuixIcon(icon: icon, size: 22, tint: MiuixTheme.of(context).colors.primary);
    return MiuixCard(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
          MiuixArrowPreference(title: '日志', summary: '查看/复制运行日志，排查下载问题', startAction: leading(Icons.bug_report_rounded), insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), onClick: () => _showLog(context)),
          const MiuixHorizontalDivider(),
          MiuixArrowPreference(title: '关于', summary: !kIsWeb && Platform.isIOS ? 'Quarklite v1.4.0  ·  iOS 原生后台下载器' : 'Quarklite v1.4.0  ·  基于 Gopeed 下载引擎', startAction: leading(Icons.info_outline_rounded), insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), onClick: () => _showAbout(context)),
        ]),
    );
  }

  Future<void> _showLog(BuildContext context) async {
    final path = await AppLogger.I.logPath();
    final content = await AppLogger.I.readLog();
    if (!context.mounted) return;
    await MiuixOverlayPanel.show(
      context: context,
      builder: (_) => _LogDialog(
        path: path,
        content: content,
        onOpenDir: () {
          final dir = path.contains(Platform.pathSeparator)
              ? path.substring(0, path.lastIndexOf(Platform.pathSeparator))
              : '.';
          try {
            Process.start('explorer.exe', [dir]);
          } catch (_) {}
          MiuixOverlayPanel.hide();
        },
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: content));
          MiuixOverlayPanel.hide();
          MiuixToast.show('日志已复制，请直接粘贴发送给开发者');
        },
      ),
    );
  }

  void _editDownloadDir(BuildContext context, AppState app) {
    miuixInputDialog(
      context,
      title: '下载目录',
      hint: '/storage/emulated/0/Download/Quarklite',
      initialText: app.downloadDir,
      confirmText: '保存',
    ).then((dir) async {
      if (dir == null) return;
      final trimmed = dir.trim();
      if (trimmed.isNotEmpty) {
        await app.setDownloadDir(trimmed);
      }
    });
  }

  void _editConnections(BuildContext context, AppState app) {
    final options = [64, 128, 256, 512, 1024];
    _showThreadPicker(
      context,
      title: '夸克下载线程',
      options: options,
      current: app.connections,
      unit: '线程',
      onPick: (n) => app.setConnections(n),
    );
  }

  void _editXunleiConnections(BuildContext context, AppState app) {
    final options = [16, 32, 64, 128, 256];
    _showThreadPicker(
      context,
      title: '迅雷下载线程',
      options: options,
      current: app.xunleiConnections,
      unit: '线程',
      onPick: (n) => app.setXunleiConnections(n),
    );
  }

  void _editNetdisk123Connections(BuildContext context, AppState app) {
    final options = [16, 32, 64, 128, 256];
    _showThreadPicker(
      context,
      title: '123下载线程',
      options: options,
      current: app.netdisk123Connections,
      unit: '线程',
      onPick: (n) => app.setNetdisk123Connections(n),
    );
  }

  /// 线程数选择弹窗：附性能提醒，让用户自行取舍
  void _showThreadPicker(
    BuildContext context, {
    required String title,
    required List<int> options,
    required int current,
    required String unit,
    required Future<void> Function(int) onPick,
  }) {
    miuixChoiceDialog<int>(
      context,
      title: title,
      options: options,
      current: current,
      labelOf: (n) => '$n $unit',
      hint: '线程数越高下载越快，但过高可能让性能较弱的设备卡顿；\n过低则速度偏慢。请按设备性能自行取舍。',
    ).then((n) {
      if (n != null) onPick(n);
    });
  }

  void _editMaxRunning(BuildContext context, AppState app) {
    miuixChoiceDialog<int>(
      context,
      title: '同时下载任务数',
      options: [1, 2, 3, 4, 6, 8],
      current: app.maxRunning,
      labelOf: (n) => '$n 个任务',
    ).then((n) {
      if (n != null) app.setMaxRunning(n);
    });
  }

  void _editUploadParallelism(BuildContext context, AppState app) {
    miuixChoiceDialog<int>(
      context,
      title: '上传并行数',
      options: [1, 2, 3, 4],
      current: app.uploadParallelism,
      labelOf: (n) => '同时上传 $n 个文件',
      hint: '并行数越高上传越快，但可能使页面卡顿或触发接口限流；\n默认为 1，请按网络与设备性能自行取舍。',
    ).then((n) {
      if (n != null) {
        app.setUploadParallelism(n);
        // 上传管理器立即获取新值（老的任务跑完按新并行数补充）
        UploadManager.I.overrideParallelism = 0;
      }
    });
  }

  void _editConnectionBudget(BuildContext context, AppState app) {
    miuixChoiceDialog<int>(
      context,
      title: '连接预算',
      options: [32, 64, 128, 256, 512],
      current: app.connectionBudget,
      labelOf: (n) => '$n 连接',
    ).then((n) {
      if (n != null) app.setConnectionBudget(n);
    });
  }

  /// 「发送到 Gopeed」远程转发配置弹窗
  void _editRemoteGopeed(BuildContext context) {
    MiuixOverlayPanel.show(
      context: context,
      builder: (_) => _RemoteGopeedDialog(initial: AppState.I.gopeedRemote),
    );
  }

  void _showAbout(BuildContext context) {
    final isIOS = !kIsWeb && Platform.isIOS;
    var capabilityText = '内置 Gopeed 多线程下载引擎\n'
        '· 支持分享链接解析 / 网盘直连 / BT 磁力';
    var platformText = '实时动态: 未查询';

    if (isIOS) {
      capabilityText = AppState.I.gopeedRemoteEnabled
          ? '已开启「发送到 Gopeed」远程转发\n'
              '· 直链与 BT 磁力由远程 Gopeed 下载\n'
              '· 任务列表显示远程 Gopeed 的任务'
          : '使用 iOS URLSession 原生后台下载器\n'
              '· 支持分享链接解析 / 网盘直连 / 暂停恢复\n'
              '· 开启「发送到 Gopeed」可转发直链与 BT 磁力';
      platformText = AppState.I.gopeedRemoteEnabled
          ? '下载位置: 远程 Gopeed 的下载目录'
          : '下载位置: 文件 App / 我的 iPhone / Quarklite';
    } else {
      final live = DownloadNotifier.liveUpdateStatus;
      if (live != null) {
        final sdk = live['sdk'];
        final supported = live['promotedSupported'] == true;
        final canPost = live['canPost'] == true;
        final promotable = live['promotable'] == true;
        if (!supported) {
          platformText = '实时动态: 需要 Android 16+（当前 $sdk）';
        } else if (!canPost) {
          platformText = '实时动态: 未启用（请在系统设置中开启）';
        } else if (promotable) {
          platformText = '实时动态: 已就绪（Android $sdk）';
        } else {
          platformText = '实时动态: 不满足条件（${live['reason'] ?? '未知'}）';
        }
      }
    }
    confirmMiuix(
      context,
      title: 'Quarklite',
      content: '夸克网盘不限速下载工具\n\n'
          '· $capabilityText\n'
          '· $platformText\n'
          '· 本项目基于 GPL-3.0 协议开源\n\n'
          'v1.4.0',
      confirmText: '关闭',
    );
  }
}

/// 账号行右侧的「退出」小按钮
class _LogoutButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _LogoutButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return MiuixPressable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(8),
      feedbackType: MiuixPressFeedbackType.sink,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiuixIcon(icon: Icons.logout_rounded, tint: AppColors.red, size: 14),
            const SizedBox(width: 4),
            MiuixText('退出', color: AppColors.red, fontSize: 12),
          ],
        ),
      ),
    );
  }
}

/// 运行日志展示对话框（MiuixOverlayDialog 包裹在 Navigator 弹层中）
class _LogDialog extends StatefulWidget {
  final String path;
  final String content;
  final VoidCallback onOpenDir;
  final VoidCallback onCopy;

  const _LogDialog({
    super.key,
    required this.path,
    required this.content,
    required this.onOpenDir,
    required this.onCopy,
  });

  @override
  State<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<_LogDialog> {
  void _close() => MiuixOverlayPanel.hide();

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final content = widget.content.length > 3000
        ? '…${widget.content.substring(widget.content.length - 3000)}'
        : widget.content;
    return MiuixOverlayDialog(
      show: true,
      title: '运行日志',
      onDismissRequest: _close,
      content: MiuixDismissScope(
        onDismissRequest: _close,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                MiuixText('日志文件位置：',
                    color: colors.onSurfaceSecondary, fontSize: 12),
                SelectableText(
                  widget.path,
                  style: TextStyle(
                      fontSize: 12,
                      color: colors.primary,
                      decoration: TextDecoration.none),
                ),
                const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 200,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  content,
                  style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceSecondary,
                      height: 1.5,
                      decoration: TextDecoration.none),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!kIsWeb && Platform.isWindows)
                    MiuixTextButton(
                      '打开目录',
                      onPressed: widget.onOpenDir,
                      colors: MiuixButtonColors(color: colors.primary, disabledColor: colors.primary, contentColor: Colors.white, disabledContentColor: Colors.white),
                    ),
                  const SizedBox(width: 8),
                  MiuixTextButton(
                    '关闭',
                    onPressed: _close,
                    colors: MiuixButtonColors(color: colors.onSurfaceSecondary, disabledColor: colors.onSurfaceSecondary, contentColor: Colors.white, disabledContentColor: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  MiuixTextButton(
                    '复制日志',
                    onPressed: widget.onCopy,
                    colors: MiuixButtonColors(color: colors.primary, disabledColor: colors.primary, contentColor: Colors.white, disabledContentColor: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「发送到 Gopeed」配置弹窗。
///
/// 默认目标是设备上安装的 Gopeed iOS 版：其内核监听 127.0.0.1 的
/// 随机端口（设置里不可修改），通过「扫描端口」自动发现；扫描命中后
/// 下载直链经 REST API 发送过去，并附带夸克的 Cookie/Referer 请求头。
/// 也支持填写局域网电脑 / NAS 上 Gopeed 的地址实现远程下载。
class _RemoteGopeedDialog extends StatefulWidget {
  final RemoteGopeedConfig initial;

  const _RemoteGopeedDialog({super.key, required this.initial});

  @override
  State<_RemoteGopeedDialog> createState() => _RemoteGopeedDialogState();
}

class _RemoteGopeedDialogState extends State<_RemoteGopeedDialog> {
  late bool _enabled = widget.initial.enabled;
  late final TextEditingController _host = TextEditingController(
      text: widget.initial.host.isEmpty
          ? RemoteGopeedConfig.localHost
          : widget.initial.host);
  late final TextEditingController _port = TextEditingController(
      text: widget.initial.port > 0 ? '${widget.initial.port}' : '');
  late final TextEditingController _token =
      TextEditingController(text: widget.initial.token);
  late final TextEditingController _dir =
      TextEditingController(text: widget.initial.dir);
  bool _testing = false;
  bool _scanning = false;
  String _scanHint = '';

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    _dir.dispose();
    super.dispose();
  }

  RemoteGopeedConfig _collect() => RemoteGopeedConfig(
        enabled: _enabled,
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 0,
        token: _token.text.trim(),
        dir: _dir.text.trim(),
      );

  void _close() => MiuixOverlayPanel.hide();

  /// 扫描本机回环端口，自动发现 Gopeed iOS 版的 REST 端口。
  /// 扫描前请确保 Gopeed 已启动（前台或刚切后台）。
  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanHint = '正在扫描，请保持 Gopeed 处于打开状态…';
    });
    try {
      final port = await GopeedPortScanner.scan(
        onProgress: (scanned, total) {
          if (mounted && _scanning) {
            setState(() => _scanHint = '正在扫描… $scanned/$total');
          }
        },
      );
      if (!mounted) return;
      if (port != null) {
        setState(() {
          _port.text = '$port';
          _scanHint = '已发现 Gopeed（端口 $port）';
        });
        MiuixToast.show('已找到 Gopeed，端口 $port');
      } else {
        setState(() => _scanHint = '未找到 Gopeed：请先打开 Gopeed 再扫描');
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// 测试 Gopeed 连通性（GET /info，带令牌）
  Future<void> _test() async {
    final cfg = _collect();
    if (cfg.host.isEmpty) {
      MiuixToast.show('请先填写 Gopeed 地址');
      return;
    }
    if (cfg.port <= 0) {
      MiuixToast.show('请先点「扫描端口」获取端口');
      return;
    }
    setState(() => _testing = true);
    try {
      final client = GopeedClient(cfg.baseUrl, apiToken: cfg.token);
      final info = await client.info();
      final ver = info['version']?.toString() ?? '';
      MiuixToast.show('连接成功${ver.isEmpty ? '' : ' · Gopeed $ver'}');
    } catch (e) {
      MiuixToast.show('连接失败：请确认 Gopeed 正在运行，且地址 / 端口正确\n$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final cfg = _collect();
    if (cfg.enabled && (cfg.host.isEmpty || cfg.port <= 0)) {
      MiuixToast.show('开启前请先扫描到 Gopeed 端口（或手动填写地址端口）');
      return;
    }
    await AppState.I.setGopeedRemote(cfg);
    if (!mounted) return;
    _close();
    MiuixToast.show(cfg.isActive
        ? '已开启，直链将发送到 ${cfg.baseUrl}'
        : '已关闭，使用本机下载');
  }

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    return MiuixOverlayDialog(
      show: true,
      title: '发送到 Gopeed',
      onDismissRequest: _close,
      content: MiuixDismissScope(
        onDismissRequest: _close,
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MiuixText(
                  '把网盘下载直链发送到设备上安装的 Gopeed（iOS 版），'
                  '由它多线程下载；文件保存在 Gopeed 里，需在 Gopeed 内'
                  '查看。开启后本机不再下载文件。',
                  color: colors.onSurfaceSecondary,
                  fontSize: 12,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: MiuixText('启用转发',
                          color: colors.onSurfaceContainer, fontSize: 14),
                    ),
                    MiuixSwitch(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                MiuixTextField(
                  controller: _host,
                  label: 'Gopeed 地址（本机默认 127.0.0.1）',
                  useLabelAsPlaceholder: true,
                  singleLine: true,
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: MiuixTextField(
                        controller: _port,
                        label: '端口（Gopeed iOS 每次启动随机）',
                        useLabelAsPlaceholder: true,
                        singleLine: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MiuixTextButton(
                      _scanning ? '扫描中…' : '扫描端口',
                      onPressed: _scanning ? null : _scan,
                      insideMargin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ],
                ),
                if (_scanHint.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  MiuixText(_scanHint,
                      color: colors.onSurfaceSecondary, fontSize: 11),
                ],
                const SizedBox(height: 10),
                MiuixTextField(
                  controller: _token,
                  label: 'API 令牌（Gopeed 未设置令牌则留空）',
                  useLabelAsPlaceholder: true,
                  singleLine: true,
                ),
                const SizedBox(height: 10),
                MiuixTextField(
                  controller: _dir,
                  label: '下载目录（留空用 Gopeed 默认目录）',
                  useLabelAsPlaceholder: true,
                  singleLine: true,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    MiuixTextButton(
                      _testing ? '测试中…' : '测试连接',
                      onPressed: _testing ? null : _test,
                      insideMargin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    const Spacer(),
                    MiuixTextButton(
                      '取消',
                      onPressed: _close,
                      insideMargin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    const SizedBox(width: 8),
                    MiuixTextButton(
                      '保存',
                      onPressed: _save,
                      colors: MiuixButtonColors(
                          color: colors.primary,
                          disabledColor: colors.primary,
                          contentColor: Colors.white,
                          disabledContentColor: Colors.white),
                      insideMargin: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
