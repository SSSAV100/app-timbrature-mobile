import 'project_task.dart';

/// Tipologia di progetto, come definita in Business Central (vedi
/// specifica funzionale, sezione 5). Determina se l'app richiederà anche
/// il bollettino di intervento (moduli futuri).
enum ProjectType { standard, service }

/// Rappresenta un progetto/cantiere/commessa (Job in Business Central)
/// assegnato all'utente corrente, con i relativi task/attività. BC resta
/// l'unica fonte di verità: questo oggetto è solo la proiezione letta
/// dalle API per l'uso nell'app.
class Project {
  final String id; // Job No. in Business Central
  final String description;
  final ProjectType type;
  final List<ProjectTask> tasks;

  const Project({
    required this.id,
    required this.description,
    required this.type,
    this.tasks = const [],
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    final rawType =
        (json['projectType'] as String? ?? 'Standard').toLowerCase();
    final rawTasks = json['tasks'] as List<dynamic>? ?? [];
    return Project(
      id: json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: rawType == 'service' ? ProjectType.service : ProjectType.standard,
      tasks: rawTasks
          .map((e) => ProjectTask.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

