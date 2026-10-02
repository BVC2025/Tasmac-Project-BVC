import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';

class AddStaffScreen extends StatefulWidget {
  final String token;

  const AddStaffScreen({super.key, required this.token});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _userIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  final _picker = ImagePicker();

  String _role = 'staff';
  int? _shopId;
  Uint8List? _photoBytes;
  bool _isSaving = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  late Future<List<dynamic>> _shopsFuture;

  @override
  void initState() {
    super.initState();
    _shopsFuture = _apiService.listShops(widget.token);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 70);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() => _photoBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not capture photo: $e')));
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final staff = await _apiService.createStaff(
        widget.token,
        fullName: _nameController.text.trim(),
        userId: _userIdController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        password: _passwordController.text,
        role: _role,
        shopId: _shopId,
      );

      final photoBytes = _photoBytes;
      if (photoBytes != null) {
        await _apiService.uploadStaffPhoto(widget.token, staff['id'] as int, photoBytes);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _userIdController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Staff')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: Colors.grey.shade200,
                          backgroundImage: _photoBytes != null ? MemoryImage(_photoBytes!) : null,
                          child: _photoBytes == null
                              ? const Icon(Icons.person_outline, size: 44, color: Colors.grey)
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: PopupMenuButton<ImageSource>(
                            icon: const CircleAvatar(
                              radius: 16,
                              child: Icon(Icons.camera_alt_outlined, size: 16),
                            ),
                            onSelected: _pickPhoto,
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: ImageSource.camera, child: Text('Camera')),
                              PopupMenuItem(value: ImageSource.gallery, child: Text('Gallery')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter name' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _userIdController,
                    decoration: const InputDecoration(labelText: 'User ID', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a User ID' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter phone number' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 4) ? 'Min 4 characters' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'staff', child: Text('Staff')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    ],
                    onChanged: (value) => setState(() => _role = value ?? 'staff'),
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<List<dynamic>>(
                    future: _shopsFuture,
                    builder: (context, snapshot) {
                      final shops = snapshot.data ?? [];
                      return DropdownButtonFormField<int?>(
                        initialValue: _shopId,
                        decoration: const InputDecoration(
                          labelText: 'Assigned Shop (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('None')),
                          ...shops.map(
                            (shop) => DropdownMenuItem<int?>(
                              value: shop['id'] as int,
                              child: Text(shop['name'] as String),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _shopId = value),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null) ...[
                    Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                  ],
                  FilledButton(
                    onPressed: _isSaving ? null : _handleSave,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
