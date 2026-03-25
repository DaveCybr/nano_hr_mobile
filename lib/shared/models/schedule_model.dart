class ScheduleModel {
  final String id;
  final String employeeId;
  final String shiftName;
  final String startTime;
  final String endTime;
  final DateTime date;

  const ScheduleModel({
    required this.id,
    required this.employeeId,
    required this.shiftName,
    required this.startTime,
    required this.endTime,
    required this.date,
  });

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    return ScheduleModel(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      shiftName: json['shift_name'] as String,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      date: DateTime.parse(json['date'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employee_id': employeeId,
      'shift_name': shiftName,
      'start_time': startTime,
      'end_time': endTime,
      'date': date.toIso8601String(),
    };
  }
}
