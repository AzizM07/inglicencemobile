/// ============================================================
///  MOTEUR SCORE E — portage fidèle de assets/js/score-e.js
///  Opère sur le JSON décodé (Map/List), comme la version web.
/// ============================================================
library;

import 'package:expressions/expressions.dart';

// ---- Crosswalks (identiques au JS) ----
const Map<String, Map<String, String>> kManualCrosswalk = {
  'EFI04': {'GMec': 'GMEC04', 'GInd': 'GIND04', 'GCiv': 'GCIV04'},
  'EFI07': {'GEA': 'ELEA07', 'GC': 'GCIV07', 'GCP': 'GCHP07', 'GCR': 'GTER07', 'GMec': 'GMEC07'},
  'EFI08': {'GEM': 'ELME08', 'GETE': 'GETE08', 'GC': 'GCHI208'},
  'EFI13': {'MECATRO': 'MECA13', 'GSI': 'IFTR13', 'GSIL': 'GSIL13', 'INFO': 'INFO13'},
  'EFI14': {'GT': 'TELC14', 'GEC': 'GSIT14', 'GII': 'ININ14', 'IDSD': 'GDSD14'},
  'EFI22': {'IDLIA22': 'IDL1A22'},
};

const Map<String, Map<String, String>> kEcoleIdCrosswalkByYear = {
  '2026': {'EFI24': 'ISITCOM24', 'EFI25': 'ISSATSO25'},
};

const Map<String, List<String>> kCatKeywordsAr = {
  'math': ['الرياضيات', 'النمذجة والمحاكاة', 'الإحصاء'],
  'info': ['الإعلامية', 'البرمجيات'],
  'info_systemes': ['نظم المعلومات', 'أنظمة المعلومات', 'نظم الإعلامية', 'أنظمة الإعلامية', 'هندسة نظم'],
  'telecom': ['إتصالات', 'المعلومات والإتصالات'],
  'elec_genie': ['الهندسة الكهربائية', 'هندسة كهربائية', 'الكهرباء الصناعية'],
  'elec_electronique_auto': ['الإلكترونيك والكهروتقنية والآلية', 'الإلكترونيك الصناعي'],
  'mecanique': ['الهندسة الميكانيكية', 'هندسة ميكانيكية'],
  'electromecanique': ['الإلكتروميكانيك'],
  'civil': ['الهندسة المدنية', 'البناء', 'الأشغال العمومية'],
  'chimie': ['الكيمياء'],
  'physique': ['الفيزياء'],
  'terre': ['علوم الأرض'],
  'vie_terre': ['علوم الحياة والأرض', 'علوم الأرض والحياة'],
  'geomatique': ['جيوماتيك'],
  'eau_hydraulique': ['المياه', 'الهيدروليكية', 'هندسة المياه'],
  'chimie_industrielle': ['الكيمياء الصناعية'],
  'physique_materiaux': ['فيزياء المواد'],
  'textile': ['هندسة النسيج'],
  'genie_procedes': ['هندسة الأساليب', 'الأساليب الصناعية'],
};

const Map<String, List<String>> kCatKeywordsFr = {
  'math': ['mathematique', 'math'],
  'info': ['informatique'],
  'info_systemes': ['systemes informatiques', "systeme d'information", "systemes d'information", 'ingenierie des systemes'],
  'telecom': ['telecommunication', 'information et de la communication', 'tic'],
  'elec_genie': ['genie electrique', 'machine electrique', 'machines electriques'],
  'elec_electronique_auto': ['electronique', 'electrotechnique', 'automatique', 'asservissement'],
  'mecanique': ['genie mecanique', 'mecanique'],
  'electromecanique': ['electromecanique'],
  'civil': ['genie civil', 'civil'],
  'chimie': ['chimie'],
  'physique': ['physique'],
  'terre': ['sciences de la terre'],
  'vie_terre': ['vie et de la terre', 'vie et la terre'],
  'geomatique': ['geomatique'],
  'eau_hydraulique': ["genie de l'eau", 'hydraulique'],
  'chimie_industrielle': ['chimie industrielle'],
  'physique_materiaux': ['physique des materiaux'],
  'textile': ['genie textile'],
  'genie_procedes': ['genie des procedes'],
};

String normalizeFr(String s) {
  // toLowerCase + suppression des diacritiques latins.
  const map = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
    'û': 'u', 'ü': 'u', 'ú': 'u', 'ù': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(map[ch] ?? ch);
  }
  return b.toString();
}

class _Match {
  final String cat;
  final int start, end;
  _Match(this.cat, this.start, this.end);
}

