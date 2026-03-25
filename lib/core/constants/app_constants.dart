class AppConstants {
  // Supabase
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yftwtsyyqrvlzzebgwov.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlmdHd0c3l5cXJ2bHp6ZWJnd292Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3NTY5OTYsImV4cCI6MjA4OTMzMjk5Nn0.qeQrPl7h7cF-2VUCnqsgpsQXCP9JzQ8XOgog8c_nSoM',
  );

  // Face++
  static const String faceppApiKey = String.fromEnvironment(
    'FACEPP_API_KEY',
    defaultValue: '3ivKCxwc1GW1Tl4s91JCZFLO2QjlfHuk',
  );
  static const String faceppApiSecret = String.fromEnvironment(
    'FACEPP_API_SECRET',
    defaultValue: 'PYI5PFyfW4mhKeBURtt2IPbXtqe82dSj',
  );
  static const String faceppBaseUrl = 'https://api-us.faceplusplus.com/facepp/v3';

  // App
  static const String appName = 'nano.HR';
  static const String companyName = 'PT Nano Indonesia Sakti';
}
