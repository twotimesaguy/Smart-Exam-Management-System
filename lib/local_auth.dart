import 'package:flutter/foundation.dart';

enum AppUserRole { admin, invigilator, disciplinaryOfficer }

extension AppUserRoleLabel on AppUserRole {
  String get label {
    switch (this) {
      case AppUserRole.admin:
        return 'Admin';
      case AppUserRole.invigilator:
        return 'Invigilator';
      case AppUserRole.disciplinaryOfficer:
        return 'Disciplinary Officer';
    }
  }
}

class LocalUser {
  const LocalUser({
    this.id,
    required this.username,
    required this.role,
    this.password = '',
    this.token,
    this.profileImageUrl,
  });

  final int? id;
  final String username;
  final String password;
  final AppUserRole role;
  final String? token;
  final String? profileImageUrl;
}

extension AppUserRoleApi on AppUserRole {
  String get apiValue {
    switch (this) {
      case AppUserRole.admin:
        return 'admin';
      case AppUserRole.invigilator:
        return 'invigilator';
      case AppUserRole.disciplinaryOfficer:
        return 'disciplinary_officer';
    }
  }
}

AppUserRole appUserRoleFromApiValue(String value) {
  switch (value) {
    case 'admin':
      return AppUserRole.admin;
    case 'invigilator':
      return AppUserRole.invigilator;
    case 'disciplinary_officer':
      return AppUserRole.disciplinaryOfficer;
    default:
      throw FlutterError('Unknown role: $value');
  }
}

class LocalAuthService {
  LocalAuthService._();

  static final LocalAuthService instance = LocalAuthService._();

  final List<LocalUser> _users = [];
  final Map<String, String> _profileImagePaths = {};

  List<LocalUser> get users => List.unmodifiable(_users);

  String? profileImagePathFor(String username) {
    return _profileImagePaths[username.trim().toLowerCase()];
  }

  void updateProfileImagePath({
    required String username,
    required String imagePath,
  }) {
    _profileImagePaths[username.trim().toLowerCase()] = imagePath;
  }

  bool usernameExists(String username) {
    return _users.any(
      (user) => user.username.toLowerCase() == username.toLowerCase(),
    );
  }

  LocalUser signUp({
    required String username,
    required String password,
    required AppUserRole role,
  }) {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || password.trim().isEmpty) {
      throw FlutterError('Username and password are required.');
    }

    if (!RegExp(r'[A-Za-z]').hasMatch(normalizedUsername)) {
      throw FlutterError('Username must include at least one letter.');
    }

    if (usernameExists(normalizedUsername)) {
      throw FlutterError('Username already exists.');
    }

    final user = LocalUser(
      username: normalizedUsername,
      password: password,
      role: role,
    );

    _users.add(user);
    return user;
  }

  LocalUser? login({required String username, required String password}) {
    final normalizedUsername = username.trim().toLowerCase();

    for (final user in _users) {
      if (user.username.toLowerCase() == normalizedUsername &&
          user.password == password) {
        return user;
      }
    }

    return null;
  }
}
