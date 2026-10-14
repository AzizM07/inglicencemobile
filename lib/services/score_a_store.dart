import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logic/score_a.dart';

/// Instantané persistant du dernier Score A calculé.
class ScoreASnapshot {
  final double total; // le Score A (arrondi à 2 décimales)
  final double? moyenne; // moyenne du bac (affichée sous le score)
  final DateTime calculeLe; // date du calcul

  const ScoreASnapshot({
    required this.total,
    this.moyenne,
    required this.calculeLe,
  });
}

/// Équivalent du localStorage 'concours_scoreA' du site : partagé entre
/// l'écran Score A (écriture) et l'écran Score E / le Home (lecture).
///
/// Persistant (SharedPreferences, même clé et même schéma JSON que le site)
/// ET réactif : [current] est notifié à chaque [save], et rechargé au
/// démarrage par [init] → le Home affiche le Score A instantanément, et le
/// retrouve au prochain lancement.
class ScoreAStore {
  ScoreAStore._();

  static const _key = 'concours_scoreA';

  /// Dernier Score A connu, réactif. Le Home l'écoute via ValueListenableBuilder.
  static final ValueNotifier<ScoreASnapshot?> current =
      ValueNotifier<ScoreASnapshot?>(null);

  /// À appeler UNE fois au démarrage (main), avant runApp : recharge le
  /// Score A enregistré lors d'une session précédente.
  static Future<void> init() async {
    current.value = await _readSnapshot();
  }

  /// Écrit le Score A (schéma identique au site) + la moyenne du bac,
  /// et notifie l'UI aussitôt.
  static Future<void> save(ScoreAResult r, {double? moyBac}) async {
    final now = DateTime.now();
    final total = (r.total * 100).round() / 100;

    // Mise à jour optimiste : le header réagit immédiatement.
    current.value = ScoreASnapshot(
      total: total,
      moyenne: moyBac ?? current.value?.moyenne,
      calculeLe: now,
    );

    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      json.encode({
        'scoreA': total,
        'M': (r.m * 10).round() / 10,
        'R': (r.r * 10).round() / 10,
        'ML': (r.ml * 100).round() / 100,
        'bonus': r.bonus,
        if (moyBac != null) 'moyenne': moyBac,
        'date': now.toIso8601String(),
      }),
    );
  }

  /// Renvoie le Score A enregistré, ou null. (comportement inchangé)
  static Future<double?> readScoreA() async =>
      current.value?.total ?? (await _readSnapshot())?.total;

  /// Renvoie la moyenne du bac enregistrée, ou null.
  static Future<double?> readMoyenne() async =>
      current.value?.moyenne ?? (await _readSnapshot())?.moyenne;

  /// Renvoie l'instantané complet, ou null.
  static Future<ScoreASnapshot?> read() async =>
      current.value ?? await _readSnapshot();

  /// Efface le Score A enregistré (ex. bouton « réinitialiser »).
  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
    current.value = null;
  }

  static Future<ScoreASnapshot?> _readSnapshot() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null) return null;
    try {
      final d = json.decode(raw) as Map<String, dynamic>;
      final v = d['scoreA'];
      if (v is! num) return null;
      final m = d['moyenne'];
      return ScoreASnapshot(
        total: v.toDouble(),
        moyenne: m is num ? m.toDouble() : null,
        calculeLe:
            DateTime.tryParse(d['date']?.toString() ?? '') ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}