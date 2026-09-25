import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'add_shop_screen.dart';

class ShopListScreen extends StatefulWidget {
  final String token;

  const ShopListScreen({super.key, required this.token});

  @override
  State<ShopListScreen> createState() => _ShopListScreenState();
}

class _ShopListScreenState extends State<ShopListScreen> {
  final _apiService = ApiService();
  late Future<List<dynamic>> _shopsFuture;

  @override
  void initState() {
    super.initState();
    _shopsFuture = _apiService.listShops(widget.token);
  }

  void _refresh() {
    setState(() {
      _shopsFuture = _apiService.listShops(widget.token);
    });
  }

  Future<void> _deactivate(int shopId) async {
    try {
      await _apiService.deactivateShop(widget.token, shopId);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  String? _formatTime(TimeOfDay? time) {
    if (time == null) return null;
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  Future<void> _editHours(Map<String, dynamic> shop) async {
    TimeOfDay? start = _parseTime(shop['service_start_time'] as String?);
    TimeOfDay? end = _parseTime(shop['service_end_time'] as String?);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Service Hours'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Leave both blank for 24/7 access.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: start ?? const TimeOfDay(hour: 10, minute: 0),
                        );
                        if (picked != null) setDialogState(() => start = picked);
                      },
                      child: Text(start == null ? 'Start' : start!.format(context)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: end ?? const TimeOfDay(hour: 18, minute: 0),
                        );
                        if (picked != null) setDialogState(() => end = picked);
                      },
                      child: Text(end == null ? 'End' : end!.format(context)),
                    ),
                  ),
                ],
              ),
              if (start != null || end != null)
                TextButton(
                  onPressed: () => setDialogState(() {
                    start = null;
                    end = null;
                  }),
                  child: const Text('Clear (24/7)'),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      await _apiService.updateShopServiceWindow(
        widget.token,
        shop['id'] as int,
        serviceStartTime: _formatTime(start),
        serviceEndTime: _formatTime(end),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Shops')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => AddShopScreen(token: widget.token)),
          );
          if (created == true) _refresh();
        },
        child: const Icon(Icons.add_business),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _shopsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final shops = snapshot.data ?? [];
          if (shops.isEmpty) {
            return const Center(child: Text('No shops yet.'));
          }

          return ListView.separated(
            itemCount: shops.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final shop = shops[index] as Map<String, dynamic>;
              final isActive = shop['is_active'] == true;
              final start = shop['service_start_time'];
              final end = shop['service_end_time'];
              final hoursLabel = (start != null && end != null)
                  ? '${start.toString().substring(0, 5)} – ${end.toString().substring(0, 5)}'
                  : '24/7';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isActive ? Colors.deepPurple : Colors.grey,
                  child: const Icon(Icons.store, color: Colors.white),
                ),
                title: Text(shop['name'] ?? ''),
                subtitle: Text(
                  '${shop['shop_code']}${shop['address'] != null ? ' • ${shop['address']}' : ''} • $hoursLabel',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.schedule),
                      tooltip: 'Set service hours',
                      onPressed: () => _editHours(shop),
                    ),
                    if (isActive)
                      IconButton(
                        icon: const Icon(Icons.block, color: Colors.red),
                        tooltip: 'Deactivate',
                        onPressed: () => _deactivate(shop['id'] as int),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('Inactive', style: TextStyle(color: Colors.grey)),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
