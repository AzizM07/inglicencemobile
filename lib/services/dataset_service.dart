import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
/// Portage de assets/js/dataset-client.js.
///
/// Le site appelle la Pages Function `/api/dataset?key=...` (Cloudflare KV)
/// avec un cache localStorage de 7 jours. Ici on tape l'URL absolue et on
/// met en cache via shared_preferences.
///
/// Clés utilisées : 'data', 'formules_score_e', 'admis_2026', 'admis_2025'.
class DatasetService {
  /// Base de ton site (la Pages Function y est déployée).
  static const String kApiBase = 'https://ing-licence.tn';
  static const String _endpoint = '/api/dataset';
  static const String _cacheVersion = 'v2';
  static const int _ttlMs = 7 * 24 * 60 * 60 * 1000; // 7 jours

  static String _cacheKey(String key) => 'ds:$_cacheVersion:$key';

  /// Doit être IDENTIQUE à APP_TOKEN dans functions/api/dataset.js.
  static const String kAppToken = 'Kx9mPqL2vT8wZs4nR7fDg1yUeH6bAc3jV5oI0pXk';

  /// En-têtes de la requête. `X-App-Token` est la vraie voie d'accès pour
  /// l'app ; `Referer` reste envoyé pour rester compatible même si tu n'as
  /// pas encore redéployé la function (l'ancienne version ne vérifie que ça).
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
    'Accept': 'application/json',
    'Referer': '$kApiBase/',
    'Origin': kApiBase,
    'X-App-Token': kAppToken,
  };

  /// Renvoie le JSON décodé (Map ou List) pour la clé demandée.
static Future<dynamic> load(String key) async {
  final cached = await _readCache(key);
  if (cached != null) {
    debugPrint('[$key] depuis CACHE — a license_ids: ${jsonEncode(cached).contains("license_ids")}');
    return cached;
  }

  final uri = Uri.parse('$kApiBase$_endpoint?key=${Uri.encodeComponent(key)}');
  final res = await http.get(uri, headers: _headers);
  if (res.statusCode != 200) {
    String msg = 'HTTP ${res.statusCode}';
    try {
      final j = json.decode(res.body);
      if (j is Map && j['error'] != null) msg += ' — ${j['error']}';
    } catch (_) {}
    throw Exception('load($key) a échoué : $msg');
  }

  final payload = json.decode(res.body);
  debugPrint('[$key] depuis RÉSEAU — a license_ids: ${res.body.contains("license_ids")}');
  await _writeCache(key, res.body);
  return payload;
}

  static Future<dynamic> _readCache(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_cacheKey(key));
      if (raw == null) return null;
      final env = json.decode(raw);
      final ts = env['ts'] as int;
      if (DateTime.now().millisecondsSinceEpoch - ts > _ttlMs) return null;
      return env['payload'];
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(String key, String body) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _cacheKey(key),
        json.encode({
          'ts': DateTime.now().millisecondsSinceEpoch,
          'payload': json.decode(body),
        }),
      );
    } catch (_) {}
  }
}
