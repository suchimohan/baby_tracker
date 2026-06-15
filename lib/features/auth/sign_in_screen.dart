import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_providers.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _isSignUp = false;
  bool _busy = false;
  String? _error;
  bool _awaitingEmailConfirm = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authControllerProvider);
    try {
      if (_isSignUp) {
        await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          displayName: _name.text.trim(),
        );
        // COPPA §8.1: parental consent = verified email ownership.
        setState(() => _awaitingEmailConfirm = true);
      } else {
        await auth.signIn(email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not reach the server. '
          'Check your connection, or continue in local mode below.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _socialSignIn(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_awaitingEmailConfirm) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 64),
                const SizedBox(height: 16),
                Text('Confirm your email', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'We sent a confirmation link to ${_email.text.trim()}.\n\n'
                  'As a parent or guardian, confirming your email gives us the '
                  'verifiable consent we need before any information about your '
                  'child is collected (COPPA). Tap the link, then sign in.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _awaitingEmailConfirm = false;
                    _isSignUp = false;
                  }),
                  child: const Text('Back to sign in'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.child_friendly,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text('Baby Tracker',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 32),

                // ── Social sign-in ──────────────────────────────────────────
                _GoogleSignInButton(
                  busy: _busy,
                  onPressed: () => _socialSignIn(
                      ref.read(authControllerProvider).signInWithGoogle),
                ),
                const SizedBox(height: 10),
                SignInWithAppleButton(
                  onPressed: _busy
                      ? () {}
                      : () => _socialSignIn(
                          ref.read(authControllerProvider).signInWithApple),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 16),

                // ── Email / password ────────────────────────────────────────
                if (_isSignUp) ...[
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Your name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                      labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password', border: OutlineInputBorder()),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy
                      ? 'Please wait…'
                      : _isSignUp
                          ? 'Create account'
                          : 'Sign in'),
                ),
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(_isSignUp
                      ? 'Have an account? Sign in'
                      : 'New here? Create account'),
                ),
                const Divider(height: 32),
                // ── Local mode ──────────────────────────────────────────────
                OutlinedButton.icon(
                  icon: const Icon(Icons.phone_iphone),
                  label: const Text('Local mode (no account)'),
                  onPressed:
                      _busy ? null : () => ref.read(demoModeProvider.notifier).enable(),
                ),
                const SizedBox(height: 4),
                Text(
                  'Local mode keeps everything on this device only — '
                  'no sync, no account. You can sign up later.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Google-branded sign-in button (Material style — no SDK button provided).
class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed, required this.busy});
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Google "G" logo colours — no external asset needed
          _GoogleG(),
          const SizedBox(width: 10),
          const Text('Sign in with Google',
              style: TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _GoogleG extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final rect = Rect.fromCircle(center: center, radius: r);

    // Blue arc (top-right, left)
    canvas.drawArc(rect, -1.4, 4.4, false,
        Paint()
          ..color = const Color(0xFF4285F4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.25);

    // Red arc (top-left)
    canvas.drawArc(rect, -2.4, 1.0, false,
        Paint()
          ..color = const Color(0xFFEA4335)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.25);

    // Green arc (bottom)
    canvas.drawArc(rect, 1.6, 1.0, false,
        Paint()
          ..color = const Color(0xFF34A853)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.25);

    // Yellow arc (bottom-right)
    canvas.drawArc(rect, 2.6, 0.7, false,
        Paint()
          ..color = const Color(0xFFFBBC05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.25);

    // Horizontal bar of the "G"
    canvas.drawRect(
      Rect.fromLTWH(r - 0.5, r - size.height * 0.14,
          r + 0.5, size.height * 0.28),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(_GoogleGPainter _) => false;
}
