import 'package:flutter/material.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/local_auth.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({required this.onAuthenticated, super.key});

  final ValueChanged<LocalUser> onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final LocalAuthService _authService = LocalAuthService.instance;

  bool _isLoginMode = true;
  AppUserRole _selectedRole = AppUserRole.invigilator;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isLoginMode = !_isLoginMode;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isSubmitting = true);

    try {
      if (_isLoginMode) {
        final user = await ApiService.instance.login(
          username: username,
          password: password,
        );
        widget.onAuthenticated(user);
        return;
      }

      final user = await ApiService.instance.signUp(
        username: username,
        password: password,
        role: _selectedRole,
      );
      _showMessage('Account created successfully.');
      widget.onAuthenticated(user);
    } catch (error) {
      final fallbackUser = _isLoginMode
          ? _authService.login(username: username, password: password)
          : null;
      if (fallbackUser != null) {
        widget.onAuthenticated(fallbackUser);
        return;
      }
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: ClipOval(
                            child: SizedBox.square(
                              dimension: 104,
                              child: Image.asset(
                                'assets/applogo_transparent.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _isLoginMode ? 'Log In' : 'Sign Up',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isLoginMode
                              ? 'Sign into your account.'
                              : 'Create an account for your assigned role.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Username is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (value) {
                            final password = value?.trim() ?? '';
                            if (password.isEmpty) {
                              return 'Password is required';
                            }
                            if (!_isLoginMode && password.length < 4) {
                              return 'Password must be at least 4 characters';
                            }
                            return null;
                          },
                        ),
                        if (!_isLoginMode) ...[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<AppUserRole>(
                            initialValue: _selectedRole,
                            decoration: const InputDecoration(
                              labelText: 'Role',
                              prefixIcon: Icon(Icons.verified_user_outlined),
                            ),
                            items: AppUserRole.values
                                .map(
                                  (role) => DropdownMenuItem(
                                    value: role,
                                    child: Text(role.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (role) {
                              if (role == null) {
                                return;
                              }

                              setState(() {
                                _selectedRole = role;
                              });
                            },
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            child: _isSubmitting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(_isLoginMode ? 'Log In' : 'Sign Up'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _isSubmitting ? null : _toggleMode,
                            child: Text(
                              _isLoginMode
                                  ? 'No account? Switch to Sign Up'
                                  : 'Have an account? Switch to Log In',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
