import 'project_task.dart';

/// Rappresenta un progetto/cantiere/commessa (Job in Business Central)
/// assegnato all'utente corrente, con i relativi task/attività. BC resta
/// l'unica fonte di verità: questo oggetto è solo la proiezione letta
/// dalle API per l'uso nell'app.
class Project {
  final String id; // Job No. in Business Central
  final String description;
  final List<ProjectTask> tasks;

  const Project({
    required this.id,
    required this.description,
    this.tasks = const [],
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    final rawTasks = json['tasks'] as List<dynamic>? ?? [];
    return Project(
      id: json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      tasks: rawTasks
          .map((e) => ProjectTask.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

