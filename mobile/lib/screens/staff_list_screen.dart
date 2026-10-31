import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../widgets/list_search.dart';
import '../widgets/reset_password_dialog.dart';
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
  String _query = '';

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

  Future<void> _edit(Map<String, dynamic> member) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddStaffScreen(token: widget.token, staff: member)),
    );
    if (saved == true) _refresh();
  }

  Future<void> _reactivate(int staffId) async {
    try {
      await _apiService.reactivateStaff(widget.token, staffId);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deactivate(Map<String, dynamic> member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate staff?'),
        content: Text('${member['full_name']} will no longer be able to log in. You can reactivate them later.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _apiService.deactivateStaff(widget.token, member['id'] as int);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Staff'),
        bottom: ListSearchBar(
          hint: 'Search name, User ID, phone, shop…',
          onChanged: (query) => setState(() => _query = query),
        ),
      ),
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

          final all = snapshot.data ?? [];
          if (all.isEmpty) {
            return const Center(child: Text('No staff yet.'));
          }
          final staff = all.where((item) {
            final m = item as Map<String, dynamic>;
            return matchesSearch(_query, [
              m['full_name'],
              m['user_id'],
              m['phone_number'],
              m['role'],
              m['shop_name'],
              m['is_active'] == true ? 'active' : 'inactive',
            ]);
          }).toList();
          if (staff.isEmpty) {
            return const Center(child: Text('No results for this search.'));
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
                subtitle: Text(
                  'ID: ${member['user_id']} • ${member['phone_number']} • ${member['role']}'
                  '${member['shop_name'] != null ? '\n${member['shop_name']}' : ''}'
                  '${isActive ? '' : '\nInactive'}',
                ),
                // One menu instead of a row of icons, so it fits narrow POS screens.
                trailing: PopupMenuButton<void>(
                  tooltip: 'Staff options',
                  itemBuilder: (context) => [
                    PopupMenuItem<void>(onTap: () => _edit(member), child: const Text('Edit details')),
                    if (isActive) ...[
                      PopupMenuItem<void>(
                        onTap: () => showResetPasswordDialog(
                          context,
                          token: widget.token,
                          staffId: member['id'] as int,
                          staffName: member['full_name'] ?? '',
                          staffPhone: member['phone_number'] as String?,
                        ),
                        child: const Text('Reset password'),
                      ),
                      PopupMenuItem<void>(
                        onTap: () => _deactivate(member),
                        child: const Text('Deactivate', style: TextStyle(color: Colors.red)),
                      ),
                    ] else
                      PopupMenuItem<void>(
                        onTap: () => _reactivate(member['id'] as int),
                        child: const Text('Reactivate'),
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
