import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';
import '../services/client_photo_service.dart';
import '../widgets/client_avatar.dart';

class AdminProfileScreen extends StatefulWidget {
  final AuthService auth;

  const AdminProfileScreen({super.key, required this.auth});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.auth.displayName,
  );
  int _photoRevision = 0;
  bool _savingName = false;
  bool _photoBusy = false;
  bool? _hasPhoto;

  @override
  void initState() {
    super.initState();
    _refreshHasPhoto();
  }

  Future<void> _refreshHasPhoto() async {
    final path = widget.auth.adminPhotoPath;
    if (path == null) {
      if (mounted) setState(() => _hasPhoto = false);
      return;
    }
    try {
      final url = await ClientPhotoService().signedUrl(path, seconds: 30);
      if (mounted) setState(() => _hasPhoto = url != null && url.isNotEmpty);
    } catch (_) {
      if (mounted) setState(() => _hasPhoto = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _avatarName {
    final typed = _name.text.trim();
    return typed.isEmpty ? widget.auth.displayName : typed;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _clean(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Enter your name before saving.');
      return;
    }
    setState(() => _savingName = true);
    try {
      await widget.auth.updateDisplayName(name);
      if (!mounted) return;
      setState(() => _name.text = name);
      _snack('Admin name updated');
    } catch (e) {
      _snack('Could not update your name: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _showPhotoActions() async {
    final path = widget.auth.adminPhotoPath;
    if (path == null) {
      _snack('Join or create a workspace before adding an admin photo.');
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final hasPhoto = _hasPhoto == true;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(
                  hasPhoto
                      ? 'Change photo with camera'
                      : 'Add photo with camera',
                ),
                onTap: () => Navigator.pop(sheetContext, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(
                  hasPhoto
                      ? 'Change photo from gallery'
                      : 'Add photo from gallery',
                ),
                onTap: () => Navigator.pop(sheetContext, 'gallery'),
              ),
              if (hasPhoto)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Remove photo',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'remove'),
                ),
            ],
          ),
        );
      },
    );
    if (action == 'camera') await _pickPhoto(ImageSource.camera);
    if (action == 'gallery') await _pickPhoto(ImageSource.gallery);
    if (action == 'remove') await _removePhoto();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final path = widget.auth.adminPhotoPath;
    if (path == null) {
      _snack('Join or create a workspace before adding an admin photo.');
      return;
    }
    if (_photoBusy) return;
    try {
      final file = await ClientPhotoService.pick(source);
      if (file == null) return;
      final ext = ClientPhotoService.extensionOf(file.name);
      if (!ClientPhotoService.isSupportedExtension(ext)) {
        _snack('Admin photos must be JPG or PNG.');
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 15 * 1024 * 1024) {
        _snack('That photo is too large. Choose a smaller image.');
        return;
      }
      setState(() => _photoBusy = true);
      await ClientPhotoService().uploadToPath(
        path: path,
        bytes: bytes,
        extension: ext,
      );
      if (!mounted) return;
      setState(() {
        _photoRevision++;
        _hasPhoto = true;
      });
      _snack('Admin photo updated');
    } catch (e) {
      _snack('Photo update failed: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    final path = widget.auth.adminPhotoPath;
    if (path == null || _photoBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Remove admin photo?'),
            content: const Text(
              'The stored photo will be deleted from the private workspace '
              'storage. You can upload a new one at any time.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    setState(() => _photoBusy = true);
    try {
      await ClientPhotoService().remove(path);
      if (!mounted) return;
      setState(() {
        _photoRevision++;
        _hasPhoto = false;
      });
      _snack('Admin photo removed');
    } catch (e) {
      _snack('Could not remove the photo: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Widget _avatar() {
    final scheme = Theme.of(context).colorScheme;
    final path = widget.auth.adminPhotoPath ?? '';
    return Center(
      child: GestureDetector(
        onTap: _showPhotoActions,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClientAvatar(
              key: ValueKey('admin-avatar-$_photoRevision'),
              photoPath: path,
              name: _avatarName,
              size: 108,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                child: Icon(
                  _hasPhoto == true
                      ? Icons.edit_outlined
                      : Icons.add_a_photo_outlined,
                  size: 17,
                  color: scheme.onPrimary,
                ),
              ),
            ),
            if (_photoBusy)
              const Positioned.fill(
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final photoPath = auth.adminPhotoPath;
    return Scaffold(
      appBar: AppBar(title: const Text('Admin profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _avatar(),
          const SizedBox(height: 14),
          Text(
            auth.displayName.isEmpty ? 'Admin' : auth.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the photo to add, change or remove it. The image is stored '
            'privately in your workspace, not in a public gallery.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Your name',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Admin name',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _savingName ? null : _saveName,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_savingName ? 'Saving…' : 'Save name'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Private photo storage'),
              subtitle: Text(
                photoPath == null
                    ? 'Join or create a workspace to store an admin photo.'
                    : 'Stored in the client-photos bucket at '
                        '$photoPath. Only people in this workspace can '
                        'request a temporary signed link.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
