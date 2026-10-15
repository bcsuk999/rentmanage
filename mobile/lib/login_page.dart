import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'app_theme.dart';
import 'motion.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.api, required this.onSignedIn});

  final ApiClient api;
  final void Function(Map<String, dynamic> user) onSignedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _mobile = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  String? _error;

  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _enter.dispose();
    _mobile.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  String _digits(String v) => v.replaceAll(RegExp(r'[\s-]'), '');

  Future<void> _submit() async {
    final mobile = _digits(_mobile.text.trim());
    if (!RegExp(r'^[0-9]{10}$').hasMatch(mobile)) {
      setState(() => _error = 'Enter your 10-digit mobile number.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = _registerMode
          ? await widget.api.register(
              mobile: mobile,
              password: _password.text,
              name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            )
          : await widget.api.login(mobile, _password.text);
      widget.onSignedIn(user);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Check the API URL.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rent Manager'),
        centerTitle: true,
        elevation: 4,
        shadowColor: AppColors.primary.withValues(alpha: 0.25),
      ),
      body: Center(
        child: Transform.translate(
          offset: const Offset(0, -28),
          child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'logo.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.home_work_outlined,
                              size: 36, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Manage your rooms, collect rent, stay organized.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: AppColors.secondaryText)),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 8,
                      shadowColor: AppColors.primary.withValues(alpha: 0.25),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  _registerMode ? 'Create account' : 'Sign in',
                                  key: ValueKey(_registerMode),
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (_error != null) ...[
                                ShakeOnError(
                                  trigger: _error,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(_error!),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (_registerMode) ...[
                                TextField(
                                  controller: _name,
                                  decoration:
                                      const InputDecoration(labelText: 'Name (optional)'),
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.name],
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextField(
                                controller: _mobile,
                                decoration: const InputDecoration(
                                  labelText: 'Mobile number',
                                  hintText: '10-digit mobile number',
                                  prefixText: '+91 ',
                                ),
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\s-]')),
                                  LengthLimitingTextInputFormatter(14),
                                ],
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.telephoneNumber],
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _password,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  helperText: _registerMode
                                      ? '8+ characters with upper, lower case and a number'
                                      : null,
                                ),
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _submit(),
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 250),
                                        child: Text(
                                          _registerMode ? 'Register' : 'Sign in',
                                          key: ValueKey(_registerMode),
                                        ),
                                      ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _registerMode = !_registerMode;
                                          _error = null;
                                        }),
                                child: Text(_registerMode
                                    ? 'Already have an account? Sign in'
                                    : 'New landlord? Create an account'),
                              ),
                            ],
                          ),
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
    );
  }
}
