import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../state/app_state.dart';
import '../../state/netdisk123_state.dart';
import '../../state/baidu_state.dart';
import '../../state/uc_state.dart';
import '../../utils/format.dart';
import '../../state/xunlei_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/miuix_common.dart';
import '../../widgets/netdisk_logo.dart';
import '../../widgets/storage_capacity.dart';
import '../login/login_page.dart';
import '../login/netdisk123_login_page.dart';
import '../login/xunlei_login_page.dart';
import 'drive_page.dart';
import 'netdisk123_accounts_page.dart';
import '../search/aggregate_search_page.dart';
import 'baidu_drive_page.dart';
import 'uc_drive_page.dart';
import 'xunlei_drive_page.dart';

class DriveHubPage extends StatelessWidget {
  const DriveHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, XunleiState.I, Netdisk123State.I, UcState.I, BaiduState.I]),
      builder: (context, _) {
        final colors = MiuixTheme.of(context).colors;
        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 20, 12),
                child: Row(
                  children: [
                    MiuixText('网盘',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurfaceContainer),
                    const Spacer(),
                    MiuixIconButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const AggregateSearchPage())),
                      child: MiuixIcon(
                          icon: Icons.travel_explore_rounded,
                          tint: colors.primary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _buildCapacitySummary(context),
                    const SizedBox(height: 14),
                    _buildQuarkCard(context),
                    const SizedBox(height: 14),
                    _buildXunleiCard(context),
                    const SizedBox(height: 14),
                    _buildNetdisk123Card(context),
                    _buildUcCard(context),
                    _buildBaiduCard(context),
                    const SizedBox(height: 20),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: MiuixText(
                        '更多网盘陆续接入中…',
                        color: colors.onSurfaceSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuarkCard(BuildContext context) {
    final app = AppState.I;
    final logged = app.isLoggedIn;
    final nickname = app.user?.nickname ?? '';
    return _DriveCard(
      iconWidget: const NetdiskLogo(
          provider: NetdiskProvider.quark, size: 52, radius: 14),
      title: '夸克网盘',
      subtitle: logged ? (nickname.isNotEmpty ? '$nickname · 已连接' : '已连接') : '未登录，点击登录',
      statusColor: logged ? AppColors.green : MiuixTheme.of(context).colors.onSurfaceSecondary,
      trailing: logged && app.user != null && app.user!.totalSize > 0
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StorageCapacityRow(totalSize: app.user!.totalSize, usedSize: app.user!.usedSize),
            )
          : null,
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage()));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DrivePage()));
      },
    );
  }

  Widget _buildXunleiCard(BuildContext context) {
    final x = XunleiState.I;
    final logged = x.isLoggedIn;
    final account = x.username ?? '';
    return _DriveCard(
      iconWidget: const NetdiskLogo(
          provider: NetdiskProvider.xunlei, size: 52, radius: 14),
      title: '迅雷云盘',
      subtitle: logged ? (account.isNotEmpty ? '$account · 已连接' : '已连接') : '未登录，点击登录',
      statusColor: logged ? AppColors.green : MiuixTheme.of(context).colors.onSurfaceSecondary,
      trailing: logged && x.hasQuota
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StorageCapacityRow(totalSize: x.totalSize, usedSize: x.usedSize),
            )
          : null,
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const XunleiLoginPage()));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const XunleiDrivePage()));
      },
      onLongPress: logged
          ? () async {
              final ok = await confirmMiuix(
                context,
                title: '退出迅雷云盘',
                content: '确定退出账号${account.isEmpty ? '' : '「$account」'}吗？',
                confirmText: '退出',
                danger: true,
              );
              if (ok == true) await XunleiState.I.logout();
            }
          : null,
    );
  }

  Widget _buildNetdisk123Card(BuildContext context) {
    final n = Netdisk123State.I;
    final logged = n.isLoggedIn;
    final count = n.accounts.length;
    final activeName = n.active?.username ?? n.username ?? '';
    final subtitle = !logged
        ? '未登录，点击登录'
        : count > 1
            ? '已登录 $count 个账号 · 点击选择账号进入'
            : (activeName.isNotEmpty ? '$activeName · 点击选择账号进入' : '已登录 · 点击选择账号');
    return _DriveCard(
      iconWidget: const NetdiskLogo(
          provider: NetdiskProvider.netdisk123, size: 52, radius: 14),
      title: '123 网盘',
      subtitle: subtitle,
      statusColor: logged ? AppColors.green : MiuixTheme.of(context).colors.onSurfaceSecondary,
      trailing: logged && n.hasQuota
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StorageCapacityRow(totalSize: n.totalSize, usedSize: n.usedSize),
            )
          : null,
      onTap: () {
        if (!logged) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123LoginPage()));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Netdisk123AccountsPage()));
      },
    );
  }

  Widget _buildBaiduCard(BuildContext context) {
    final b = BaiduState.I;
    final logged = b.isLoggedIn;
    return _DriveCard(
      iconWidget: const NetdiskTextBadge(
          text: '百度', color: Color(0xFF06A7FF), size: 52, radius: 14),
      title: '百度网盘',
      subtitle: logged
          ? (b.username.isNotEmpty ? '${b.username} · 点击进入' : '已登录 · 点击进入')
          : '未登录 · 实验性，Cookie 登录',
      statusColor:
          logged ? AppColors.green : MiuixTheme.of(context).colors.onSurfaceSecondary,
      onTap: () {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BaiduDrivePage()));
      },
    );
  }

  Widget _buildUcCard(BuildContext context) {
    final u = UcState.I;
    final logged = u.isLoggedIn;
    return _DriveCard(
      iconWidget: const NetdiskTextBadge(text: 'UC', size: 52, radius: 14),
      title: 'UC 网盘',
      subtitle: logged
          ? (u.user?.nickname.isNotEmpty == true
              ? '${u.user!.nickname} · 点击进入'
              : '已登录 · 点击进入')
          : '未登录 · 实验性，Cookie 登录',
      statusColor:
          logged ? AppColors.green : MiuixTheme.of(context).colors.onSurfaceSecondary,
      onTap: () {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const UcDrivePage()));
      },
    );
  }

  /// 聚合容量卡：展示已登录网盘的空间使用情况（有数据才显示行）
  Widget _buildCapacitySummary(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final rows = <Widget>[];
    void addRow(
        Widget logo, String name, String totalText, String usedText, int total, int used) {
      if (total <= 0) return;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            logo,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MiuixText(name,
                          fontSize: 12,
                          color: colors.onSurfaceContainer),
                      const Spacer(),
                      MiuixText('$usedText / $totalText',
                          fontSize: 11,
                          color: colors.onSurfaceSecondary),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: MiuixLinearProgressIndicator(
                      progress: used / total,
                      height: 4,
                      colors: MiuixProgressIndicatorColors(
                        foregroundColor: colors.primary,
                        disabledForegroundColor: colors.primary,
                        backgroundColor: colors.surfaceContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ));
    }

    final app = AppState.I;
    if (app.isLoggedIn && app.user != null && app.user!.totalSize > 0) {
      addRow(
        const NetdiskLogo(provider: NetdiskProvider.quark, size: 20, radius: 6),
        '夸克网盘',
        formatBytes(app.user!.totalSize),
        formatBytes(app.user!.usedSize),
        app.user!.totalSize,
        app.user!.usedSize,
      );
    }
    if (XunleiState.I.isLoggedIn && XunleiState.I.hasQuota) {
      addRow(
        const NetdiskLogo(provider: NetdiskProvider.xunlei, size: 20, radius: 6),
        '迅雷云盘',
        formatBytes(XunleiState.I.totalSize),
        formatBytes(XunleiState.I.usedSize),
        XunleiState.I.totalSize,
        XunleiState.I.usedSize,
      );
    }
    if (Netdisk123State.I.isLoggedIn && Netdisk123State.I.hasQuota) {
      addRow(
        const NetdiskLogo(
            provider: NetdiskProvider.netdisk123, size: 20, radius: 6),
        '123 网盘',
        formatBytes(Netdisk123State.I.totalSize),
        formatBytes(Netdisk123State.I.usedSize),
        Netdisk123State.I.totalSize,
        Netdisk123State.I.usedSize,
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return MiuixCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MiuixText('空间总览',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceContainer),
            const SizedBox(height: 4),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _DriveCard extends StatelessWidget {
  final Widget iconWidget;
  final String title;
  final String subtitle;
  final Color statusColor;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const _DriveCard({
    required this.iconWidget,
    required this.title,
    required this.subtitle,
    required this.statusColor,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final titleWidget = MiuixText(title,
        color: colors.onSurfaceContainer, fontSize: 16, fontWeight: FontWeight.w700);
    final subtitleWidget = MiuixText(subtitle,
        maxLines: 1, overflow: TextOverflow.ellipsis, color: statusColor, fontSize: 12);
    final iconBox = iconWidget;
    final chevron = MiuixIcon(
        icon: Icons.chevron_right_rounded,
        tint: colors.onSurfaceSecondary,
        size: 22);
    return MiuixCard(
      onPressed: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            iconBox,
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                titleWidget,
                const SizedBox(height: 4),
                subtitleWidget,
                if (trailing != null) ...[const SizedBox(height: 10), trailing!],
              ]),
            ),
            chevron,
          ],
        ),
      ),
    );
  }
}
