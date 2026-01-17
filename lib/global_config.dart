
class GlobalConfig {
  static const String baseUrl = 'https://jds25q4d-8003.euw.devtunnels.ms';
  static const String appName = 'BKM Service';
  static const String version = '1.0.0';

  static const String defaultAdminEmail = 'admin@admin.com';
  static const String defaultAdminPassword = 'admin123';
  
  // URL сервера (можно изменить в настройках)
  static String serverUrl = baseUrl ;
  
  // Метод для обновления URL сервера
  static void updateServerUrl(String newUrl) {
    serverUrl = newUrl;
  }
}
