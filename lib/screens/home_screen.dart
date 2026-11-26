import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../core/day_parts.dart';
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
import 'project_report_screen.dart';
import 'ore_progetti_screen.dart';
import 'service_detail_screen.dart';
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
  double? _vacationHours;
  ServiceAssignment? _nextService;
  bool _nextServiceLoaded = false;
  int? _pendingApprovalsCount;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _loadCurrentUser();
    _loadBranding();
    _loadTodaySummary();
    _loadVacation();

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
      DayRules.current = DayRules.parse(user.dayRules) ?? const DayRules();
      AppUser.current = user;
      setState(() {
        _currentUser = user;
        _userError = null;
      });
      _loadTodaySummary();
      if (user.canApprove) {
        final results = await Future.wait([
          BcApiService.instance.fetchPendingApprovals().then((l) => l.length).catchError((_) => 0),
          BcApiService.instance.fetchVacationApprovals().then((l) => l.length).catchError((_) => 0),
        ]);
        setState(() => _pendingApprovalsCount = results[0] + results[1]);
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
  Future<void> _loadVacation() async {
    try {
      final hours = await BcApiService.instance.fetchVacationBalanceHours();
      if (mounted) setState(() => _vacationHours = hours);
    } catch (_) {
      // Senza rete il riquadro mostra "–".
    }
  }

  Future<void> _loadTodaySummary() async {
    // Totale della giornata: ore di progetto più ore stipendio Service.
    final entries = await LocalDbService.instance.getTimeEntriesForDate(DateTime.now());
    final serviceHours = await LocalDbService.instance.getServiceSalaryHoursForDate(DateTime.now());
    if (mounted) setState(() => _hoursToday = entries.fold(serviceHours, (sum, e) => sum + e.hoursWorked));
    if (_currentUser?.hasServiceModule != true) return;
    try {
      final now = DateTime.now();
      final assignments = await BcApiService.instance.fetchServiceAssignments();
      final today = assignments.where((a) =>
          a.allocationDate.year == now.year &&
          a.allocationDate.month == now.month &&
          a.allocationDate.day == now.day &&
          a.state != ServiceState.finished);
      // Prossimo intervento: il primo non terminato da oggi in avanti, per
      // giorno e ora pianificata.
      final startOfToday = DateTime(now.year, now.month, now.day);
      final upcoming = assignments
          .where((a) => a.state != ServiceState.finished && !a.allocationDate.isBefore(startOfToday))
          .toList()
        ..sort((a, b) {
          final byDate = a.allocationDate.compareTo(b.allocationDate);
          if (byDate != 0) return byDate;
          return (a.startingTime ?? '99:99').compareTo(b.startingTime ?? '99:99');
        });
      if (mounted) {
        setState(() {
          _servicesToday = today.length;
          _nextService = upcoming.isEmpty ? null : upcoming.first;
          _nextServiceLoaded = true;
        });
      }
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
        setState(
            () => _loadError = fromCache ? 'Offline: quanto registrato viene inviato al ritorno della rete.' : null);
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
      // Niente barra in alto: Esci sta nell'intestazione blu.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([_loadProjects(), _loadCurrentUser(), _loadBranding(), _loadVacation()]);
              await _loadTodaySummary();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
                const Text('Cosa vuoi fare?',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                _buildTileGrid([
                  ModuleTile(
                    icon: Icons.work_outline_rounded,
                    color: AppColors.primary,
                    label: 'Ore progetti',
                    subtitle: 'Registra le ore di lavoro',
                    onTap: () => _open(const OreProgettiScreen()),
                  ),
                  ModuleTile(
                    icon: Icons.assignment_outlined,
                    color: const Color(0xFF0B7A9C),
                    label: 'Bollettino a regia',
                    subtitle: 'Materiale e manodopera',
                    onTap: () => _open(const ProjectReportsScreen()),
                  ),
                  // Sezione Service: interventi assegnati dalla Dispatch Board,
                  // solo per chi ha il modulo (flag "Tecnico Service" in BC).
                  if (_currentUser?.hasServiceModule == true)
                    ModuleTile(
                      icon: Icons.build_outlined,
                      color: const Color(0xFF0E8C78),
                      label: 'Interventi',
                      subtitle: _servicesToday == null || _servicesToday == 0
                          ? 'Assistenza clienti'
                          : '$_servicesToday da fare oggi',
                      onTap: () => _open(const ServiceListScreen()),
                    ),
                  ModuleTile(
                    icon: Icons.beach_access_outlined,
                    color: const Color(0xFFD9692E),
                    label: 'Ferie e assenze',
                    subtitle: 'Ferie, malattia, infortunio',
                    onTap: () => _open(const FerieAssenzeScreen()),
                  ),
                  if (_currentUser?.hasExpensesModule == true)
                    ModuleTile(
                      icon: Icons.receipt_long_outlined,
                      color: const Color(0xFF6A52E0),
                      label: 'Note spese',
                      subtitle: 'Spese con ricevuta',
                      onTap: () => _open(const NoteSpeseScreen()),
                    ),
                  if (_currentUser?.canApprove == true)
                    ModuleTile(
                      icon: Icons.fact_check_outlined,
                      color: const Color(0xFFC98A0A),
                      label: 'Approvazioni',
                      subtitle: (_pendingApprovalsCount ?? 0) == 0
                          ? 'Nessuna in attesa'
                          : '${_pendingApprovalsCount!} in attesa',
                      badgeCount: _pendingApprovalsCount,
                      onTap: () => _open(const ApprovalsScreen()),
                    ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Piastrelle a due per riga, tutte della stessa misura.
  Widget _buildTileGrid(List<Widget> tiles) {
    const height = 112.0;
    const gap = 12.0;
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
      rows.add(SizedBox(
        height: height,
        child: Row(children: [
          Expanded(child: tiles[i]),
          const SizedBox(width: gap),
          // Ultima piastrella sola: stessa misura delle altre, spazio vuoto
          // accanto (scelta di Michele, 22.11.2026).
          Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  /// Apre un modulo e, al ritorno, aggiorna riepilogo e approvazioni.
  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) {
      _loadTodaySummary();
      _loadCurrentUser();
      _loadVacation();
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
              IconButton(
                onPressed: _signOut,
                tooltip: 'Esci',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.logout_rounded, color: Colors.white.withValues(alpha: 0.9), size: 22),
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
    final isTechnician = _currentUser?.hasServiceModule == true;
    return Column(
      children: [
        // Tecnici: il prossimo intervento in grande, in cima (richiesta del
        // cliente, 26.11.2026), con il numero di interventi di oggi.
        if (isTechnician) ...[
          _buildNextServiceCard(),
          const SizedBox(height: 10),
        ],
        Row(children: [
          Expanded(
            child: _SummaryCard(
              icon: Icons.schedule,
              label: 'Ore inserite oggi',
              value: '${_formatHours(_hoursToday)} h',
              onTap: () => _open(const OreProgettiScreen()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryCard(
              icon: Icons.beach_access_outlined,
              label: 'Ferie residue',
              value: _vacationHours == null ? '–' : '${_formatHours(_vacationHours!)} h',
              onTap: () => _open(const FerieAssenzeScreen()),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildNextServiceCard() {
    const accent = Color(0xFF0E8C78);
    final next = _nextService;
    final todayCount = _servicesToday ?? 0;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _open(next == null ? const ServiceListScreen() : ServiceDetailScreen(assignment: next)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
                    child: const Icon(Icons.build_outlined, size: 18, color: accent),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Prossimo intervento',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent)),
                  ),
                  Text(
                    todayCount == 1 ? '1 da fare oggi' : '$todayCount da fare oggi',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (next == null)
                Text(
                  _nextServiceLoaded ? 'Nessun intervento in programma.' : 'Caricamento…',
                  style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
                )
              else ...[
                Text(
                  _nextServiceWhenLong(next),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  next.customerName.isEmpty ? next.orderNo : next.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                if (next.orderDescription.isNotEmpty)
                  Text(next.orderDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                if (next.fullAddress.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(next.fullAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (next.fullAddress.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                            Uri.parse('https://maps.apple.com/?q=${Uri.encodeComponent(next.fullAddress)}'),
                            mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.navigation_outlined, size: 18),
                        label: const Text('Naviga'),
                        style: OutlinedButton.styleFrom(foregroundColor: accent),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _open(const ServiceListScreen()),
                      style: TextButton.styleFrom(foregroundColor: accent),
                      child: const Text('Tutti gli interventi'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "Oggi 09:30–12:00", "Domani 08:00", "Gio 26.11 14:00".
  String _nextServiceWhenLong(ServiceAssignment a) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(a.allocationDate.year, a.allocationDate.month, a.allocationDate.day);
    final diff = day.difference(today).inDays;
    String dayLabel;
    if (diff <= 0) {
      dayLabel = 'Oggi';
    } else if (diff == 1) {
      dayLabel = 'Domani';
    } else {
      final l = DateFormat('EEE d.MM', 'it_IT').format(day);
      dayLabel = l[0].toUpperCase() + l.substring(1);
    }
    final time = a.plannedTimeRange;
    return time == null ? dayLabel : '$dayLabel $time';
  }

  String _formatHours(double hours) =>
      hours.toStringAsFixed(hours == hours.roundToDouble() ? 0 : (hours * 10 == (hours * 10).roundToDouble() ? 1 : 2));

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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.accentBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
