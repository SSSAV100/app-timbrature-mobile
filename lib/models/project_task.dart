/// Un task/attività appartenente a un progetto (Job Task in Business
/// Central). Letto insieme al progetto tramite l'API assignedProjects
/// (vedi ProjectApi in bc_api_service.dart).
class ProjectTask {
  final String id;
  final String description;

  const ProjectTask({
    required this.id,
    required this.description,
  });

  factory ProjectTask.fromJson(Map<String, dynamic> json) {
    return ProjectTask(
      id: json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}