List<String> categoriesOf(
    String text, Map<String, List<String>> dict, bool applyNormalize) {
  final t = applyNormalize ? normalizeFr(text) : text;
  final matches = <_Match>[];
  dict.forEach((cat, kws) {
    for (final kw in kws) {
      final k = applyNormalize ? normalizeFr(kw) : kw;
      if (k.isEmpty) continue;
      var idx = t.indexOf(k);
      while (idx != -1) {
        matches.add(_Match(cat, idx, idx + k.length));
        idx = t.indexOf(k, idx + 1);
      }
    }
  });
  matches.sort((a, b) => (b.end - b.start) - (a.end - a.start));

  final kept = <_Match>[];
  for (final m in matches) {
    final coveredByLonger = kept.any(
        (k2) => k2.cat != m.cat && m.start >= k2.start && m.end <= k2.end);
    if (!coveredByLonger) kept.add(m);
  }
  final cats = <String>[];
  for (final m in kept) {
    if (!cats.contains(m.cat)) cats.add(m.cat);
  }
  return cats;
}

int scoreMatch(String licenceAr, String licenceFr) {
  final catsAr = categoriesOf(licenceAr, kCatKeywordsAr, false);
  final catsFr = categoriesOf(licenceFr, kCatKeywordsFr, true);
  return catsAr.where((c) => catsFr.contains(c)).length;
}

class GroupeMatch {
  final Map<String, dynamic>? groupe;
  final int score;
  final bool ambigu;
  GroupeMatch(this.groupe, this.score, this.ambigu);
}

GroupeMatch meilleurGroupePourLicence(
    String licenceAr, List<Map<String, dynamic>> groupes) {
  Map<String, dynamic>? best;
  int bestScore = 0;
  bool ambigu = false;
  for (final groupe in groupes) {
    final labels = (groupe['licences_acceptees'] as List?)?.cast<String>() ?? [];
    int localBest = 0;
    for (final labelFr in labels) {
      final s = scoreMatch(licenceAr, labelFr);
      if (s > localBest) localBest = s;
    }
    if (localBest > bestScore) {
      bestScore = localBest;
      best = groupe;
      ambigu = false;
    } else if (localBest == bestScore && localBest > 0 && groupe != best) {
      ambigu = true;
    }
  }
  return GroupeMatch(ambigu ? null : best, bestScore, ambigu);
}

// ---- Codes & licences côté data.json ----
List<String> specCodes(Map<String, dynamic> spec) {
  final codes = <String>[];
  if (spec['codes'] is List) codes.addAll((spec['codes'] as List).cast<String>());
  if (spec['code'] is String) codes.add(spec['code'] as String);
  if (spec['codes_associes'] is List) {
    codes.addAll((spec['codes_associes'] as List).cast<String>());
  }
  return codes;
}

List<Map<String, dynamic>> extractDataSubgroups(Map<String, dynamic> dataEcole) {
  final subs = <Map<String, dynamic>>[];
  final filieres = (dataEcole['filieres'] as List?) ?? [];
  for (final f in filieres.cast<Map<String, dynamic>>()) {
    for (final k in f.keys) {
      if (k.startsWith('code') && f[k] is String) {
        final suffix = k.substring(4);
        final licKey = 'licences_acceptees$suffix';
        subs.add({'code': f[k], 'licences': (f[licKey] as List?) ?? []});
      }
    }
  }
  return subs;
}

List<String>? findLicencesForCode(
    Map<String, dynamic> dataEcole, String code, String ecoleId) {
  var mapped = code;
  final cw = kManualCrosswalk[ecoleId];
  if (cw != null && cw[code] != null) mapped = cw[code]!;
  for (final s in extractDataSubgroups(dataEcole)) {
    if (s['code'] == mapped) return (s['licences'] as List).cast<String>();
  }
  return null;
}

List<String> licencesForEcole(Map<String, dynamic> ec) {
  final all = <String>[];
  final seen = <String>{};
  for (final f in ((ec['filieres'] as List?) ?? []).cast<Map<String, dynamic>>()) {
    for (final k in f.keys) {
      if (k.startsWith('licences_acceptees') && f[k] is List) {
        for (final l in (f[k] as List)) {
          final t = l.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
          if (t.isNotEmpty && seen.add(t)) all.add(t);
        }
      }
    }
  }
  return all;
}

// ---- Helpers math (variadiques via paramètres optionnels) ----
List<num> _nums(List args) =>
    args.whereType<num>().where((x) => !x.isNaN).toList();

