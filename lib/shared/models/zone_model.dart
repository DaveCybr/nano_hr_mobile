class ZoneModel {
  final String id;
  final String officeName;
  final String? officeAddress;
  final double latitude;
  final double longitude;
  final int radiusMeters;

  const ZoneModel({
    required this.id,
    required this.officeName,
    this.officeAddress,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  factory ZoneModel.fromMap(Map<String, dynamic> map) {
    return ZoneModel(
      id: map['id'] ?? '',
      officeName: map['office_name'] ?? '',
      officeAddress: map['office_address'],
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      radiusMeters: map['radius_meters'] ?? 200,
    );
  }
}
