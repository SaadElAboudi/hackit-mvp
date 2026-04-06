import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/project.dart';

const _kProjectKey = 'active_client_project';

class ProjectProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  ClientProject? _activeProject;

  ProjectProvider(this._prefs) {
    _load();
  }

  ClientProject? get activeProject => _activeProject;
  bool get hasProject => _activeProject != null;

  void _load() {
    final raw = _prefs.getString(_kProjectKey);
    if (raw != null && raw.isNotEmpty) {
      _activeProject = ClientProject.decode(raw);
    }
  }

  Future<void> setProject(ClientProject project) async {
    _activeProject = project;
    await _prefs.setString(_kProjectKey, ClientProject.encode(project));
    notifyListeners();
  }

  Future<ClientProject> createProject({
    required String name,
    String? sector,
    String? teamSize,
    String? mainChallenge,
    String? budget,
  }) async {
    final project = ClientProject(
      id: const Uuid().v4(),
      name: name.trim(),
      sector: sector?.trim(),
      teamSize: teamSize?.trim(),
      mainChallenge: mainChallenge?.trim(),
      budget: budget?.trim(),
      createdAt: DateTime.now(),
    );
    await setProject(project);
    return project;
  }

  Future<void> clearProject() async {
    _activeProject = null;
    await _prefs.remove(_kProjectKey);
    notifyListeners();
  }
}
