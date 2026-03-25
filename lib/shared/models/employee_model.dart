class EmployeeModel {
  final String id;
  final String? authUserId;
  final String fullName;
  final String employeeCode;
  final String email;
  final String? groupId;
  final String? faceToken;
  final String? facePhotoUrl;
  final String accessType;
  final bool isActive;
  final Map<String, dynamic>? group;
  final Map<String, dynamic>? position;

  const EmployeeModel({
    required this.id,
    this.authUserId,
    required this.fullName,
    required this.employeeCode,
    required this.email,
    this.groupId,
    this.faceToken,
    this.facePhotoUrl,
    required this.accessType,
    required this.isActive,
    this.group,
    this.position,
  });

  factory EmployeeModel.fromMap(Map<String, dynamic> map) {
    return EmployeeModel(
      id: map['id'] ?? '',
      authUserId: map['auth_user_id'],
      fullName: map['full_name'] ?? '',
      employeeCode: map['employee_code'] ?? '',
      email: map['email'] ?? '',
      groupId: map['group_id'],
      faceToken: map['face_token'],
      facePhotoUrl: map['face_photo_url'],
      accessType: map['access_type'] ?? 'staff',
      isActive: map['is_active'] ?? false,
      group: map['group'] as Map<String, dynamic>?,
      position: map['position'] as Map<String, dynamic>?,
    );
  }
}
