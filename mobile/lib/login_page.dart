import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'app_theme.dart';
import 'motion.dart';
import 'session_cache.dart';
import 'widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.api,
    required this.onSignedIn,
    this.onFirstFrame,
  });

  final ApiClient api;
  final void Function(Map<String, dynamic> user) onSignedIn;

  /// Fired once this page has painted its first frame, so the shell can drop
  /// the splash it is holding over the top of it.
  final VoidCallback? onFirstFrame;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _mobile = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  bool _rememberMe = false;
  bool _showPassword = false;

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
    _loadRememberedCredentials();
    final first = widget.onFirstFrame;
    if (first != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => first());
    }
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

  Future<void> _loadRememberedCredentials() async {
    try {
      final credentials = await SessionCache.loadRememberedCredentials();
      if (!mounted || credentials == null) return;
      setState(() {
        _mobile.text = credentials.mobile;
        _password.text = credentials.password;
        _rememberMe = true;
      });
    } catch (e) {
      if (mounted) {
        toastError(context, 'Could not load remembered sign-in details.');
      }
    }
  }

  Future<void> _setRememberMe(bool value) async {
    setState(() => _rememberMe = value);
    if (value) return;
    try {
      await SessionCache.clearRememberedCredentials();
    } catch (e) {
      if (!mounted) return;
      setState(() => _rememberMe = true);
      toastError(context, 'Could not remove saved sign-in details.');
    }
  }

  Future<void> _submit() async {
    final mobile = _digits(_mobile.text.trim());
    if (!RegExp(r'^[0-9]{10}$').hasMatch(mobile)) {
      toastError(context, 'Enter your 10 digit mobile number.');
      return;
    }
    if (_password.text.isEmpty) {
      toastError(context, 'Enter your password.');
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final user = _registerMode
          ? await widget.api.register(
              mobile: mobile,
              password: _password.text,
              name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            )
          : await widget.api.login(mobile, _password.text);
      if (!_registerMode) {
        try {
          if (_rememberMe) {
            await SessionCache.saveRememberedCredentials(
              mobile: mobile,
              password: _password.text,
            );
          } else {
            await SessionCache.clearRememberedCredentials();
          }
        } catch (e) {
          if (mounted) {
            setState(() => _rememberMe = false);
            toastError(
              context,
              'Signed in, but could not save sign-in details securely.',
            );
          }
        }
      }
      widget.onSignedIn(user);
    } on ApiException catch (e) {
      if (mounted) toastError(context, e.message);
    } catch (_) {
      if (mounted) {
        toastError(context, 'Could not reach the server. Check the API URL.');
      }
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
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          // The page is exactly the screen: the intro is laid out at the top and
          // the sheet is expanded into whatever height is left, so the page
          // never grows past the viewport and never scrolls. The room under the
          // buttons inside the sheet adapts to the device instead.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'logo.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.home_work_outlined,
                                size: 36,
                                color: Colors.white,
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Manage your rooms, collect rent, stay organized.',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.secondaryText,
                          ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              // Full-bleed sign-in sheet: no side margins, so the left, right
              // and bottom edges meet the screen, with a deep round on top.
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border: const Border(
                      top: BorderSide(color: AppColors.border),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(36),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        blurRadius: 28,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  child: Text(
                                    _registerMode
                                        ? 'Create account'
                                        : 'Sign in',
                                    key: ValueKey(_registerMode),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                if (_registerMode) ...[
                                  TextField(
                                    controller: _name,
                                    decoration: const InputDecoration(
                                      labelText: 'Name (optional)',
                                    ),
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.name],
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                TextField(
                                  controller: _mobile,
                                  decoration: const InputDecoration(
                                    labelText: 'Mobile number',
                                    hintText: 'Enter mobile number',
                                    prefixText: '+91 ',
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [
                                    AutofillHints.telephoneNumber,
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _password,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    helperText: _registerMode
                                        ? '8+ characters with upper, lower case and a number'
                                        : null,
                                    suffixIcon: IconButton(
                                      tooltip: _showPassword
                                          ? 'Hide password'
                                          : 'Show password',
                                      onPressed: () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                                      icon: Icon(
                                        _showPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                    ),
                                  ),
                                  obscureText: !_showPassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  onSubmitted: (_) => _submit(),
                                ),
                                if (!_registerMode) ...[
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: _rememberMe,
                                        onChanged: _busy
                                            ? null
                                            : (value) => _setRememberMe(
                                                value ?? false,
                                              ),
                                      ),
                                      const Text('Remember me'),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 36),
                                PressScale(
                                  enabled: !_busy,
                                  child: FilledButton(
                                    onPressed: _busy ? null : _submit,
                                    child: _busy
                                        ? const SizedBox(
                                            height: 18,
                                            width: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 250,
                                            ),
                                            child: Text(
                                              _registerMode
                                                  ? 'Register'
                                                  : 'Sign in',
                                              key: ValueKey(_registerMode),
                                            ),
                                          ),
                                  ),
                                ),
                                PressScale(
                                  enabled: !_busy,
                                  child: TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                            _registerMode = !_registerMode;
                                          }),
                                    child: Text(
                                      _registerMode
                                          ? 'Already have an account? Sign in'
                                          : 'New landlord? Create an account',
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
            ],
          ),
        ),
      ),
    );
  }
}
