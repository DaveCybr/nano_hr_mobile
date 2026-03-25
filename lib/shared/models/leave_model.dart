class LeaveModel {
  final String id;
  final String employeeId;
  final DateTime startDate;
  final DateTime endDate;
  final String type;
  final String reason;
  final String status;
  final DateTime createdAt;

  const LeaveModel({
    required this.id,
    required this.employeeId,
    required this.startDate,
    required this.endDate,
    required this.type,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  factory LeaveModel.fromJson(Map<String, dynamic> json) {
    return LeaveModel(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      type: json['type'] as String,
      reason: json['reason'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employee_id': employeeId,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'type': type,
      'reason': reason,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
