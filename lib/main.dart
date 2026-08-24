import 'package:flutter/material.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/auth_page.dart';
import 'package:flutter_application_1/dashboard.dart';
import 'package:flutter_application_1/local_auth.dart';

void main() {
  runApp(const IntelligentExamApp());
}

class IntelligentExamApp extends StatelessWidget {
  const IntelligentExamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Intelligent Exam System',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const AppEntry(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
          secondary: isDark ? const Color(0xFFFBBF24) : const Color(0xFFF59E0B),
          tertiary: isDark ? const Color(0xFFF9A8D4) : const Color(0xFFEC4899),
          surface: isDark ? const Color(0xFF111827) : const Color(0xFFFFFBF5),
          surfaceContainerHighest: isDark
              ? const Color(0xFF253142)
              : const Color(0xFFF4EDE1),
        );
    final baseTextTheme = isDark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF0B1220)
          : const Color(0xFFF7F4EE),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface.withValues(alpha: isDark ? 0.78 : 0.94),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        helperStyle: TextStyle(
          color: colorScheme.primary.withValues(alpha: 0.85),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.secondary,
          foregroundColor: colorScheme.onSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface.withValues(alpha: 0.96),
        indicatorColor: colorScheme.secondary.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          color: isDark ? const Color(0xFFE5F3F1) : const Color(0xFF12303A),
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFE5F3F1) : const Color(0xFF12303A),
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFE5F3F1) : const Color(0xFF12303A),
        ),
        bodyLarge: TextStyle(
          height: 1.4,
          color: isDark ? const Color(0xFFC8D7D5) : const Color(0xFF35515A),
        ),
        bodyMedium: TextStyle(
          height: 1.4,
          color: isDark ? const Color(0xFFB6C8C6) : const Color(0xFF4B646C),
        ),
      ),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  LocalUser? _activeUser;

  void _onAuthenticated(LocalUser user) {
    setState(() {
      _activeUser = user;
    });
  }

  void _logout() {
    ApiService.instance.clearAccessToken();
    setState(() {
      _activeUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_activeUser == null) {
      return AuthPage(onAuthenticated: _onAuthenticated);
    }

    return Dashboard(currentUser: _activeUser!, onLogout: _logout);
  }
}
