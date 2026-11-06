class CornerInspectionData {
  final String name;
  final double blobArea;
  final bool isDamaged;

  const CornerInspectionData({
    required this.name,
    required this.blobArea,
    required this.isDamaged,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'blobArea': blobArea,
    'isDamaged': isDamaged,
  };

  factory CornerInspectionData.fromJson(Map<String, dynamic> json) => CornerInspectionData(
    name: json['name'] as String,
    blobArea: (json['blobArea'] as num).toDouble(),
    isDamaged: json['isDamaged'] as bool? ?? false,
  );
}

class SideCornerReport {
  final String side;
  final List<CornerInspectionData> corners;
  final String? annotatedImagePath;

  const SideCornerReport({
    required this.side,
    required this.corners,
    this.annotatedImagePath,
  });

  Map<String, dynamic> toJson() => {
    'side': side,
    'corners': corners.map((c) => c.toJson()).toList(),
    'annotatedImagePath': annotatedImagePath,
  };

  factory SideCornerReport.fromJson(Map<String, dynamic> json) => SideCornerReport(
    side: json['side'] as String,
    corners: (json['corners'] as List? ?? [])
        .map((c) => CornerInspectionData.fromJson(c as Map<String, dynamic>))
        .toList(),
    annotatedImagePath: json['annotatedImagePath'] as String?,
  );
}
