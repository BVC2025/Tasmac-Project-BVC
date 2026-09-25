import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'add_staff_screen.dart';

class StaffListScreen extends StatefulWidget {
  final String token;

  const StaffListScreen({super.key, required this.token});

  @override
  State<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends State<StaffListScreen> {
  final _apiService = ApiService();
  late Future<List<dynamic>> _staffFuture;

  @override
  void initState() {
    super.initState();
    _staffFuture = _apiService.listStaff(widget.token);
  }

  void _refresh() {
    setState(() {
      _staffFuture = _apiService.listStaff(widget.token);
    });
  }

  Future<void> _deactivate(int staffId) async {
    try {
      await _apiService.deactivateStaff(widget.token, staffId);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Staff')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => AddStaffScreen(token: widget.token)),
          );
          if (created == true) _refresh();
        },
        child: const Icon(Icons.person_add),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _staffFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final staff = snapshot.data ?? [];
          if (staff.isEmpty) {
            return const Center(child: Text('No staff yet.'));
          }

          return ListView.separated(
            itemCount: staff.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final member = staff[index] as Map<String, dynamic>;
              final isActive = member['is_active'] == true;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isActive ? Colors.green : Colors.grey,
                  child: Icon(
                    member['role'] == 'admin' ? Icons.shield : Icons.person,
                    color: Colors.white,
                  ),
                ),
                title: Text(member['full_name'] ?? ''),
                subtitle: Text('${member['phone_number']} • ${member['role']}'),
                trailing: isActive
                    ? IconButton(
                        icon: const Icon(Icons.block, color: Colors.red),
                        tooltip: 'Deactivate',
                        onPressed: () => _deactivate(member['id'] as int),
                      )
                    : const Text('Inactive', style: TextStyle(color: Colors.grey)),
              );
            },
          );
        },
      ),
    );
  }
}
