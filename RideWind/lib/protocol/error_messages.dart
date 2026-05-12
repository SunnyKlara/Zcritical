/// 设备错误消息映射工具
///
/// 将 ESP32 返回的错误代码映射为用户友好的中文提示。
class DeviceErrorMessages {
  DeviceErrorMessages._();

  static const Map<String, String> logoErrors = {
    'LOGO_ERROR:MEM': '设备内存不足',
    'LOGO_ERROR:INVALID_SLOT': 'Logo 槽位无效',
    'LOGO_ERROR:SIZE_MISMATCH': '图片大小不匹配',
    'LOGO_FAIL:CRC': '数据校验失败，请重试',
    'LOGO_FAIL:WRITE': '写入失败，请重试',
  };

  static const Map<String, String> otaErrors = {
    'OTA_FAIL:CRC': '校验失败，设备已回滚到上一版本',
    'OTA_FAIL:SIZE': '固件大小不匹配，设备已回滚到上一版本',
    'OTA_FAIL:WRITE': '写入失败，设备已回滚到上一版本',
    'OTA_FAIL:VERIFY': '验证失败，设备已回滚到上一版本',
    'OTA_FAIL:TIMEOUT': '传输超时，设备已回滚到上一版本',
  };

  static const Map<String, String> wifiErrors = {
    'WIFI_ERR:CONNECT_FAILED': 'WiFi 连接失败，请检查密码',
    'WIFI_ERR:TIMEOUT': 'WiFi 连接超时，请检查网络',
    'WIFI_ERR:NO_AP': '未找到指定的 WiFi 网络',
    'WIFI_ERR:AUTH_FAIL': 'WiFi 认证失败，请检查密码',
  };

  static const String bleTimeoutMessage = '设备响应超时，请检查连接';

  static String getLogoErrorMessage(String errorResponse) =>
      logoErrors[errorResponse] ?? 'Logo 操作失败: $errorResponse';

  static String getOtaErrorMessage(String errorResponse) =>
      otaErrors[errorResponse] ?? '升级失败，设备已回滚到上一版本 ($errorResponse)';

  static String getWifiErrorMessage(String errorResponse) =>
      wifiErrors[errorResponse] ?? 'WiFi 连接失败，请检查密码';

  static String getBleTimeoutMessage() => bleTimeoutMessage;
}
