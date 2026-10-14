import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../services/dataset_service.dart';
import '../services/score_a_store.dart';
import '../logic/score_e_engine.dart' as engine;
import '../services/ad_service.dart';
import 'score_a_screen.dart';

/// Détails d'une école : port de afficher() + renderEcole() + onCalculer().
///
/// DESIGN « B · accordéon » — épuré, peu de couleur :
///  • fond gris très clair, cartes blanches, texte foncé ;
///  • la page liste les spécialités (code + nom) ; une seule s'ouvre à la fois ;
///  • une spécialité ouverte montre : le choix éventuel, les notes /20
///    (limitées de 0 à 20), le bouton corail, puis UN verdict ;
///  • tout le reste (formule, licences, seuils, autres formules) est replié
///    sous « Détails ».
/// Couleurs : bleu = admissible probable / focus ; corail = bouton, limite,
/// difficile. Logique inchangée : score_e_engine, crosswalk, seuils,
/// interstitiel après un calcul réussi.

const Color _kPageBg = Color(0xFFF4F5F9);
const Color _kFieldBg = Color(0xFFF4F5F9);
const Color _kMuted = Color(0xFF8A90A8);
const Color _kSoftText = Color(0xFF4A5070);
const Color _kHint = Color(0xFFB4BAD0);
const Color _kLine = Color(0xFFECEEF4);
const Color _kBlueSoft = Color(0xFFE8EDFF);
const Color _kCoral = Color(0xFFFF6B5B);
const Color _kCoralSoft = Color(0xFFFFECE9);
const Color _kCoralText = Color(0xFFD2493A);

/// Nombre au format français : 54.98 -> « 54,98 ».
String _fr(num v) => v.toStringAsFixed(2).replaceAll('.', ',');

class EcoleDetailScreen extends StatefulWidget {
  const EcoleDetailScreen({super.key, required this.ecoleId});
  final String ecoleId;

  @override
  State<EcoleDetailScreen> createState() => _EcoleDetailScreenState();
}

class _Bundle {
  final Map<String, dynamic> dataEcole;
  final Map<String, dynamic>? formulesEcole;
  final dynamic admis2026, admis2025;
  final double? scoreA;
  _Bundle(this.dataEcole, this.formulesEcole, this.admis2026, this.admis2025, this.scoreA);
}

class _EcoleDetailScreenState extends State<EcoleDetailScreen> {
  late Future<_Bundle> _future;

  /// Spécialité ouverte (une seule à la fois). La 1re est ouverte par défaut.
  int? _openIndex = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Bundle> _load() async {
    final results = await Future.wait([
      DatasetService.load('data'),
      DatasetService.load('formules_score_e'),
      DatasetService.load('admis_2026').catchError((_) => null),
      DatasetService.load('admis_2025').catchError((_) => null),
    ]);
    final data = results[0];
    final formules = results[1];

    Map<String, dynamic>? pick(dynamic ds) {
      final list = ((ds?['ecoles']) as List?)?.cast<Map<String, dynamic>>() ?? [];
      final m = list.where((e) => e['id'] == widget.ecoleId);
      return m.isEmpty ? null : m.first;
    }

    final dataEcole = pick(data);
    if (dataEcole == null) {
      throw Exception('Aucune école avec l\'identifiant "${widget.ecoleId}".');
    }
    final scoreA = await ScoreAStore.readScoreA();
    return _Bundle(dataEcole, pick(formules), results[2], results[3], scoreA);
  }

