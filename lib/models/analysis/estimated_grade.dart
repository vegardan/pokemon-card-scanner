class SubGrade {
  final String category;
  final double score;
  final String description;
  final Map<String, dynamic>? details;

  const SubGrade({
    required this.category,
    required this.score,
    required this.description,
    this.details,
  });

  Map<String, dynamic> toJson() => {
    'category': category,
    'score': score,
    'description': description,
    if (details != null) 'details': details,
  };

  factory SubGrade.fromJson(Map<String, dynamic> json) => SubGrade(
    category: json['category'] as String,
    score: (json['score'] as num).toDouble(),
    description: json['description'] as String,
    details: json['details'] as Map<String, dynamic>?,
  );
}

class EstimatedGrade {
  final int overallScore;
  final String strategyName;
  final List<SubGrade> subGrades;
  final List<String> notes;

  const EstimatedGrade({
    required this.overallScore,
    required this.strategyName,
    this.subGrades = const [],
    this.notes = const [],
  });

  Map<String, dynamic> toJson() => {
    'overallScore': overallScore,
    'strategyName': strategyName,
    'subGrades': subGrades.map((s) => s.toJson()).toList(),
    'notes': notes,
  };

  factory EstimatedGrade.fromJson(Map<String, dynamic> json) => EstimatedGrade(
    overallScore: json['overallScore'] as int,
    strategyName: json['strategyName'] as String? ?? 'Standard',
    subGrades: (json['subGrades'] as List? ?? [])
        .map((s) => SubGrade.fromJson(s as Map<String, dynamic>))
        .toList(),
    notes: List<String>.from(json['notes'] as List? ?? []),
  );
}
