/// L'utente autenticato, con i ruoli assegnati in Business Central.
///
/// Ogni dipendente ha sempre almeno il ruolo "dipendente"; può in aggiunta
/// avere "responsabileCantiere" (approva lo straordinario sulle commesse di
/// cui è capo cantiere). I ruoli vengono letti da BC ad ogni login, non
/// sono mai decisi lato app.
class AppUser {
  final String employeeId;
  final String fullName;
  final Set<String> roles;

  /// Sezioni dell'app da mostrare ("progetti", "service"), decise in BC
  /// (flag "Tecnico Service" sulla scheda dipendente).
  final Set<String> modules;

  /// Limiti della giornata dalla Setup (null = valori predefiniti).
  final String? dayRules;

  /// Apprendista oggi (malattia: certificato dal primo giorno).
  final bool apprentice;

  /// Ferie: primo giorno chiedibile (preavviso in giorni lavorativi).
  final DateTime? firstVacationDate;

  /// Ultimo profilo letto da BC (home), per i controlli delle altre schermate.
  static AppUser? current;

  const AppUser({
    required this.employeeId,
    required this.fullName,
    required this.roles,
    this.modules = const {'progetti'},
    this.dayRules,
    this.apprentice = false,
    this.firstVacationDate,
  });

  bool get hasServiceModule => modules.contains('service');

  /// Note spese nell'app: solo se attivo nella Setup di BC ("spese").
  bool get hasExpensesModule => modules.contains('spese');

  bool get isResponsabileCantiere => roles.contains('responsabileCantiere');

  /// Approva le ferie (primo o secondo approvatore).
  bool get isVacationApprover => roles.contains('approvatoreFerie');

  /// True se l'utente ha almeno un ruolo che dà accesso alla schermata
  /// Approvazioni nell'app.
  bool get canApprove => isResponsabileCantiere || isVacationApprover;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    // "roles" arriva da BC come stringa con valori separati da virgola
    // (es. "dipendente,responsabileCantiere"), non come array JSON: una
    // pagina API di Business Central non può restituire un array di
    // stringhe scalari (solo array di entità annidate), quindi lato AL è
    // stato esposto così — vedi SS.CurrentUserApi.Page.al.
    final rawRoles = (json['roles'] as String? ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final rawModules = (json['modules'] as String? ?? 'progetti')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    return AppUser(
      employeeId: json['employeeId'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      roles: rawRoles,
      modules: rawModules,
      dayRules: json['dayRules'] as String?,
      apprentice: json['apprentice'] as bool? ?? false,
      firstVacationDate: DateTime.tryParse(json['firstVacationDate'] as String? ?? ''),
    );
  }
}
