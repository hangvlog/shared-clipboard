/// 设备信息模型
class DeviceInfo {
  /// 设备唯一标识
  final String deviceId;

  /// 设备类型：desktop / mobile / web
  final String deviceType;

  /// 设备名称
  final String deviceName;

  /// 操作系统平台
  final String platform;

  DeviceInfo({
    required this.deviceId,
    required this.deviceType,
    required this.deviceName,
    required this.platform,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceType': deviceType,
      'deviceName': deviceName,
      'platform': platform,
    };
  }

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['deviceId'] as String,
      deviceType: json['deviceType'] as String,
      deviceName: json['deviceName'] as String,
      platform: json['platform'] as String,
    );
  }
}
