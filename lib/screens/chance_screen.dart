// chance_screen.dart — « Voir ma chance » : simulateur Score E global.
//
// L'utilisateur choisit sa licence, saisit UNE fois l'union des notes
// demandées par toutes les formules éligibles, et l'app calcule pour chaque
// école/spécialité :
//   Score E   = engine.computeScore(formule, notes, paliers)
//   Score gén = 0,7·ScoreA + 0,3·ScoreE
//   verdict   = comparaison au dernier admis (engine.seuilsForYear), marge ±2
// exactement comme ecole_detail_screen.dart, mais sur TOUTES les écoles.
//
// Réutilise le moteur (score_e_engine.dart) et les datasets (DatasetService).
// Le Score A vient de ScoreAStore (réactif) : requis pour le verdict.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_header.dart';
import '../services/dataset_service.dart';
import '../services/score_a_store.dart';
import '../logic/score_e_engine.dart' as engine;
import 'ecole_detail_screen.dart';
import 'score_a_screen.dart' show ScoreAScreen;

class ChanceScreen extends StatefulWidget {
  const ChanceScreen({super.key});
  @override
  State<ChanceScreen> createState() => _ChanceScreenState();
}

class _ChanceData {
  _ChanceData({
    required this.ecolesData,
    required this.formulesById,
    required this.licences,
    required this.admis2026,
    required this.admis2025,
  });
  final List<Map<String, dynamic>> ecolesData;
  final Map<String, Map<String, dynamic>> formulesById;
  final List<Map<String, dynamic>> licences;
  final dynamic admis2026, admis2025;
}

/// Une cible de calcul = une (école, spécialité) éligible pour la licence.
class _Target {
  _Target({
    required this.ecoleId,
    required this.ecoleNom,
    required this.specNom,
    required this.formule,
    required this.paliers,
    required this.dataCodes,
    required this.ambiguous,
    required this.noFormule,
  });
  final String ecoleId, ecoleNom;
  final String? specNom;
  final Map<String, dynamic>? formule;
  final List? paliers;
  final List<String> dataCodes;
  final bool ambiguous; // plusieurs formules, la licence ne tranche pas
  final bool noFormule; // pas de formule trouvée pour cette filière
}

/// Résultat calculé (indépendant du Score A ; le verdict est calculé au rendu).
class _Result {
  _Result({
    required this.t,
    this.scoreE,
    this.missing = const [],
    this.error,
    this.s2026,
    this.s2025,
  });
  final _Target t;
  final num? scoreE;
  final List<String> missing;
  final String? error;
  final engine.Seuils? s2026, s2025;

  bool get incomplete => missing.isNotEmpty;

  engine.Seuils? get ref {
    if (s2026 != null && (s2026!.dernier != null || s2026!.premier != null)) return s2026;
    if (s2025 != null && (s2025!.dernier != null || s2025!.premier != null)) return s2025;
    return null;
  }

  String? get refYear {
    if (s2026 != null && (s2026!.dernier != null || s2026!.premier != null)) return '2026';
    if (s2025 != null && (s2025!.dernier != null || s2025!.premier != null)) return '2025';
    return null;
  }
}

class _ChanceScreenState extends State<ChanceScreen> {
  late Future<_ChanceData> _future;
  _ChanceData? _data;

