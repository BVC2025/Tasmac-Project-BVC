import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
    bool obscure = true;

    final newPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Reset password — $staffName'),
          content: TextField(
            controller: controller,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'New password',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setDialogState(() => obscure = !obscure),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Reset'),
            ),
          ],
        ),
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
                leading: _EditableStaffAvatar(
                  token: widget.token,
                  staffId: member['id'] as int,
                  hasPhoto: member['has_photo'] == true,
                  isActive: isActive,
                  isAdmin: member['role'] == 'admin',
                  onPhotoChanged: _refresh,
                ),
                title: Text(member['full_name'] ?? ''),
                subtitle: Text('ID: ${member['user_id']} • ${member['phone_number']} • ${member['role']}'),
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

/// Shows a staff member's uploaded photo (or a role icon when none is set)
/// and lets admin tap it to set or replace it — the only place a photo can
/// be attached to an *existing* account, since Add Staff only covers the
/// moment of creation.
class _EditableStaffAvatar extends StatefulWidget {
  final String token;
  final int staffId;
  final bool hasPhoto;
  final bool isActive;
  final bool isAdmin;
  final VoidCallback onPhotoChanged;

  const _EditableStaffAvatar({
    required this.token,
    required this.staffId,
    required this.hasPhoto,
    required this.isActive,
    required this.isAdmin,
    required this.onPhotoChanged,
  });

  @override
  State<_EditableStaffAvatar> createState() => _EditableStaffAvatarState();
}

class _EditableStaffAvatarState extends State<_EditableStaffAvatar> {
  final _apiService = ApiService();
  final _picker = ImagePicker();
  late Future<Uint8List?> _photoFuture = _loadPhoto();
  bool _uploading = false;

  Future<Uint8List?> _loadPhoto() async {
    if (!widget.hasPhoto) return null;
    try {
      return await _apiService.getStaffPhoto(widget.token, widget.staffId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 70);
      if (file == null) return;
      final bytes = await file.readAsBytes();

      setState(() => _uploading = true);
      await _apiService.uploadStaffPhoto(widget.token, widget.staffId, bytes);
      if (!mounted) return;
      setState(() {
        _photoFuture = Future.value(bytes);
        _uploading = false;
      });
      widget.onPhotoChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not set photo: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAndUpload(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
      child: Stack(
        children: [
          FutureBuilder<Uint8List?>(
            future: _photoFuture,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              return CircleAvatar(
                backgroundColor: widget.isActive ? Colors.green : Colors.grey,
                backgroundImage: bytes != null ? MemoryImage(bytes) : null,
                child: (bytes == null && !_uploading)
                    ? Icon(widget.isAdmin ? Icons.shield : Icons.person, color: Colors.white)
                    : (_uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : null),
              );
            },
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt, size: 12, color: Colors.blueGrey),
            ),
          ),
        ],
      ),
    );
  }
}
