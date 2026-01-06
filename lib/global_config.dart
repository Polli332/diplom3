class GlobalConfig {
  static const String baseUrl = 'https://jvvrlmfl-3000.euw.devtunnels.ms';
  static const String appName = 'BKM Service';
  static const String version = '1.0.0';

  static const String defaultAdminEmail = 'admin@admin.com';
  static const String defaultAdminPassword = 'admin123';
  
  // URL сервера (можно изменить в настройках)
  static String serverUrl = 'https://jvvrlmfl-3000.euw.devtunnels.ms';
  
  // Метод для обновления URL сервера
  static void updateServerUrl(String newUrl) {
    serverUrl = newUrl;
  }
}
