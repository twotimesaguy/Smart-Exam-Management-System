import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/local_auth.dart';
import 'package:flutter_application_1/local_image_preview.dart';
import 'package:flutter_application_1/module_shell.dart';
import 'package:image_picker/image_picker.dart';

class ProfileModule extends StatefulWidget {
  const ProfileModule({required this.currentUser, super.key});

  final LocalUser currentUser;

  @override
  State<ProfileModule> createState() => _ProfileModuleState();
}

class _ProfileModuleState extends State<ProfileModule> {
  final ImagePicker _imagePicker = ImagePicker();
  String? _profileImagePath;
  String? _profileImageUrl;
  bool _isPickingImage = false;

  LocalUser get currentUser => widget.currentUser;

  @override
  void initState() {
    super.initState();
    _profileImageUrl = currentUser.profileImageUrl;
    _profileImagePath = LocalAuthService.instance.profileImagePathFor(
      currentUser.username,
    );
  }

  Future<void> _pickProfilePicture() async {
    if (_isPickingImage) {
      return;
    }

    setState(() => _isPickingImage = true);

    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (image == null || !mounted) {
        return;
      }

      String? savedImageUrl;
      if (currentUser.id != null) {
        final updatedUser = await ApiService.instance.uploadProfilePicture(
          userId: currentUser.id!,
          imagePath: kIsWeb ? null : image.path,
          imageBytes: kIsWeb ? await image.readAsBytes() : null,
          imageFileName: image.name,
        );
        savedImageUrl = updatedUser.profileImageUrl == null
            ? null
            : '${updatedUser.profileImageUrl}?v=${DateTime.now().millisecondsSinceEpoch}';
      } else {
        LocalAuthService.instance.updateProfileImagePath(
          username: currentUser.username,
          imagePath: image.path,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _profileImagePath = image.path;
        _profileImageUrl = savedImageUrl ?? _profileImageUrl;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile picture saved.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final roleLabel = currentUser.role.label;
    final modules = _modulesForRole(currentUser.role);

    return ModuleShell(
      title: 'Profile Information',
      description: 'Manage your account profile and available system sections.',
      child: ListView(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final avatar = _ProfileAvatar(
                  username: currentUser.username,
                  imagePath: _profileImagePath,
                  imageUrl: _profileImageUrl,
                );
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentUser.username,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      roleLabel,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isPickingImage ? null : _pickProfilePicture,
                      icon: _isPickingImage
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined),
                      label: Text(
                        _isPickingImage
                            ? 'Opening Gallery...'
                            : _profileImagePath == null
                            ? 'Upload Profile Picture'
                            : 'Change Profile Picture',
                      ),
                    ),
                  ],
                );

                if (constraints.maxWidth < 320) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [avatar, const SizedBox(height: 14), details],
                  );
                }

                return Row(
                  children: [
                    avatar,
                    const SizedBox(width: 18),
                    Expanded(child: details),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _ProfileInfoTile(
                icon: Icons.person_outline,
                label: 'Username',
                value: currentUser.username,
              ),
              _ProfileInfoTile(
                icon: Icons.verified_user_outlined,
                label: 'Role',
                value: roleLabel,
              ),
              _ProfileInfoTile(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Access Level',
                value: _accessLevelForRole(currentUser.role),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available Sections',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ...modules.map(
                  (module) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(module)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<String> _modulesForRole(AppUserRole role) {
    if (role == AppUserRole.admin) {
      return const [
        'Automated Allocation',
        'Student Registration',
        'Attendance Verification',
        'Malpractice Reporting',
        'Profile Information',
      ];
    }

    if (role == AppUserRole.disciplinaryOfficer) {
      return const [
        'Malpractice Case Handling',
        'Disciplinary Report Generation',
        'Profile Information',
      ];
    }

    return const [
      'My Assignment',
      'Student Registration',
      'Attendance Verification',
      'Malpractice Reporting',
      'Profile Information',
    ];
  }

  static String _accessLevelForRole(AppUserRole role) {
    switch (role) {
      case AppUserRole.admin:
        return 'Full system access';
      case AppUserRole.invigilator:
        return 'Invigilation access';
      case AppUserRole.disciplinaryOfficer:
        return 'Case handling access';
    }
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.username,
    required this.imagePath,
    required this.imageUrl,
  });

  final String username;
  final String? imagePath;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final path = imagePath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 84,
        height: 84,
        child: path != null
            ? buildLocalImagePreview(
                path: path,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _InitialsAvatar(username: username),
              )
            : imageUrl != null
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _InitialsAvatar(username: username),
              )
            : _InitialsAvatar(username: username),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          _initials(username),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String _initials(String username) {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      return '?';
    }

    return trimmed.characters.first.toUpperCase();
  }
}

class _ProfileInfoTile extends StatelessWidget {
  const _ProfileInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth < 230 ? constraints.maxWidth : 230,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.secondary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
