import 'dart:convert';

class ClientProject {
  final String id;
  final String name;
  final String? sector;
  final String? teamSize;
  final String? mainChallenge;
  final String? budget;
  final DateTime createdAt;

  const ClientProject({
    required this.id,
    required this.name,
    this.sector,
    this.teamSize,
    this.mainChallenge,
    this.budget,
    required this.createdAt,
  });

  /// Returns context map injected into every Gemini query.
  Map<String, String?> get contextMap => {
        'projectName': name,
        if ((sector ?? '').isNotEmpty) 'sector': sector,
        if ((teamSize ?? '').isNotEmpty) 'teamSize': teamSize,
        if ((mainChallenge ?? '').isNotEmpty) 'mainChallenge': mainChallenge,
        if ((budget ?? '').isNotEmpty) 'budget': budget,
      };

  ClientProject copyWith({
    String? name,
    String? sector,
    String? teamSize,
    String? mainChallenge,
    String? budget,
  }) =>
      ClientProject(
        id: id,
        name: name ?? this.name,
        sector: sector ?? this.sector,
        teamSize: teamSize ?? this.teamSize,
        mainChallenge: mainChallenge ?? this.mainChallenge,
        budget: budget ?? this.budget,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sector': sector,
        'teamSize': teamSize,
        'mainChallenge': mainChallenge,
        'budget': budget,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ClientProject.fromJson(Map<String, dynamic> json) => ClientProject(
        id: json['id'] as String,
        name: json['name'] as String,
        sector: json['sector'] as String?,
        teamSize: json['teamSize'] as String?,
        mainChallenge: json['mainChallenge'] as String?,
        budget: json['budget'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );

  static String encode(ClientProject p) => jsonEncode(p.toJson());
  static ClientProject? decode(String s) {
    try {
      final m = jsonDecode(s);
      if (m is Map<String, dynamic>) return ClientProject.fromJson(m);
    } catch (_) {}
    return null;
  }
}
