import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/local_files.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

/// Login: con nome utente e password (operai senza account Microsoft,
/// tramite il server di login) oppure con Microsoft (ufficio). Mostra nome
/// e logo della società dall'ultimo accesso, se ci sono.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _companyController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _microsoftLoading = false;
  String? _errorMessage;
  String _companyName = AppConfig.instance.companyName;
  Uint8List? _logo;

  bool get _passwordLoginEnabled => AppConfig.instance.loginServerUrl.isNotEmpty;

  @override
  void initState() {
    super.initState();
    AuthService.instance.lastPasswordLogin().then((last) {
      if (!mounted) return;
      _companyController.text = last.company;
      _usernameController.text = last.username;
    });
    _loadBranding();
  }

  Future<void> _loadBranding() async {
    try {
      final cached = await LocalFiles.readCache(LocalFiles.brandingCacheName);
      if (cached == null) return;
      final rows = jsonDecode(cached) as List;
      if (rows.isEmpty) return;
      final row = rows.first as Map<String, dynamic>;
      final name = row['name'] as String? ?? '';
      final logo = row['logoBase64'] as String? ?? '';
      if (!mounted) return;
      setState(() {
        if (name.isNotEmpty) _companyName = name;
        if (logo.isNotEmpty) _logo = base64Decode(logo);
      });
    } catch (_) {
      // Senza copia locale valida si resta su nome e icona di default.
    }
  }

  @override
  void dispose() {
    _companyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  Future<void> _handlePasswordSignIn() async {
    final company = _companyController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (company.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Compila codice azienda, nome utente e password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final success = await AuthService.instance.signInWithPassword(company, username, password);
    if (!mounted) return;
    if (success) return _goHome();
    setState(() {
      _errorMessage = AuthService.instance.lastErrorMessage ?? 'Accesso non riuscito. Riprova.';
      _isLoading = false;
    });
  }

  Future<void> _handleMicrosoftSignIn() async {
    setState(() {
      _microsoftLoading = true;
      _errorMessage = null;
    });
    final success = await AuthService.instance.signIn();
    if (!mounted) return;
    if (success) return _goHome();
    setState(() {
      final detail = AuthService.instance.lastErrorMessage;
      _errorMessage = detail == null ? 'Accesso non riuscito. Riprova.' : 'Accesso non riuscito: $detail';
      _microsoftLoading = false;
    });
  }

  bool get _busy => _isLoading || _microsoftLoading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(context),
              Transform.translate(
                offset: const Offset(0, -36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildCard(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'Salary Solution',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, topInset + 40, 24, 72),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 6)),
              ],
            ),
            child: _logo != null
                ? Image.memory(_logo!, fit: BoxFit.contain)
                : Icon(Icons.schedule_rounded, color: AppColors.primary, size: 48),
          ),
          const SizedBox(height: 18),
          Text(
            _companyName,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Ore, assenze, spese e interventi',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Accedi', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
            _passwordLoginEnabled
                ? 'Con le credenziali ricevute dal tuo datore di lavoro.'
                : 'Con il tuo account aziendale Microsoft.',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          if (_passwordLoginEnabled) ...[
            AutofillGroup(
              child: Column(
                children: [
                  _field(
                    controller: _companyController,
                    label: 'Codice azienda',
                    icon: Icons.business_outlined,
                    capitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _usernameController,
                    label: 'Nome utente',
                    icon: Icons.person_outline,
                    autofill: AutofillHints.username,
                    keyboardType: TextInputType.visiblePassword,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    autofill: AutofillHints.password,
                    obscure: _obscurePassword,
                    focusNode: _passwordFocus,
                    action: TextInputAction.done,
                    onSubmitted: (_) => _busy ? null : _handlePasswordSignIn(),
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ],
              ),
            ),
            if (_errorMessage != null) ...[const SizedBox(height: 14), _errorBox()],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _handlePasswordSignIn,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              child: _isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Accedi'),
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('oppure', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
                Expanded(child: Divider(color: AppColors.border)),
              ],
            ),
            const SizedBox(height: 16),
          ] else if (_errorMessage != null) ...[
            _errorBox(),
            const SizedBox(height: 16),
          ],
          OutlinedButton.icon(
            onPressed: _busy ? null : _handleMicrosoftSignIn,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              minimumSize: const Size.fromHeight(50),
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            icon: _microsoftLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const _MicrosoftLogo(),
            label: const Text('Accedi con Microsoft'),
          ),
        ],
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? autofill,
    bool obscure = false,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    TextInputAction action = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
    Widget? suffix,
  }) {
    final radius = BorderRadius.circular(14);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      textInputAction: action,
      autofillHints: autofill == null ? null : [autofill],
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
      ),
    );
  }
}

/// I quattro quadrati colorati di Microsoft, disegnati (niente immagini).
class _MicrosoftLogo extends StatelessWidget {
  const _MicrosoftLogo();

  @override
  Widget build(BuildContext context) {
    Widget square(Color c) => Container(width: 8, height: 8, color: c);
    return SizedBox(
      width: 18,
      height: 18,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [square(const Color(0xFFF25022)), square(const Color(0xFF7FBA00))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [square(const Color(0xFF00A4EF)), square(const Color(0xFFFFB900))]),
        ],
      ),
    );
  }
}
