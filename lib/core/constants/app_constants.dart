import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  // Supabase
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // Face++
  static String get faceppApiKey =>
      dotenv.env['FACEPP_API_KEY'] ?? '';
  static String get faceppApiSecret =>
      dotenv.env['FACEPP_API_SECRET'] ?? '';
  static const String faceppBaseUrl =
      'https://api-us.faceplusplus.com/facepp/v3';

  // App
  static const String appName = 'nano.HR';
  static const String companyName = 'PT Nano Indonesia Sakti';
}
