import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/config.dart';
import '../core/local_files.dart';
import '../core/theme.dart';
import '../models/app_user.dart';
import '../models/service_assignment.dart';
import '../services/auth_service.dart';
import '../services/bc_api_service.dart';
import '../services/local_db_service.dart';
import '../services/sync_service.dart';
import '../widgets/module_tile.dart';
import 'approvals_screen.dart';
import 'ferie_assenze_screen.dart';
import 'login_screen.dart';
import 'note_spese_screen.dart';
import 'ore_progetti_screen.dart';
import 'service_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Stato della lettura dei cantieri: offline o errore di BC.
  String? _loadError;

  /// Errore nella lettura del profilo (GET /me): senza profilo mancano nome,
  /// Approvazioni e Interventi, quindi va detto invece di mostrare solo "...".
  String? _userError;

  AppUser? _currentUser;

  // Intestazione e riepilogo del giorno.
  String _companyName = '';
  Uint8List? _companyLogo;
  double _hoursToday = 0;
  int? _servicesToday;
  int? _pendingApprovalsCount;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _loadCurrentUser();
    _loadBranding();
    _loadTodaySummary();

    // Ogni volta che la connessione torna disponibile, invia quanto
    // registrato offline (vedi SyncService).
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        SyncService.instance.syncAll();
      }
    });
    SyncService.instance.syncAll();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// Legge l'utente corrente e i suoi ruoli da Business Central. Se l'utente
  /// ha un ruolo di approvatore, legge anche il numero di richieste in
  /// sospeso, per mostrare il badge sulla piastrella Approvazioni. Se la
  /// richiesta fallisce (es. offline al primo avvio), la piastrella
  /// Approvazioni resta semplicemente nascosta: non è un errore bloccante,
  /// e i ruoli vengono ricontrollati ad ogni apertura dell'app.
  Future<void> _signOut() async {
    await SyncService.instance.syncAll();
    final unsent = await LocalDbService.instance.countUnsent();
    if (!mounted) return;
    if (unsent > 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Dati non ancora inviati'),
          content: Text(
            'Sul telefono ci sono $unsent registrazioni non ancora arrivate in Business Central. '
            'Collegati alla rete e attendi l\'invio (o correggi quelle in errore) prima di uscire, '
            'altrimenti andrebbero perse.',
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Uscire?'),
        content: const Text('Per rientrare servirà di nuovo il login.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Esci')),
        ],
      ),
    );
    if (confirm != true) return;
    await AuthService.instance.signOut();
    await LocalDbService.instance.clearAll();
    await LocalFiles.clearCache();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = await BcApiService.instance.fetchCurrentUser();
      setState(() {
        _currentUser = user;
        _userError = null;
      });
      _loadTodaySummary();
      if (user.canApprove) {
        final approvals = await BcApiService.instance.fetchPendingApprovals();
        setState(() => _pendingApprovalsCount = approvals.length);
      }
    } catch (e, stackTrace) {
      developer.log('fetchCurrentUser fallita', name: 'HomeScreen', error: e, stackTrace: stackTrace);
      // Senza profilo le piastrelle Approvazioni e Interventi restano nascoste.
      if (mounted) {
        setState(() => _userError = e is BcApiException
            ? 'Profilo non letto da Business Central: $e'
            : 'Profilo non disponibile: verifica la connessione o rifai il login.');
      }
    }
  }

  Future<void> _loadBranding() async {
    try {
      final branding = await BcApiService.instance.fetchCompanyBranding();
      if (mounted) {
        setState(() {
          _companyName = branding.name;
          _companyLogo = branding.logo;
        });
      }
    } catch (e) {
      developer.log('fetchCompanyBranding fallita', name: 'HomeScreen', error: e);
    }
  }

  /// Ore inserite oggi (dal telefono) e interventi di oggi ancora da chiudere.
  Future<void> _loadTodaySummary() async {
    final entries = await LocalDbService.instance.getTimeEntriesForDate(DateTime.now());
    if (mounted) setState(() => _hoursToday = entries.fold(0.0, (sum, e) => sum + e.hoursWorked));
    if (_currentUser?.hasServiceModule != true) return;
    try {
      final now = DateTime.now();
      final assignments = await BcApiService.instance.fetchServiceAssignments();
      final today = assignments.where((a) =>
          a.allocationDate.year == now.year &&
          a.allocationDate.month == now.month &&
          a.allocationDate.day == now.day &&
          a.state != ServiceState.finished);
      if (mounted) setState(() => _servicesToday = today.length);
    } catch (_) {
      // Riepilogo facoltativo: senza dati resta nascosto.
    }
  }

  /// Aggiorna la copia locale dei cantieri (per lavorare offline in Ore su
  /// progetti e Note spese) e segnala se BC non è raggiungibile.
  Future<void> _loadProjects() async {
    try {
      await BcApiService.instance.fetchAssignedProjects();
      final fromCache = BcApiService.instance.projectsFromCache;
      if (mounted) {
        setState(() => _loadError = fromCache
            ? 'Offline: quanto registrato viene inviato al ritorno della rete.'
            : null);
      }
    } catch (e, stackTrace) {
      developer.log('fetchAssignedProjects fallita', name: 'HomeScreen', error: e, stackTrace: stackTrace);
      if (mounted) {
        // Errore restituito da BC: lo si mostra per intero, altrimenti non si
        // distingue da un problema di rete.
        setState(() => _loadError = e is BcApiException
            ? 'Impossibile aggiornare l\'elenco cantieri. $e'
            : 'Impossibile aggiornare l\'elenco cantieri (verifica la connessione).');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Esci', onPressed: _signOut),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_loadProjects(), _loadCurrentUser(), _loadBranding()]);
          await _loadTodaySummary();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildTodaySummary(),
            if (_userError != null) ...[
              const SizedBox(height: 8),
              Text(_userError!, style: const TextStyle(fontSize: 11, color: Colors.orange)),
            ],
            if (_loadError != null) ...[
              const SizedBox(height: 8),
              Text(_loadError!, style: const TextStyle(fontSize: 11, color: Colors.orange)),
            ],
            const SizedBox(height: 24),
            const Text('Cosa vuoi fare?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              // Le ombre colorate delle piastrelle escono dai bordi.
              clipBehavior: Clip.none,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: [
                ModuleTile(
                  icon: Icons.work_outline_rounded,
                  colors: const [Color(0xFF2A93F2), Color(0xFF0B63BF)],
                  label: 'Ore progetti',
                  subtitle: 'Registra le ore di lavoro',
                  onTap: () => _open(const OreProgettiScreen()),
                ),
                // Sezione Service: interventi assegnati dalla Dispatch Board,
                // solo per chi ha il modulo (flag "Tecnico Service" in BC).
                if (_currentUser?.hasServiceModule == true)
                  ModuleTile(
                    icon: Icons.build_outlined,
                    colors: const [Color(0xFF1CB59C), Color(0xFF0A7A68)],
                    label: 'Interventi',
                    subtitle: _servicesToday == null || _servicesToday == 0
                        ? 'Assistenza clienti'
                        : '$_servicesToday da fare oggi',
                    onTap: () => _open(const ServiceListScreen()),
                  ),
                ModuleTile(
                  icon: Icons.beach_access_outlined,
                  colors: const [Color(0xFFF59A5B), Color(0xFFD65F24)],
                  label: 'Ferie e assenze',
                  subtitle: 'Ferie, malattia, infortunio',
                  onTap: () => _open(const FerieAssenzeScreen()),
                ),
                ModuleTile(
                  icon: Icons.receipt_long_outlined,
                  colors: const [Color(0xFF8C74FF), Color(0xFF5B41D9)],
                  label: 'Note spese',
                  subtitle: 'Spese con ricevuta',
                  onTap: () => _open(const NoteSpeseScreen()),
                ),
                if (_currentUser?.canApprove == true)
                  ModuleTile(
                    icon: Icons.fact_check_outlined,
                    colors: const [Color(0xFFF4B740), Color(0xFFCF8A06)],
                    label: 'Approvazioni',
                    subtitle: (_pendingApprovalsCount ?? 0) == 0
                        ? 'Nessuna in attesa'
                        : '${_pendingApprovalsCount!} in attesa',
                    badgeCount: _pendingApprovalsCount,
                    onTap: () => _open(const ApprovalsScreen()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Apre un modulo e, al ritorno, aggiorna riepilogo e approvazioni.
  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) {
      _loadTodaySummary();
      _loadCurrentUser();
    });
  }

  Widget _buildHeader() {
    final today = DateFormat('EEEE d MMMM', 'it_IT').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Logo di Informazioni società (BC), su fondo bianco perché
              // i loghi sono pensati per sfondo chiaro.
              Container(
                height: 48,
                constraints: const BoxConstraints(minWidth: 48, maxWidth: 140),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: _companyLogo != null
                    ? Image.memory(_companyLogo!, fit: BoxFit.contain)
                    : Center(
                        child: Text(
                          _initials(_companyName.isEmpty ? AppConfig.instance.companyName : _companyName),
                          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _companyName.isEmpty ? AppConfig.instance.companyName : _companyName,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Ciao, ${_currentUser?.fullName ?? '...'}',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            today[0].toUpperCase() + today.substring(1),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySummary() {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.schedule,
            label: 'Ore inserite oggi',
            value: '${_hoursToday.toStringAsFixed(_hoursToday == _hoursToday.roundToDouble() ? 0 : 2)} h',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const OreProgettiScreen()))
                .then((_) => _loadTodaySummary()),
          ),
        ),
        if (_currentUser?.hasServiceModule == true) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryCard(
              icon: Icons.build_outlined,
              label: 'Interventi oggi',
              value: _servicesToday == null ? '–' : '$_servicesToday',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const ServiceListScreen()))
                  .then((_) => _loadTodaySummary()),
            ),
          ),
        ],
      ],
    );
  }

  String _initials(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) return '?';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SummaryCard({required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.accentBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
