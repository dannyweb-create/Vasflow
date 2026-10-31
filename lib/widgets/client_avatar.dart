import 'package:flutter/material.dart';

import '../services/client_photo_service.dart';

class ClientAvatar extends StatefulWidget {
  final String photoPath;
  final String name;
  final double size;

  /// When set, the avatar is drawn with rounded corners instead of a circle.
  final BorderRadius? borderRadius;

  const ClientAvatar({
    super.key,
    required this.photoPath,
    required this.name,
    this.size = 46,
    this.borderRadius,
  });

  @override
  State<ClientAvatar> createState() => _ClientAvatarState();
}

class _ClientAvatarState extends State<ClientAvatar> {
  Future<String?>? _urlFuture;

  @override
  void initState() {
    super.initState();
    _loadSignedUrl();
  }

  @override
  void didUpdateWidget(covariant ClientAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoPath != widget.photoPath) _loadSignedUrl();
  }

  void _loadSignedUrl() {
    final path = widget.photoPath.trim();
    _urlFuture =
        path.isEmpty ? null : ClientPhotoService().signedUrl(path, seconds: 60);
  }

  String get _initials {
    final parts =
        widget.name
            .trim()
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Widget _fallback() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape:
            widget.borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.borderRadius,
      ),
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: widget.size * 0.33,
          fontWeight: FontWeight.w800,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_urlFuture == null) return _fallback();
    return FutureBuilder<String?>(
      future: _urlFuture,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) return _fallback();
        final image = Image.network(
          url,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          loadingBuilder:
              (context, child, progress) =>
                  progress == null ? child : _fallback(),
          errorBuilder: (context, error, stackTrace) => _fallback(),
        );
        final radius = widget.borderRadius;
        return radius == null
            ? ClipOval(child: image)
            : ClipRRect(borderRadius: radius, child: image);
      },
    );
  }
}