  /// Ouvre le calcul du Score A, puis recharge la fiche au retour.
  Future<void> _openScoreA() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const Scaffold(body: ScoreAScreen())),
    );
    if (!mounted) return;
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      body: FutureBuilder<_Bundle>(
        future: _future,
        builder: (context, snap) {
          final sigle = (snap.data?.dataEcole['sigle'] ?? '').toString().trim();
          return Column(
            children: [
              AppHeader(
                onBack: () => Navigator.of(context).maybePop(),
                eyebrow: 'Mutation 2025 · ${widget.ecoleId}',
                title: sigle.isNotEmpty ? sigle : widget.ecoleId,
              ),
              Expanded(child: _body(snap)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(AsyncSnapshot<_Bundle> snap) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
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
    final b = snap.data!;
    final specs = ((b.formulesEcole?['specialites']) as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final nom = (b.dataEcole['nom'] ?? b.dataEcole['sigle'] ?? '').toString();
    final n = specs.length;

    // Pas de SafeArea : le padding bas inclut la barre système Android.
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        // ── Nom de l'école + infos ──
        Text(nom,
            style: const TextStyle(
                fontSize: 18.5,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: AppColors.ink)),
        const SizedBox(height: 4),
        Text(
          n == 0
              ? 'Aucune spécialité'
              : '$n spécialité${n > 1 ? 's' : ''} · touche pour calculer',
          style: const TextStyle(fontSize: 13, color: _kMuted),
        ),
        const SizedBox(height: 12),
        _ScoreALine(scoreA: b.scoreA, onCalculer: _openScoreA),
        const SizedBox(height: 14),

        if (b.formulesEcole == null || specs.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text('Aucune formule pour cette école.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gray)),
          )
        else
          for (int i = 0; i < specs.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SpecCard(
                key: ValueKey('spec_$i'),
                spec: specs[i],
                dataEcole: b.dataEcole,
                admis2026: b.admis2026,
                admis2025: b.admis2025,
                scoreA: b.scoreA,
                expanded: _openIndex == i,
                onToggle: () => setState(
                    () => _openIndex = _openIndex == i ? null : i),
              ),
            ),
      ],
    );
  }
}

/// Ligne discrète « Ton Score A : 54,98 », ou invitation à le calculer.
class _ScoreALine extends StatelessWidget {
  const _ScoreALine({required this.scoreA, required this.onCalculer});
  final double? scoreA;
  final VoidCallback onCalculer;

  @override
  Widget build(BuildContext context) {
    final a = scoreA;
    if (a != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.calculate_outlined, size: 19, color: _kMuted),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Ton Score A',
                style: TextStyle(fontSize: 13.5, color: _kSoftText)),
          ),
          Text(_fr(a),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ]),
      );
    }
    return Material(
      color: _kCoralSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onCalculer,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, size: 19, color: _kCoralText),
            SizedBox(width: 10),
            Expanded(
              child: Text('Calcule d\'abord ton Score A pour avoir ton verdict',
                  style: TextStyle(fontSize: 13, height: 1.35, color: _kCoralText)),
            ),
            Icon(Icons.chevron_right_rounded, color: _kCoralText),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  SPÉCIALITÉ (accordéon)
// ─────────────────────────────────────────────────────────────────────────

class _SpecCard extends StatefulWidget {
  const _SpecCard({
    super.key,
    required this.spec,
    required this.dataEcole,
    required this.admis2026,
    required this.admis2025,
    required this.scoreA,
    required this.expanded,
    required this.onToggle,
  });
  final Map<String, dynamic> spec;
  final Map<String, dynamic> dataEcole;
  final dynamic admis2026, admis2025;
  final double? scoreA;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<_SpecCard> createState() => _SpecCardState();
}

class _SpecCardState extends State<_SpecCard> {
  late final List<Map<String, dynamic>> _groupes;
  late final List<String> _codes;
  late final List<String> _dataCodes; // codes mappés (crosswalk)
  late final List<String> _licencesCanoniques;
  late final String _ecoleId;

  int? _selectedIdx; // index de groupe choisi
  String? _suggestion;
  final Map<String, TextEditingController> _noteCtrls = {};
  String? _calcError;
  num? _scoreE;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _ecoleId = widget.dataEcole['id'].toString();
    _groupes = ((widget.spec['groupes_licences']) as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    _codes = engine.specCodes(widget.spec);
    final cw = engine.kManualCrosswalk[_ecoleId] ?? {};
    _dataCodes = _codes.map((c) => cw[c] ?? c).toList();

    final canon = <String>[];
    for (final c in _codes) {
      final found = engine.findLicencesForCode(widget.dataEcole, c, _ecoleId);
      if (found != null) {
        for (final l in found) {
          if (!canon.contains(l)) canon.add(l);
        }
      }
    }
    _licencesCanoniques = canon;

    // Une seule formule → sélection directe.
    if (_groupes.length == 1) _selectedIdx = 0;
  }