  Map<String, dynamic>? _licence;
  List<_Target> _targets = [];
  Map<String, String> _vars = {}; // id -> label (union)
  final Map<String, TextEditingController> _noteCtrls = {};
  List<_Result>? _results;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    for (final c in _noteCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<_ChanceData> _load() async {
    final results = await Future.wait([
      DatasetService.load('data'),
      DatasetService.load('formules_score_e'),
      DatasetService.load('licences'),
      DatasetService.load('admis_2026').catchError((_) => null),
      DatasetService.load('admis_2025').catchError((_) => null),
    ]);

    final ecolesData =
        ((results[0]?['ecoles']) as List?)?.cast<Map<String, dynamic>>() ?? [];

    final formulesById = <String, Map<String, dynamic>>{};
    for (final fe in ((results[1]?['ecoles']) as List?)?.cast<Map<String, dynamic>>() ?? []) {
      formulesById[fe['id'].toString()] = fe;
    }

    final licences = (((results[2]?['licences']) as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .where((l) => (l['license_id'] ?? '') != 'ANY')
        .toList()
      ..sort((a, b) => (a['ar'] ?? '').toString().compareTo((b['ar'] ?? '').toString()));

    final d = _ChanceData(
      ecolesData: ecolesData,
      formulesById: formulesById,
      licences: licences,
      admis2026: results[3],
      admis2025: results[4],
    );
    _data = d;
    return d;
  }

  // ── Construction des cibles pour la licence choisie ──────────────────────

  void _onPickLicence(Map<String, dynamic> lic) {
    _licence = lic;
    _buildTargets();
    setState(() => _results = null);
  }

  void _buildTargets() {
    final d = _data;
    final lic = _licence;
    if (d == null || lic == null) {
      _targets = [];
      _vars = {};
      return;
    }
    final lid = (lic['license_id'] ?? '').toString();
    final licAr = (lic['ar'] ?? '').toString();

    final seen = <String>{};
    final targets = <_Target>[];

    for (final de in d.ecolesData) {
      final id = de['id'].toString();
      final nom = (de['nom'] ?? de['sigle'] ?? '').toString();
      final fe = d.formulesById[id];
      final filieres = ((de['filieres']) as List?)?.cast<Map<String, dynamic>>() ?? [];

      for (final f in filieres) {
        if (!_filiereAccepts(f, lid)) continue;

        // Spécialités (formules) correspondant aux codes de cette filière.
        // Une filière a souvent code_annee1 + code_annee2 : on ne garde que
        // les codes qui trouvent réellement une spécialité.
        final specs = <Map<String, dynamic>>[];
        if (fe != null) {
          for (final code in _filiereCodes(f)) {
            final spec = _specForCode(fe, id, code);
            if (spec == null || specs.contains(spec)) continue;
            // Chez les filières « à options » (EFI25/24…), plusieurs
            // spécialités partagent le même license_ids de data mais visent
            // chacune une licence précise. On ne garde que celles dont un
            // groupe accepte réellement la licence choisie.
            if (!_specAcceptsLid(spec, lid)) continue;
            specs.add(spec);
          }
        }

        if (specs.isEmpty) {
          // École accepte la licence mais aucune formule pour cette filière.
          final label = (f['nom'] ?? f['nom_annee1'] ?? f['nom_annee1_a'] ?? '').toString();
          final codesTxt = _filiereCodes(f).join(',');
          final key = '$id::noform::${label.isEmpty ? codesTxt : label}';
          if (seen.add(key)) {
            targets.add(_Target(
              ecoleId: id,
              ecoleNom: nom,
              specNom: label.isEmpty ? null : label,
              formule: null,
              paliers: null,
              dataCodes: _filiereCodes(f),
              ambiguous: false,
              noFormule: true,
            ));
          }
          continue;
        }

        for (final spec in specs) {
          final specNom = (spec['nom'] ?? '').toString();
          final key = '$id::$specNom';
          if (!seen.add(key)) continue;

          final codes = engine.specCodes(spec);
          final cw = engine.kManualCrosswalk[id] ?? const {};
          final dataCodes = codes.map((c) => (cw[c] ?? c)).toList();
          final picked = _pickFormule(spec, lid, licAr);
          final formule = picked.$1;
          final ambiguous = picked.$2;

          targets.add(_Target(
            ecoleId: id,
            ecoleNom: nom,
            specNom: specNom,
            formule: formule,
            paliers: (spec['bareme']?['paliers']) as List?,
            dataCodes: dataCodes,
            ambiguous: ambiguous,
            noFormule: formule == null && !ambiguous,
          ));
        }
      }
    }

    // Union des variables de toutes les formules déterminées.
    final vars = <String, String>{};
    for (final t in targets) {
      final fo = t.formule;
      if (fo == null) continue;
      for (final v in ((fo['variables']) as List?)?.cast<Map<String, dynamic>>() ?? []) {
        final idv = v['id'].toString();
        vars.putIfAbsent(idv, () => (v['label'] ?? idv).toString());
      }
    }

    _targets = targets;
    _vars = vars;
  }

  Set<String> _licenseIdsOfFiliere(Map f) {
    final out = <String>{};
    f.forEach((k, v) {
      if (k.toString().startsWith('license_ids') && v is List) {
        out.addAll(v.map((e) => e.toString()));
      }
    });
    return out;
  }

  bool _filiereAccepts(Map f, String lid) {
    final ids = _licenseIdsOfFiliere(f);
    return ids.contains(lid) || ids.contains('ANY');
  }

  List<String> _filiereCodes(Map f) {
    final out = <String>[];
    f.forEach((k, v) {
      if (k.toString().startsWith('code') && v is String) out.add(v);
    });
    return out;
  }

  Map<String, dynamic>? _specForCode(Map fe, String ecoleId, String code) {
    final specs = ((fe['specialites']) as List?)?.cast<Map<String, dynamic>>() ?? [];
    final cw = engine.kManualCrosswalk[ecoleId] ?? const {};
    for (final spec in specs) {
      final codes = engine.specCodes(spec);
      final dataCodes = codes.map((c) => (cw[c] ?? c)).toList();
      if (dataCodes.contains(code)) return spec;
    }
    return null;
  }

  /// Une spécialité concerne-t-elle cette licence ? On se base sur les
  /// license_ids des groupes de la formule. Sans aucun license_ids (ancien
  /// format), on laisse passer (l'éligibilité data + le match flou décident).
  bool _specAcceptsLid(Map spec, String lid) {
    final groupes = ((spec['groupes_licences']) as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (groupes.isEmpty) return false;
    bool anyHasIds = false;
    for (final g in groupes) {
      final ids = (g['license_ids'] as List?)?.map((e) => e.toString()).toList();
      if (ids != null && ids.isNotEmpty) {
        anyHasIds = true;
        if (ids.contains(lid) || ids.contains('ANY')) return true;
      }
    }
    return !anyHasIds;
  }

  /// (formule, ambigu). Priorité au license_ids du groupe (précis) ; repli sur
  /// le groupe « ANY » ; en dernier, la correspondance floue AR/FR du moteur.
  (Map<String, dynamic>?, bool) _pickFormule(Map spec, String lid, String licenceAr) {
    final groupes = ((spec['groupes_licences']) as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (groupes.isEmpty) return (null, false);
    if (groupes.length == 1) return (groupes[0]['formule'] as Map<String, dynamic>?, false);

    List<String> idsOf(Map g) =>
        (g['license_ids'] as List?)?.map((e) => e.toString()).toList() ?? const [];

    // 1) Match direct par license_id.
    final exact = groupes.where((g) => idsOf(g).contains(lid)).toList();
    if (exact.length == 1) return (exact[0]['formule'] as Map<String, dynamic>?, false);
    if (exact.length > 1) return (null, true); // plusieurs formules pour cette licence

    // 2) Groupe générique « ANY ».
    final any = groupes.where((g) => idsOf(g).contains('ANY')).toList();
    if (any.length == 1) return (any[0]['formule'] as Map<String, dynamic>?, false);
    if (any.length > 1) return (null, true);

    // 3) Repli : correspondance floue AR/FR (comme l'écran détail).
    final gm = engine.meilleurGroupePourLicence(licenceAr, groupes);
    if (gm.ambigu) return (null, true);
    if (gm.groupe != null && gm.score > 0) {
      return (gm.groupe!['formule'] as Map<String, dynamic>?, false);
    }
    return (null, true);
  }

  // ── Calcul ───────────────────────────────────────────────────────────────

  void _calculer() {
    final d = _data;
    if (d == null) return;
    final res = <_Result>[];

    for (final t in _targets) {
      if (t.noFormule || t.ambiguous || t.formule == null) {
        res.add(_Result(t: t));
        continue;
      }
      final fo = t.formule!;
      final vlist = ((fo['variables']) as List?)?.cast<Map<String, dynamic>>() ?? [];
      final values = <String, num>{};
      final missing = <String>[];
      for (final v in vlist) {
        final idv = v['id'].toString();
        final raw = _noteCtrls[idv]?.text.trim() ?? '';
        if (raw.isEmpty) {
          missing.add((v['label'] ?? idv).toString());
        } else {
          values[idv] = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
        }
      }
      if (missing.isNotEmpty) {
        res.add(_Result(t: t, missing: missing));
        continue;
      }
      num? scoreE;
      String? err;
      try {
        final s = engine.computeScore(fo, values, t.paliers);
        scoreE = (s * 100).round() / 100;
      } catch (e) {
        err = '$e';
      }
      res.add(_Result(
        t: t,
        scoreE: scoreE,
        error: err,
        s2026: engine.seuilsForYear(d.admis2026, t.ecoleId, t.dataCodes, '2026'),
        s2025: engine.seuilsForYear(d.admis2025, t.ecoleId, t.dataCodes, '2025'),
      ));
    }

    setState(() => _results = res);
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Column(
          children: [
            AppHeader(
              onBack: () => Navigator.of(context).maybePop(),
              eyebrow: 'Simulateur · Score E',
              title: 'Voir ma chance',
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: FutureBuilder<_ChanceData>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('${snap.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.gray)),
                        ),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        _licenceField(snap.data!.licences),
                        const SizedBox(height: 14),
                        if (_licence != null) ..._notesSection(),
                        if (_results != null) ..._resultsSection(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _licenceField(List<Map<String, dynamic>> licences) {
    final label = _licence == null
        ? 'اختر إجازتك…'
        : (_licence!['ar'] ?? _licence!['fr'] ?? '').toString();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final choice = await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (_) => _LicencePickerSheet(licences: licences),
          );
          if (choice != null) _onPickLicence(choice);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _licence == null
                    ? const Color(0xFFDFE4F6)
                    : AppColors.blue.withOpacity(.55)),
          ),
          child: Row(
            children: [
              Icon(Icons.school_outlined, size: 19, color: AppColors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: _licence == null ? AppColors.graySoft : AppColors.ink,
                    fontWeight: _licence == null ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.gray),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _notesSection() {
    if (_targets.isEmpty) {
      return [
        _notice(Icons.search_off, 'Aucune école',
            'Aucune école n\'accepte cette licence dans le dataset actuel.'),
      ];
    }
    if (_vars.isEmpty) {
      return [
        _notice(Icons.sync_problem, 'Formules indisponibles',
            'Les formules ne sont pas encore chargées pour ces écoles. Réessaie plus tard.'),
      ];
    }
    return [
      Text('Vos notes (/20)',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
      const SizedBox(height: 4),
      Text('Renseignez ce que vous connaissez — chaque école utilise les notes de sa formule.',
          style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.gray)),
      const SizedBox(height: 12),
      for (final e in _vars.entries) _noteRow(e.key, e.value),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: _calculer,
          child: const Text('Calculer mes chances'),
        ),
      ),
    ];
  }

  Widget _noteRow(String id, String label) {
    final ctrl = _noteCtrls.putIfAbsent(id, () => TextEditingController());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.ink)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: const InputDecoration(hintText: '/20'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _resultsSection() {
    return [
      const SizedBox(height: 20),
      // Réactif au Score A : dès qu'il est calculé, les verdicts apparaissent.
      ValueListenableBuilder<ScoreASnapshot?>(
        valueListenable: ScoreAStore.current,
        builder: (context, snapA, _) {
          final a = snapA?.total;
          final results = List<_Result>.from(_results!)
            ..sort((r1, r2) => _rank(r1, a).compareTo(_rank(r2, a)));

          final admissibles = a == null
              ? 0
              : results.where((r) => r.scoreE != null && r.ref?.dernier != null
                  && (0.7 * a + 0.3 * r.scoreE!) - r.ref!.dernier! >= 2).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (a == null) _scoreAPrompt() else _scoreABanner(a),
              const SizedBox(height: 12),
              _divider(a == null
                  ? '${results.where((r) => r.scoreE != null).length} SCORES E CALCULÉS'
                  : '$admissibles ADMISSIBLES · ${results.length} FILIÈRES'),
              const SizedBox(height: 8),
              for (final r in results) _resultCard(r, a),
            ],
          );
        },
      ),
    ];
  }

  int _rank(_Result r, double? a) {
    if (r.t.noFormule || r.t.ambiguous) return 6;
    if (r.error != null) return 7;
    if (r.incomplete) return 5;
    if (r.scoreE == null) return 7;
    if (a == null) return 4;
    final ref = r.ref;
    if (ref?.dernier == null) return 3;
    final sg = 0.7 * a + 0.3 * r.scoreE!;
    final d = sg - ref!.dernier!;
    if (d >= 2) return 0;
    if (d >= -2) return 1;
    return 2;
  }

  Widget _resultCard(_Result r, double? a) {
    final title = '${r.t.ecoleId} · ${r.t.specNom ?? 'Filière'}';

    // Cas particuliers : ambiguë / sans formule → renvoi au détail.
    if (r.t.noFormule || r.t.ambiguous) {
      return _softRow(
        onTap: () => _openDetail(r.t.ecoleId),
        child: Row(
          children: [
            const Icon(Icons.help_outline, size: 18, color: AppColors.graySoft),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${r.t.ecoleId} — ${r.t.ambiguous ? 'formules à départager' : 'formule indisponible'}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
              ),
            ),
            const Text('Ouvrir',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.blue)),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.blue),
          ],
        ),
      );
    }

    if (r.error != null) {
      return _softRow(
        child: Text('$title — erreur de calcul',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFC0392B))),
      );
    }

    if (r.incomplete) {
      return _softRow(
        onTap: () => _openDetail(r.t.ecoleId),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text('Renseignez : ${r.missing.join(', ')}',
                style: const TextStyle(fontSize: 12, color: AppColors.gray)),
          ],
        ),
      );
    }

