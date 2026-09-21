/// L'utente autenticato, con i ruoli assegnati in Business Central.
///
/// Ogni dipendente ha sempre almeno il ruolo "dipendente"; può in aggiunta
/// avere "responsabileCantiere" (approva lo straordinario dei progetti
/// Standard) e/o "responsabileProgetti" (approva il lato Progetti delle
/// ore Service — il lato Salari e l'approvazione "ufficio" per i
/// bollettini senza firma cliente restano gestiti nativamente in Business
/// Central, tramite l'app ufficiale Microsoft Business Central: non sono
/// compito di questa app). I ruoli vengono letti da BC ad ogni login, non
/// sono mai decisi lato app.
class AppUser {
  final String employeeId;
  final String fullName;
  final Set<String> roles;

  const AppUser({
    required this.employeeId,
    required this.fullName,
    required this.roles,
  });

  bool get isResponsabileCantiere => roles.contains('responsabileCantiere');
  bool get isResponsabileProgetti => roles.contains('responsabileProgetti');

  /// True se l'utente ha almeno un ruolo che dà accesso alla schermata
  /// Approvazioni nell'app.
  bool get canApprove => isResponsabileCantiere || isResponsabileProgetti;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final rawRoles = (json['roles'] as List<dynamic>? ?? [])
        .map((e) => e as String)
        .toSet();
    return AppUser(
      employeeId: json['employeeId'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      roles: rawRoles,
    );
  }
}