  @override
  void dispose() {
    for (final c in _noteCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // --- modes de sélection (port de renderEcole) ---
  bool get _plusieurs => _groupes.length > 1;

  List<String?> get _annees => _groupes.map((g) => g['annee_cible'] as String?).toList();
  bool get _splitParAnnee {
    final distinct = _annees.where((x) => x != null).toSet();
    return _plusieurs && distinct.length == _groupes.length;
  }

  List<String?> get _types =>
      _groupes.map((g) => g['type_candidature'] as String?).toList();
  bool get _splitParCandidature {
    final distinct = _types.where((x) => x != null).toSet();
    return !_splitParAnnee && _plusieurs && distinct.length == _groupes.length;
  }

  List<dynamic>? get _licencesVerifiees =>
      (widget.spec['licences_verifiees'] is List)
          ? widget.spec['licences_verifiees'] as List
          : null;
  bool get _splitParLicVerif {
    final lv = _licencesVerifiees;
    return _plusieurs && lv != null && lv.length == _groupes.length;
  }

  String _candidatureLabel(String? t) {
    if (t == 'interne') return 'Candidat interne (déjà inscrit ici)';
    if (t == 'externe') return 'Candidat externe (licence obtenue ailleurs)';
    return t ?? '';
  }

  void _onPickLicenceAuto(String licenceAr) {
    final res = engine.meilleurGroupePourLicence(licenceAr, _groupes);
    setState(() {
      _resetCalc();
      if (res.ambigu) {
        _suggestion = 'Plusieurs formules se ressemblent : vérifie-les dans « Détails ».';
        _selectedIdx = null;
      } else if (res.groupe != null && res.score > 0) {
        _suggestion = 'Formule choisie automatiquement (à vérifier dans « Détails »).';
        _selectedIdx = _groupes.indexOf(res.groupe!);
      } else {
        _suggestion = 'Aucune correspondance fiable : vérifie les formules dans « Détails ».';
        _selectedIdx = null;
      }
    });
  }

  void _resetCalc() {
    _calcError = null;
    _scoreE = null;
  }

  void _calculer() {
    FocusScope.of(context).unfocus();
    final g = (_selectedIdx != null) ? _groupes[_selectedIdx!] : null;
    final formule = g?['formule'] as Map<String, dynamic>?;
    if (formule == null) return;
    final vars = ((formule['variables']) as List?)?.cast<Map<String, dynamic>>() ?? [];

    final values = <String, num>{};
    final manquantes = <String>[];
    for (final v in vars) {
      final id = v['id'] as String;
      final raw = _noteCtrls[id]?.text.trim() ?? '';
      if (raw.isEmpty) {
        manquantes.add(v['label'].toString());
      } else {
        values[id] = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
      }
    }
    if (manquantes.isNotEmpty) {
      setState(() {
        _calcError = 'Merci de renseigner : ${manquantes.join(', ')}';
        _scoreE = null;
      });
      return;
    }
    try {
      final paliers = (widget.spec['bareme']?['paliers']) as List?;
      final score = engine.computeScore(formule, values, paliers);
      setState(() {
        _calcError = null;
        _scoreE = (score * 100).round() / 100;
      });
      InterstitialAdService.registerAction(); // calcul Score E réussi
    } catch (e) {
      setState(() {
        _calcError = 'Erreur de calcul : $e';
        _scoreE = null;
      });
    }
  }

  // ── Seuils (référence 2026, sinon 2025) ──
  engine.Seuils? get _s2026 =>
      engine.seuilsForYear(widget.admis2026, _ecoleId, _dataCodes, '2026');
  engine.Seuils? get _s2025 =>
      engine.seuilsForYear(widget.admis2025, _ecoleId, _dataCodes, '2025');

  ({engine.Seuils seuils, String year})? get _ref {
    final a = _s2026, b = _s2025;
    if (a != null && (a.dernier != null || a.premier != null)) {
      return (seuils: a, year: '2026');
    }
    if (b != null && (b.dernier != null || b.premier != null)) {
      return (seuils: b, year: '2025');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final code = _codes.isEmpty ? '—' : _codes.join(' / ');
    final nom = (widget.spec['nom'] ?? '').toString();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── En-tête cliquable : code + nom + chevron ──
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(code,
                          style: const TextStyle(fontSize: 11.5, color: _kMuted)),
                      const SizedBox(height: 2),
                      Text(nom,
                          style: const TextStyle(
                              fontSize: 16,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink)),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: widget.expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 24, color: _kHint),
                ),
              ]),
            ),
          ),

          // ── Contenu (ouvert / fermé en douceur) ──
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: widget.expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _content(),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final g = _selectedIdx != null ? _groupes[_selectedIdx!] : null;
    final formule = g?['formule'] as Map<String, dynamic>?;
    final vars = ((formule?['variables']) as List?)?.cast<Map<String, dynamic>>() ?? [];
    final texte = formule?['texte']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 1, color: _kLine),
        const SizedBox(height: 12),

        // Choix éventuel (année / type / licence)
        ..._selector(),

        if (g != null && vars.isEmpty)
          _softNote(
            (texte == null || texte.isEmpty)
                ? 'Formule non disponible${g['remarque'] != null ? ' — ${g['remarque']}' : ''}.'
                : 'Pas de notes à saisir pour cette formule (voir « Détails »).',
          ),

        // Notes
        if (vars.isNotEmpty) ...[
          const Text('Tes notes sur 20',
              style: TextStyle(fontSize: 12.5, color: _kMuted)),
          const SizedBox(height: 4),
          for (final v in vars) _noteRow(v),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: _kCoral,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _calculer,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: Text('Calculer mon score',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ),
            ),
          ),
          if (_calcError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_calcError!,
                  style: const TextStyle(fontSize: 13, color: _kCoralText)),
            ),
          if (_scoreE != null) ...[
            const SizedBox(height: 12),
            _verdict(_scoreE!),
          ],
        ],

        // Détails repliés
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _showDetails = !_showDetails),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: _kMuted),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Détails : formule, licences, seuils',
                    style: TextStyle(fontSize: 13, color: _kSoftText)),
              ),
              AnimatedRotation(
                turns: _showDetails ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: _kHint),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _showDetails ? _details(g) : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  // ── Choix de la formule ──
  List<Widget> _selector() {
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(t, style: const TextStyle(fontSize: 12.5, color: _kMuted)),
        );

    if (_splitParAnnee || _splitParCandidature) {
      return [
        label(_splitParAnnee ? "Année d'accès visée" : 'Type de candidature'),
        DropdownButtonFormField<int>(
          value: _selectedIdx,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _kMuted),
          style: const TextStyle(fontSize: 14.5, color: AppColors.ink),
          decoration: _fieldDecoration(),
          hint: const Text('Choisir', style: TextStyle(fontSize: 14, color: _kHint)),
          items: [
            for (int gi = 0; gi < _groupes.length; gi++)
              DropdownMenuItem(
                value: gi,
                child: Text(
                  _splitParAnnee ? (_annees[gi] ?? '') : _candidatureLabel(_types[gi]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() {
            _selectedIdx = v;
            _resetCalc();
          }),
        ),
        const SizedBox(height: 14),
      ];
    }

    if (_splitParLicVerif) {
      final options = <MapEntry<String, int>>[];
      for (int gi = 0; gi < _licencesVerifiees!.length; gi++) {
        final entry = _licencesVerifiees![gi];
        final arr = entry is List ? entry : [entry];
        for (final l in arr) {
          options.add(MapEntry(l.toString(), gi));
        }
      }
      return [
        label('Ta licence exacte'),
        DropdownButtonFormField<int>(
          value: _selectedIdx,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _kMuted),
          style: const TextStyle(fontSize: 14.5, color: AppColors.ink),
          decoration: _fieldDecoration(),
          hint: const Text('Choisir', style: TextStyle(fontSize: 14, color: _kHint)),
          items: [
            for (final o in options)
              DropdownMenuItem(
                value: o.value,
                child: Text(o.key,
                    textDirection: TextDirection.rtl, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() {
            _selectedIdx = v;
            _resetCalc();
          }),
        ),
        const SizedBox(height: 14),
      ];
    }

    if (_plusieurs && _licencesCanoniques.isNotEmpty) {
      return [
        label('Ta licence exacte'),
        DropdownButtonFormField<String>(
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _kMuted),
          style: const TextStyle(fontSize: 14.5, color: AppColors.ink),
          decoration: _fieldDecoration(),
          hint: const Text('Choisir', style: TextStyle(fontSize: 14, color: _kHint)),
          items: [
            for (final l in _licencesCanoniques)
              DropdownMenuItem(
                value: l,
                child: Text(l,
                    textDirection: TextDirection.rtl, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) _onPickLicenceAuto(v);
          },
        ),
        if (_suggestion != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_suggestion!,
                style: const TextStyle(fontSize: 12, height: 1.4, color: _kMuted)),
          ),
        const SizedBox(height: 14),
      ];
    }

    return const [];
  }

  /// Ligne de note : matière à gauche, champ (0 → 20) à droite.
  Widget _noteRow(Map<String, dynamic> v) {
    final id = v['id'] as String;
    final ctrl = _noteCtrls.putIfAbsent(id, () => TextEditingController());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Text(v['label'].toString(),
              style: const TextStyle(fontSize: 14.5, color: AppColors.ink)),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 96,
          child: TextField(
            controller: ctrl,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 15, color: AppColors.ink),
            inputFormatters: const [_MoyenneFormatter(max: 20)],
            decoration: _fieldDecoration(hint: '—'),
          ),
        ),
      ]),
    );
  }

  /// UN seul bloc résultat : verdict + Score général (+ Score E en petit).
  Widget _verdict(num scoreE) {
    final a = widget.scoreA;

    // Sans Score A : on montre juste le Score E.
    if (a == null) {
      return _resultBox(
        bg: _kFieldBg,
        fg: AppColors.ink,
        icon: Icons.functions_rounded,
        title: 'Score E : ${_fr(scoreE)}',
        subtitle: 'Calcule ton Score A pour obtenir ton verdict.',
      );
    }

    // Score général = 0,7·A + 0,3·E, arrondi à 2 décimales (comme le JS).
    final sg = ((0.7 * a + 0.3 * scoreE) * 100).round() / 100;
    final ref = _ref;
    final dernier = ref?.seuils.dernier;

    if (ref == null || dernier == null) {
      return _resultBox(
        bg: _kFieldBg,
        fg: AppColors.ink,
        icon: Icons.info_outline_rounded,
        title: 'Score général : ${_fr(sg)}',
        subtitle: 'Score E ${_fr(scoreE)} · seuils non disponibles pour cette filière.',
      );
    }

    final d = sg - dernier;
    final sub = 'Score général ${_fr(sg)} · dernier admis ${ref.year} : $dernier';
    if (d >= 2) {
      return _resultBox(
          bg: _kBlueSoft,
          fg: AppColors.blue,
          icon: Icons.check_circle_rounded,
          title: 'Admissible probable',
          subtitle: sub);
    } else if (d >= -2) {
      return _resultBox(
          bg: _kCoralSoft,
          fg: _kCoralText,
          icon: Icons.warning_amber_rounded,
          title: 'Limite',
          subtitle: sub);
    }
    return _resultBox(
        bg: _kCoral,
        fg: Colors.white,
        icon: Icons.cancel_rounded,
        title: 'Difficile',
        subtitle: sub);
  }

  Widget _resultBox({
    required Color bg,
    required Color fg,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: fg)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, height: 1.4, color: fg.withOpacity(.85))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Contenu de « Détails » : formule, Score E, licences, seuils, autres formules.
  Widget _details(Map<String, dynamic>? g) {
    final texte = (g?['formule']?['texte'])?.toString();
    final s26 = _s2026, s25 = _s2025;

    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(t,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _kMuted)),
        );
    Widget plain(String t) => Text(t,
        style: const TextStyle(fontSize: 13.5, height: 1.55, color: _kSoftText));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (texte != null && texte.isNotEmpty) ...[
          title('Formule'),
          plain(texte),
        ],
        if (_scoreE != null) ...[
          title('Score E calculé'),
          plain(_fr(_scoreE!)),
        ],
        if (_licencesCanoniques.isNotEmpty) ...[
          title('Licences acceptées'),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in _licencesCanoniques)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: _kFieldBg, borderRadius: BorderRadius.circular(8)),
                    child: Text(l,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 12.5, color: _kSoftText)),
                  ),
              ],
            ),
          ),
        ],
        if (s26 != null || s25 != null) ...[
          title('Seuils d\'admission'),
          for (final item in [('2026', s26), ('2025', s25)])
            if (item.$2 != null)
              plain('${item.$1} · dernier ${item.$2!.dernier ?? '—'} · premier ${item.$2!.premier ?? '—'}'
                  '${item.$2!.nb != null ? ' · ${item.$2!.nb} admis' : ''}'),
          const SizedBox(height: 4),
          const Text('Indicatif : comparaison au dernier admis, marge ±2. Les seuils changent chaque année.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: _kMuted)),
        ],
        if (_plusieurs) ...[
          title('Toutes les formules'),
          for (final gr in _groupes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: plain('• ${((gr['formule']?['texte']) ?? 'Formule non disponible').toString()}'),
            ),
        ],
      ],
    );
  }

  Widget _softNote(String t) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: _kFieldBg, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: const TextStyle(fontSize: 13, color: _kSoftText)),
      );
}

// ─────────────────────────────────────────────────────────────────────────
//  CHAMPS
// ─────────────────────────────────────────────────────────────────────────

/// Champ : fond gris clair, sans bordure, contour bleu au focus.
InputDecoration _fieldDecoration({String? hint}) {
  OutlineInputBorder border(Color c, [double w = 0]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: _kHint, fontSize: 14),
    isDense: true,
    filled: true,
    fillColor: _kFieldBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: border(Colors.transparent),
    focusedBorder: border(AppColors.blue, 1.5),
    border: border(Colors.transparent),
  );
}

/// Limite la saisie d'une note à [0 ; max] avec au plus 2 décimales.
class _MoyenneFormatter extends TextInputFormatter {
  const _MoyenneFormatter({this.max = 20});
  final double max;

  static final RegExp _pattern = RegExp(r'^\d{0,2}([.,]\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (!_pattern.hasMatch(text)) return oldValue;
    final v = double.tryParse(text.replaceAll(',', '.'));
    if (v != null && v > max) return oldValue;
    return newValue;
  }
}