    if (r.scoreE == null) {
      return _softRow(
        onTap: () => _openDetail(r.t.ecoleId),
        child: Text('$title — formule indisponible',
            style: const TextStyle(fontSize: 12.5, color: AppColors.gray)),
      );
    }
    final scoreE = r.scoreE!;
    final num? sg =
        (a != null) ? ((0.7 * a + 0.3 * scoreE) * 100).round() / 100 : null;

    return _softRow(
      onTap: () => _openDetail(r.t.ecoleId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
          const SizedBox(height: 8),
          Row(
            children: [
              _metric('Score E', _fmt(scoreE)),
              if (sg != null) ...[
                const SizedBox(width: 14),
                _metric('Général', _fmt(sg)),
              ],
            ],
          ),
          // Comparaison par année : 2026 ET 2025, chacune avec son verdict.
          _yearLine('2026', r.s2026, sg),
          _yearLine('2025', r.s2025, sg),
          if (a == null) ...[
            const SizedBox(height: 6),
            const Text('Calcule ton Score A pour le verdict par année.',
                style: TextStyle(fontSize: 11, color: AppColors.graySoft)),
          ],
        ],
      ),
    );
  }

  /// Une ligne = une année : seuils (dernier/premier) + verdict de cette année.
  /// Rendue vide si l'année n'a pas de données pour cette filière.
  Widget _yearLine(String year, engine.Seuils? s, num? sg) {
    if (s == null || (s.dernier == null && s.premier == null)) {
      return const SizedBox.shrink();
    }
    Widget? tag;
    if (sg != null && s.dernier != null) {
      final d = sg - s.dernier!;
      late Color bg, fg;
      late String note;
      if (d >= 2) {
        bg = const Color(0xFFE3F8EE);
        fg = const Color(0xFF0F9D63);
        note = 'Admissible';
      } else if (d >= -2) {
        bg = const Color(0xFFFDF3DC);
        fg = const Color(0xFFA9750A);
        note = 'Limite';
      } else {
        bg = const Color(0xFFFBE7E3);
        fg = const Color(0xFFC0392B);
        note = 'Difficile';
      }
      tag = _pill(note, fg, bg);
    }
    final parts = <String>[year];
    if (s.dernier != null) parts.add('dernier ${_fmt(s.dernier!)}');
    if (s.premier != null) parts.add('premier ${_fmt(s.premier!)}');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(parts.join(' · '),
                style: const TextStyle(fontSize: 11, color: AppColors.graySoft)),
          ),
          if (tag != null) tag,
        ],
      ),
    );
  }

  void _openDetail(String ecoleId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EcoleDetailScreen(ecoleId: ecoleId)),
    );
  }

  // ── petits widgets ───────────────────────────────────────────────────────

  Widget _metric(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12, color: AppColors.gray),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink)),
        ],
      ),
    );
  }

  Widget _pill(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _softRow({required Widget child, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3E7F5)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _divider(String label) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE3E7F5))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.graySoft)),
        ),
        const Expanded(child: Divider(color: Color(0xFFE3E7F5))),
      ],
    );
  }

  Widget _scoreABanner(double a) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7DDF7)),
      ),
      child: Text('Score A enregistré : ${a.toStringAsFixed(2)} pts — utilisé pour le Score général.',
          style: const TextStyle(fontSize: 12.5, color: AppColors.ink)),
    );
  }

  Widget _scoreAPrompt() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAEEDA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0DCB4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Il vous faut un Score A pour connaître vos chances d\'admission (Score général = 0,7·A + 0,3·E).',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF5A4A2A)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ScoreAScreen()),
              ),
              child: const Text('Calculer mon Score A'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.graySoft),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.gray)),
        ],
      ),
    );
  }

  String _fmt(num v) => v.toStringAsFixed(2).replaceAll('.', ',');
  String _fmtNum(num? v) => v == null ? '—' : v.toString().replaceAll('.', ',');
}

// ── Feuille modale de sélection de licence (recherche RTL) ─────────────────
class _LicencePickerSheet extends StatefulWidget {
  const _LicencePickerSheet({required this.licences});
  final List<Map<String, dynamic>> licences;
  @override
  State<_LicencePickerSheet> createState() => _LicencePickerSheetState();
}

class _LicencePickerSheetState extends State<_LicencePickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase().trim();
    final items = widget.licences.where((l) {
      if (q.isEmpty) return true;
      final hay =
          '${l['ar'] ?? ''} ${l['fr'] ?? ''} ${(l['aliases'] as List?)?.join(' ') ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE2E4EE), borderRadius: BorderRadius.circular(4)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'ابحث عن إجازتك…',
                  hintTextDirection: TextDirection.rtl,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF4F5FB),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text('Aucune licence', style: TextStyle(color: AppColors.gray)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFF0F1F6)),
                      itemBuilder: (_, i) {
                        final l = items[i];
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(l),
                          title: Text((l['ar'] ?? '').toString(),
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink)),
                          subtitle: (l['fr'] ?? '').toString().isEmpty
                              ? null
                              : Text((l['fr']).toString(),
                                  style: const TextStyle(fontSize: 12, color: AppColors.gray)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}