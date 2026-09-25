import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bottle_list_screen.dart';
import 'login_screen.dart';
import 'my_returns_screen.dart';
import 'scan_bottle_screen.dart';
import 'shop_list_screen.dart';
import 'staff_list_screen.dart';

class _Action {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;

  const _Action({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.builder,
  });
}

class HomeScreen extends StatelessWidget {
  final Map<String, dynamic> user;
  final String token;
  final Map<String, dynamic>? locationInfo;

  const HomeScreen({super.key, required this.user, required this.token, this.locationInfo});

  @override
  Widget build(BuildContext context) {
    final isAdmin = user['role'] == 'admin';

    final actions = <_Action>[
      if (isAdmin) ...[
        _Action(
          label: 'Manage Staff',
          subtitle: 'Add & manage staff accounts',
          icon: Icons.people_outline,
          color: const Color(0xFF2D6A4F),
          builder: (_) => StaffListScreen(token: token),
        ),
        _Action(
          label: 'Manage Shops',
          subtitle: 'TASMAC outlet locations',
          icon: Icons.storefront_outlined,
          color: const Color(0xFF40916C),
          builder: (_) => ShopListScreen(token: token),
        ),
        _Action(
          label: 'Manage Bottles',
          subtitle: 'Generate & print QR codes',
          icon: Icons.qr_code_2,
          color: const Color(0xFF52B788),
          builder: (_) => BottleListScreen(token: token),
        ),
      ],
      _Action(
        label: 'Scan Bottle',
        subtitle: 'Verify a return with the camera',
        icon: Icons.qr_code_scanner,
        color: AppColors.brandRed,
        builder: (_) => ScanBottleScreen(token: token, user: user),
      ),
      _Action(
        label: 'My Returns',
        subtitle: 'Returns you have processed',
        icon: Icons.history,
        color: const Color(0xFF1B4332),
        builder: (_) => MyReturnsScreen(token: token),
      ),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.primaryGreen,
            foregroundColor: Colors.white,
            pinned: true,
            expandedHeight: locationInfo != null ? 220 : 190,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16, right: 20),
              title: Text(
                user['full_name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryGreen, Color(0xFF2D6A4F)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          (user['full_name'] as String? ?? '?').trim().isNotEmpty
                              ? (user['full_name'] as String).trim()[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              user['phone_number'] ?? '',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                (user['role'] as String? ?? '').toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            if (locationInfo != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.location_on, color: Colors.white, size: 13),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '${locationInfo!['distance_meters']}m from ${locationInfo!['shop_name']}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.crossAxisExtent >= 700 ? 3 : 2;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.95,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final action = actions[index];
                      return _ActionCard(action: action, token: token);
                    },
                    childCount: actions.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final _Action action;
  final String token;

  const _ActionCard({required this.action, required this.token});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: action.color,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: action.builder)),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, color: Colors.white, size: 24),
              ),
              const Spacer(),
              Text(
                action.label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                action.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