num _moy(
    [a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]) {
  final v = _nums([a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]);
  if (v.isEmpty) return 0;
  return v.reduce((x, y) => x + y) / v.length;
}

num _max(
    [a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]) {
  final v = _nums([a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]);
  if (v.isEmpty) return 0;
  return v.reduce((x, y) => x > y ? x : y);
}

num _top2moy(
    [a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]) {
  final v = _nums([a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]);
  if (v.isEmpty) return 0;
  v.sort((x, y) => y.compareTo(x));
  final top = v.take(2).toList();
  return top.reduce((x, y) => x + y) / top.length;
}

num _coalesce0(
    [a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]) {
  for (final val in [a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p]) {
    if (val is num && !val.isNaN) return val;
  }
  return 0;
}

bool _baremeCond(String cond, num mv) {
  var m = RegExp(r'^M\s*>=\s*(-?\d+(\.\d+)?)$').firstMatch(cond);
  if (m != null) return mv >= double.parse(m.group(1)!);
  m = RegExp(r'^M\s*<\s*(-?\d+(\.\d+)?)$').firstMatch(cond);
  if (m != null) return mv < double.parse(m.group(1)!);
  m = RegExp(r'^(-?\d+(\.\d+)?)\s*<=\s*M\s*<\s*(-?\d+(\.\d+)?)$').firstMatch(cond);
  if (m != null) {
    return mv >= double.parse(m.group(1)!) && mv < double.parse(m.group(3)!);
  }
  return false;
}

num Function(num) _makeBareme(List? paliers) {
  return (num m) {
    for (final p in (paliers ?? []).cast<Map<String, dynamic>>()) {
      if (_baremeCond(p['condition'] as String, m)) {
        return (p['points'] as num);
      }
    }
    return 0;
  };
}

/// Évalue formule.expression avec les notes saisies (équiv. new Function côté JS).
num computeScore(
    Map<String, dynamic> formule, Map<String, num> values, List? paliers) {
  final vars = (formule['variables'] as List).cast<Map<String, dynamic>>();
  final context = <String, dynamic>{};
  for (final v in vars) {
    context[v['id'] as String] = values[v['id']];
  }
  context['max'] = _max;
  context['moy'] = _moy;
  context['top2moy'] = _top2moy;
  context['coalesce0'] = _coalesce0;
  context['bareme'] = _makeBareme(paliers);

  final expr = Expression.parse(formule['expression'] as String);
  const evaluator = ExpressionEvaluator();
  final result = evaluator.eval(expr, context);
  return (result as num);
}

// ---- Seuils admis (2025 / 2026) ----
String mapEcoleIdForYear(String ecoleId, String year) {
  final m = kEcoleIdCrosswalkByYear[year];
  return (m != null && m[ecoleId] != null) ? m[ecoleId]! : ecoleId;
}

class Seuils {
  final num? premier, dernier;
  final int? nb;
  Seuils({this.premier, this.dernier, this.nb});
}

Seuils? seuilsForYear(
    dynamic admis, String ecoleId, List<String> dataCodes, String year) {
  if (admis == null) return null;
  final ecoles = (admis is Map ? admis['ecoles'] : admis);
  if (ecoles is! List) return null;

  final mappedId = mapEcoleIdForYear(ecoleId, year);
  final ec = ecoles.cast<Map<String, dynamic>>().where((e) => e['id'] == mappedId);
  if (ec.isEmpty) return null;
  final fils = (ec.first['filieres'] ?? ec.first['specialites'] ?? []) as List;

  for (final f in fils.cast<Map<String, dynamic>>()) {
    final fcode = f['code'] ?? f['code_annee1'] ?? f['code_annee2'];
    if (!dataCodes.contains(fcode)) continue;

    if (f['dernier_admis'] is num || f['premier_admis'] is num) {
      return Seuils(
        premier: f['premier_admis'] as num?,
        dernier: f['dernier_admis'] as num?,
        nb: f['nb_admis'] as int?,
      );
    }
    final arrRaw = (f['students'] ?? f['admis']);
    if (arrRaw is List) {
      final arr = arrRaw
          .map((s) => s is num
              ? s
              : (s is Map && s['score'] != null
                  ? num.tryParse(s['score'].toString())
                  : null))
          .whereType<num>()
          .toList();
      if (arr.isNotEmpty) {
        return Seuils(
          premier: arr.reduce((a, b) => a > b ? a : b),
          dernier: arr.reduce((a, b) => a < b ? a : b),
          nb: arr.length,
        );
      }
    }
  }
  return null;
}