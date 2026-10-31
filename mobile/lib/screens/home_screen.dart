import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/bottle_label.dart';
import '../services/api_service.dart';
import '../services/auth_storage.dart';
import '../services/geofence_monitor.dart';
import '../services/voice_service.dart';
import '../theme/app_colors.dart';
import '../widgets/confirm_logout.dart';
import '../widgets/list_search.dart';
import 'login_screen.dart';
import 'password_requests_screen.dart';
import 'refund_history_screen.dart';
import 'reject_history_screen.dart';
import 'return_detail_screen.dart';
import 'scan_bottle_screen.dart';
import 'shop_list_screen.dart';
import 'staff_list_screen.dart';

const _refundGreen = Color(0xFF1B4332);
const _rejectRed = Color(0xFF6B2C2C);
const _amountGold = Color(0xFFA9672B);

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String token;
  final Map<String, dynamic>? locationInfo;

  const HomeScreen({super.key, required this.user, required this.token, this.locationInfo});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _apiService = ApiService();

  bool get _isAdmin => widget.user['role'] == 'admin';

  // Staff: their own returns, for today's stats and recent scans.
  // Admin: pending "forgot password" requests, for the badge.
  late Future<List<dynamic>> _dataFuture = _load();
  DateTime? _loadedAt;

  Future<List<dynamic>> _load() async {
    final data = _isAdmin
        ? await _apiService.listPasswordResetRequests(widget.token)
        : await _apiService.listMyReturns(widget.token);
    _loadedAt = DateTime.now();
    return data;
  }

  void _refresh() => setState(() => _dataFuture = _load());

  Future<void> _open(WidgetBuilder builder) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: builder));
    if (mounted) _refresh(); // counts may have changed while away
  }

  Future<void> _logout() async {
    if (!await confirmLogout(context)) return;
    GeofenceMonitor.instance.stop();
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          _refresh();
          await _dataFuture.catchError((_) => <dynamic>[]);
        },
        child: FutureBuilder<List<dynamic>>(
          future: _dataFuture,
          builder: (context, snapshot) {
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                _HeaderWithCard(
                  header: _Header(
                    user: widget.user,
                    token: widget.token,
                    locationInfo: widget.locationInfo,
                    onLogout: _logout,
                  ),
                  card: _isAdmin ? null : _StatsCard(snapshot: snapshot, loadedAt: _loadedAt, onRefresh: _refresh),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: _isAdmin ? _adminBody(snapshot) : _staffBody(snapshot),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _staffBody(AsyncSnapshot<List<dynamic>> snapshot) {
    final today = _todayReturns(snapshot.data ?? const []);
    final refundedToday = today.where((r) => r['status'] == 'verified').length;
    final rejectedToday = today.where((r) => r['status'] == 'rejected').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScanHeroCard(onTap: () => _open((_) => ScanBottleScreen(token: widget.token, user: widget.user))),
        const SizedBox(height: 14),
        // IntrinsicHeight + stretch: both cards take the taller one's height.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _HistoryCard(
                  color: _refundGreen,
                  icon: Icons.check,
                  title: 'Refund',
                  subtitle: 'Successful returns',
                  todayCount: snapshot.hasData ? refundedToday : null,
                  onTap: () => _open((_) => RefundHistoryScreen(token: widget.token)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HistoryCard(
                  color: _rejectRed,
                  icon: Icons.close,
                  title: 'Reject',
                  subtitle: 'Rejected returns',
                  todayCount: snapshot.hasData ? rejectedToday : null,
                  onTap: () => _open((_) => RejectHistoryScreen(token: widget.token)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _RecentScansCard(
          snapshot: snapshot,
          token: widget.token,
          hasScansToday: today.isNotEmpty,
          onViewAll: () => _open((_) => _AllScansScreen(token: widget.token, returns: snapshot.data ?? const [])),
        ),
      ],
    );
  }

  Widget _adminBody(AsyncSnapshot<List<dynamic>> snapshot) {
    final pending = snapshot.data?.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NavCard(
          color: const Color(0xFF2D6A4F),
          icon: Icons.people_outline,
          title: 'Manage Staff',
          subtitle: 'Add & manage staff accounts',
          onTap: () => _open((_) => StaffListScreen(token: widget.token)),
        ),
        const SizedBox(height: 12),
        _NavCard(
          color: const Color(0xFF40916C),
          icon: Icons.storefront_outlined,
          title: 'Manage Shops',
          subtitle: 'TASMAC outlet locations',
          onTap: () => _open((_) => ShopListScreen(token: widget.token)),
        ),
        const SizedBox(height: 12),
        // IntrinsicHeight + stretch: both cards take the taller one's height.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _HistoryCard(
                  color: _refundGreen,
                  icon: Icons.check,
                  title: 'Refunds',
                  subtitle: 'All shops',
                  todayCount: null,
                  onTap: () => _open((_) => RefundHistoryScreen(token: widget.token, allShops: true)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HistoryCard(
                  color: _rejectRed,
                  icon: Icons.close,
                  title: 'Rejections',
                  subtitle: 'All shops',
                  todayCount: null,
                  onTap: () => _open((_) => RejectHistoryScreen(token: widget.token, allShops: true)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _NavCard(
          color: _amountGold,
          icon: Icons.lock_reset,
          title: 'Password Requests',
          subtitle: 'Staff who forgot their password',
          badge: (pending ?? 0) > 0 ? '$pending new' : null,
          onTap: () => _open((_) => PasswordRequestsScreen(token: widget.token)),
        ),
      ],
    );
  }
}

List<Map<String, dynamic>> _todayReturns(List<dynamic> all) {
  final now = DateTime.now();
  return [
    for (final item in all.cast<Map<String, dynamic>>())
      if (_createdAt(item) case final at? when at.year == now.year && at.month == now.month && at.day == now.day) item,
  ];
}

DateTime? _createdAt(Map<String, dynamic> item) => DateTime.tryParse(item['created_at']?.toString() ?? '')?.toLocal();

String _relativeTime(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${at.day}/${at.month}/${at.year}';
}

/// The green header with the stats card overlapping its bottom edge, as in
/// the design. The green backdrop is sized from the content (not a fixed
/// height), so it still fits with large system fonts.
class _HeaderWithCard extends StatelessWidget {
  final Widget header;
  final Widget? card;

  const _HeaderWithCard({required this.header, this.card});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: card != null ? 70 : 0,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryGreen, Color(0xFF2D6A4F)],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (card != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: card),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final Map<String, dynamic> user;
  final String token;
  final Map<String, dynamic>? locationInfo;
  final VoidCallback onLogout;

  const _Header({required this.user, required this.token, required this.locationInfo, required this.onLogout});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _today() {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final white70 = Colors.white.withValues(alpha: 0.85);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 8, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StaffAvatar(token: token, user: user),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['full_name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${user['user_id'] ?? ''}  •  ${(user['role'] as String? ?? '').toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: white70, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<VoiceLanguage>(
                icon: const Icon(Icons.campaign_outlined, color: Colors.white),
                tooltip: 'Voice language',
                onSelected: (language) => VoiceService.instance.setLanguage(language),
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    value: VoiceLanguage.english,
                    checked: VoiceService.instance.language == VoiceLanguage.english,
                    child: const Text('Voice: English'),
                  ),
                  CheckedPopupMenuItem(
                    value: VoiceLanguage.tamil,
                    checked: VoiceService.instance.language == VoiceLanguage.tamil,
                    child: const Text('Voice: தமிழ்'),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'Logout',
                onPressed: onLogout,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (user['shop_name'] != null) _HeaderChip(icon: Icons.storefront_outlined, label: user['shop_name']),
                if (locationInfo != null)
                  _HeaderChip(
                    icon: Icons.location_on_outlined,
                    label: '${locationInfo!['distance_meters']} m away',
                    trailing: const Icon(Icons.check_circle, color: AppColors.accentGreen, size: 18),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${_greeting()}  •  ${_today()}',
            style: TextStyle(color: white70, fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;

  const _HeaderChip({required this.icon, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final AsyncSnapshot<List<dynamic>> snapshot;
  final DateTime? loadedAt;
  final VoidCallback onRefresh;

  const _StatsCard({required this.snapshot, required this.loadedAt, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final loaded = snapshot.hasData;
    final today = _todayReturns(snapshot.data ?? const []);
    final refunded = today.where((r) => r['status'] == 'verified').length;
    final rejected = today.where((r) => r['status'] == 'rejected').length;

    final String syncLabel;
    if (snapshot.connectionState == ConnectionState.waiting) {
      syncLabel = 'Updating…';
    } else if (snapshot.hasError) {
      syncLabel = "Couldn't update — tap to retry";
    } else {
      syncLabel = loadedAt != null ? 'Updated ${_relativeTime(loadedAt!)}' : '';
    }

    return Material(
      color: AppColors.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Column(
          children: [
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Scanned',
                      value: loaded ? '${today.length}' : '—',
                      color: AppColors.textPrimary,
                      footer: const Icon(Icons.photo_camera_outlined, size: 18, color: AppColors.textSecondary),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _Stat(
                      label: 'Refunded',
                      value: loaded ? '$refunded' : '—',
                      color: _refundGreen,
                      footer: Text(
                        loaded ? '₹${refunded * 10}' : '',
                        style: const TextStyle(color: _refundGreen, fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _Stat(
                      label: 'Rejected',
                      value: loaded ? '$rejected' : '—',
                      color: _rejectRed,
                      footer: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.brandRed),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  children: [
                    const Icon(Icons.sync, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        syncLabel,
                        style: TextStyle(
                          color: snapshot.hasError ? AppColors.brandRed : AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Text('Today', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Widget footer;

  const _Stat({required this.label, required this.value, required this.color, required this.footer});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 4),
        footer,
      ],
    );
  }
}

class _ScanHeroCard extends StatelessWidget {
  final VoidCallback onTap;

  const _ScanHeroCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFFC62828), AppColors.brandRed]),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 6),
                  ),
                  child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 34),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan Bottle',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Verify a return with the camera',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final int? todayCount;
  final VoidCallback onTap;

  const _HistoryCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.todayCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: todayCount == null
                          ? null
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              // Shrinks rather than cutting to "2 tod…" on narrow POS screens.
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '$todayCount today',
                                  maxLines: 1,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Pushes the title to the bottom when the paired card is taller,
              // so both cards in a row line up.
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // One line, shrunk if needed: on ~320-wide POS screens
                        // "Rejections" otherwise broke mid-word.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            title,
                            maxLines: 1,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentScansCard extends StatelessWidget {
  final AsyncSnapshot<List<dynamic>> snapshot;
  final String token;
  final bool hasScansToday;
  final VoidCallback onViewAll;

  const _RecentScansCard({
    required this.snapshot,
    required this.token,
    required this.hasScansToday,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final recent = (snapshot.data ?? const []).take(5).cast<Map<String, dynamic>>().toList();

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Recent scans', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (recent.isNotEmpty)
                  TextButton(
                    onPressed: onViewAll,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text('View all'), Icon(Icons.chevron_right, size: 18)],
                    ),
                  ),
              ],
            ),
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot.hasError)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Could not load scans: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              )
            else ...[
              for (var i = 0; i < recent.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _ScanTile(item: recent[i], token: token),
              ],
              if (!hasScansToday) const _EmptyToday(),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScanTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final String token;

  const _ScanTile({required this.item, required this.token});

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String?;
    final createdAt = _createdAt(item);

    final (IconData icon, Color color, String label) = switch (status) {
      'verified' => (Icons.check, Colors.green.shade700, '₹10 refunded'),
      'rejected' => (
          Icons.close,
          AppColors.brandRed,
          _sentenceCase((item['rejection_reason'] ?? 'Rejected').toString().replaceAll('_', ' ')),
        ),
      _ => (Icons.priority_high, _amountGold, 'Payment not completed'),
    };

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReturnDetailScreen(item: item, token: token)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(radius: 20, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['qr_code'] ?? 'Unknown bottle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  if (bottleLabel(item) case final bottle?)
                    Text(
                      bottle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (createdAt != null)
              Text(_relativeTime(createdAt), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  String _sentenceCase(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

class _EmptyToday extends StatelessWidget {
  const _EmptyToday();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 8),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.accentGreen.withValues(alpha: 0.15),
            child: const Icon(Icons.qr_code_2, color: AppColors.primaryGreen, size: 30),
          ),
          const SizedBox(height: 10),
          const Text('No scans yet today.', style: TextStyle(fontWeight: FontWeight.w600)),
          const Text('Tap Scan Bottle to start.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _NavCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Text(badge!, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every return this staff member has processed, newest first.
class _AllScansScreen extends StatefulWidget {
  final String token;
  final List<dynamic> returns;

  const _AllScansScreen({required this.token, required this.returns});

  @override
  State<_AllScansScreen> createState() => _AllScansScreenState();
}

class _AllScansScreenState extends State<_AllScansScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final returns = widget.returns.cast<Map<String, dynamic>>().where((item) {
      return matchesSearch(_query, [
        item['refund_qr_code'] ?? item['qr_code'],
        item['manufacturing_qr_code'],
        item['brand_name'],
        item['bottle_size'],
        item['status'] == 'verified' ? 'refunded' : item['status'],
        item['rejection_reason']?.toString().replaceAll('_', ' '),
        item['shop_name'],
      ]);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Scans'),
        bottom: ListSearchBar(
          hint: 'Search QR, brand, size, refunded/rejected…',
          onChanged: (query) => setState(() => _query = query),
        ),
      ),
      body: returns.isEmpty
          ? const Center(child: Text('No results for this search.'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: returns.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _ScanTile(item: returns[index], token: widget.token),
            ),
    );
  }
}

/// Shows the logged-in staff/admin's uploaded photo (set by an admin when
/// creating the account) in the header, falling back to their name's first
/// letter when no photo was uploaded or it fails to load.
class _StaffAvatar extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;

  const _StaffAvatar({required this.token, required this.user});

  @override
  State<_StaffAvatar> createState() => _StaffAvatarState();
}

class _StaffAvatarState extends State<_StaffAvatar> {
  late final Future<Uint8List?> _photoFuture = _loadPhoto();

  Future<Uint8List?> _loadPhoto() async {
    if (widget.user['has_photo'] != true) return null;
    try {
      return await ApiService().getStaffPhoto(widget.token, widget.user['id'] as int);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = (widget.user['full_name'] as String? ?? '?').trim().isNotEmpty
        ? (widget.user['full_name'] as String).trim()[0].toUpperCase()
        : '?';

    return FutureBuilder<Uint8List?>(
      future: _photoFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return CircleAvatar(
          radius: 30,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          backgroundImage: bytes != null ? MemoryImage(bytes) : null,
          child: bytes == null
              ? Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 26))
              : null,
        );
      },
    );
  }
}
