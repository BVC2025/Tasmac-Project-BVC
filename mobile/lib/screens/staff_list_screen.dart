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

  Future<void> _resetPassword(int staffId, String staffName) async {
    final controller = TextEditingController();
    final newPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reset password — $staffName'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'New password'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (newPassword == null || newPassword.isEmpty) return;

    try {
      await _apiService.resetStaffPassword(widget.token, staffId, newPassword);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset for $staffName. Share the new password with them securely.')),
      );
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
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.key, color: Colors.blueGrey),
                            tooltip: 'Reset password',
                            onPressed: () => _resetPassword(member['id'] as int, member['full_name'] ?? ''),
                          ),
                          IconButton(
                            icon: const Icon(Icons.block, color: Colors.red),
                            tooltip: 'Deactivate',
                            onPressed: () => _deactivate(member['id'] as int),
                          ),
                        ],
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
