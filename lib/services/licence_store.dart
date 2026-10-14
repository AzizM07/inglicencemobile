// licence_store.dart — licence choisie, réactive ET persistée.
//
// Même principe que ScoreAStore : un ValueNotifier écouté par l'UI
// (le header Home) + une sauvegarde dans SharedPreferences pour que la
// licence survive au redémarrage de l'app.
//
// PREREQUIS main.dart (une seule fois, à côté de ScoreAStore.init()) :
//   await LicenceStore.init();

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Instantané de la licence sélectionnée (ce qu'on affiche / persiste).
class LicenceSnapshot {
  const LicenceSnapshot({this.licenseId, this.ar, this.fr});

  final String? licenseId;
  final String? ar;
  final String? fr;

  /// Libellé à afficher : l'arabe en priorité (les licences sont en RTL),
  /// sinon le français.
  String get label {
    if (ar != null && ar!.trim().isNotEmpty) return ar!.trim();
    if (fr != null && fr!.trim().isNotEmpty) return fr!.trim();
    return '';
  }

  Map<String, dynamic> toJson() =>
      {'license_id': licenseId, 'ar': ar, 'fr': fr};

  factory LicenceSnapshot.fromJson(Map<String, dynamic> j) => LicenceSnapshot(
        licenseId: j['license_id']?.toString(),
        ar: j['ar']?.toString(),
        fr: j['fr']?.toString(),
      );

  /// Reconstruit une Map exploitable par l'écran Score E (filtrage +
  /// affichage du champ licence).
  Map<String, dynamic> toMap() =>
      {'license_id': licenseId, 'ar': ar, 'fr': fr};
}

class LicenceStore {
  LicenceStore._();

  static const String _key = 'licence_current_v1';

  /// Source de vérité réactive : le header Home l'écoute.
  static final ValueNotifier<LicenceSnapshot?> current =
      ValueNotifier<LicenceSnapshot?>(null);

  static SharedPreferences? _prefs;

  /// À appeler au démarrage (main.dart) pour recharger la dernière licence.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        current.value =
            LicenceSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // JSON corrompu : on ignore, on repart sans licence.
      }
    }
  }

  /// Enregistre la licence choisie (appelé depuis l'écran Score E).
  /// [licence] est la Map issue du picker (clés license_id / ar / fr).
  static Future<void> save(Map<String, dynamic> licence) async {
    final snap = LicenceSnapshot(
      licenseId: licence['license_id']?.toString(),
      ar: licence['ar']?.toString(),
      fr: licence['fr']?.toString(),
    );
    current.value = snap; // notifie l'UI immédiatement
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_key, jsonEncode(snap.toJson()));
  }

  /// Efface la licence (quand l'utilisateur la retire sur Score E).
  static Future<void> clear() async {
    current.value = null;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_key);
  }
}