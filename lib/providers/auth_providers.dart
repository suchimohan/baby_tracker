import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core_providers.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// Current signed-in user (null when signed out).
/// In local demo mode a fixed pseudo-user id is used instead.
final currentUserIdProvider = Provider<String?>((ref) {
  final demo = ref.watch(demoModeProvider);
  if (demo) return 'demo-user';
  ref.watch(authStateProvider); // rebuild on auth changes
  return ref.watch(supabaseClientProvider).auth.currentUser?.id;
});

/// Local demo mode: app fully usable without a backend; everything stays
/// queued in Hive. Toggled from the sign-in screen.
class DemoModeNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(localStoreProvider).getMeta('demo_mode') == 'true';

  Future<void> enable() async {
    await ref.read(localStoreProvider).setMeta('demo_mode', 'true');
    state = true;
  }

  Future<void> disable() async {
    await ref.read(localStoreProvider).setMeta('demo_mode', null);
    state = false;
  }
}

final demoModeProvider =
    NotifierProvider<DemoModeNotifier, bool>(DemoModeNotifier.new);

class AuthController {
  AuthController(this._ref);
  final Ref _ref;

  SupabaseClient get _client => _ref.read(supabaseClientProvider);

  Future<void> signIn({required String email, required String password}) =>
      _client.auth.signInWithPassword(email: email, password: password);

  /// COPPA §8.1: sign-up sends a confirmation email; data collection only
  /// begins after the parent verifies ownership of the address.
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) =>
      _client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );

  Future<void> signInWithGoogle() async {
    // Configure with your iOS client ID from GoogleService-Info.plist.
    // The serverClientId (web client ID) is required for the ID token.
    const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
    final googleSignIn = GoogleSignIn(
      clientId: iosClientId.isEmpty ? null : iosClientId,
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    final user = await googleSignIn.signIn();
    if (user == null) return; // cancelled by user
    final auth = await user.authentication;
    final idToken = auth.idToken;
    if (idToken == null) throw Exception('Google sign-in returned no ID token');
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
  }

  Future<void> signInWithApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256(rawNonce);
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    final idToken = credential.identityToken;
    if (idToken == null) throw Exception('Apple sign-in returned no ID token');
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    // COPPA: no child data left on a signed-out device.
    await _ref.read(localStoreProvider).clearAll();
  }
}

final authControllerProvider = Provider<AuthController>(AuthController.new);

String _generateNonce([int length = 32]) {
  const chars =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final rng = Random.secure();
  return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
}

String _sha256(String input) =>
    sha256.convert(utf8.encode(input)).toString();
