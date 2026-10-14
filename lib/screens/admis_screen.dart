// admis_screen.dart — Admis par école (portage mobile de assets/js/admis-2025.js)
//
// Charge admis_2026 puis admis_2025 via DatasetService (Cloudflare KV).
// L'année active suit la priorité 2026, avec un switch si les deux existent.
// Le titre est TOUJOURS dynamique (« Admis 2026 ») — jamais figé sur 2025.
//
// Liste (cette classe) -> détail d'une école (_AdmisSchoolScreen, pushé) :
// hero (crest + KPIs Admis/Filières/Meilleur) puis les filières en accordéon
// avec le tableau Rang / Nom / Score et la ligne « seuil ».
//
// PUBS : l'ID du bloc natif vient de AdIds.native (ad_service.dart).

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_header.dart';
import '../services/ad_service.dart';
import '../services/dataset_service.dart';
import '../services/native_ad_manager.dart';

// 1 natif toutes les _kAdEvery écoles, plafonné à _kMaxAds, hauteur _kNativeAdHeight.
const int _kAdEvery = 5;
const int _kMaxAds = 3;
const double _kNativeAdHeight = 205;

class AdmisScreen extends StatefulWidget {
  const AdmisScreen({super.key});
  @override
  State<AdmisScreen> createState() => _AdmisScreenState();
}

class _AdmisScreenState extends State<AdmisScreen> {
  late Future<Map<String, List<_AdmisSchool>>> _future;

  /// Année de session active ('2026' en priorité).
  String? _year;

  /// Recherche.
  String _q = '';

  /// Natifs in-feed : préchargés + gardés en cache pour la durée de l'écran.
  late final NativeAdManager _adManager;

  @override
  void initState() {
    super.initState();
    _adManager = NativeAdManager(
      adUnitId: AdIds.native,
      factoryId: 'ecoleAdFactory',
      maxAds: _kMaxAds,
    );
    _future = _load();
    // Fixe l'année active dès que les données arrivent (sans muter en build).
    _future.then((byYear) {
      if (!mounted) return;
      final years = byYear.keys.toList();
      if (_year == null || !years.contains(_year)) {
        setState(() => _year = years.first);
      }
    }).catchError((_) {});
  }

  /// Charge les deux années (2026 prioritaire) et construit les écoles.
  Future<Map<String, List<_AdmisSchool>>> _load() async {
    final byYear = <String, List<_AdmisSchool>>{};
    for (final y in const ['2026', '2025']) {
      try {
        final j = await DatasetService.load('admis_$y');
        final ecoles = ((j['ecoles'] as List?) ?? []).cast<Map<String, dynamic>>();
        final schools = _buildSchools(ecoles);
        if (schools.isNotEmpty) byYear[y] = schools;
      } catch (_) {
        // année absente / erreur réseau : on ignore, on garde l'autre année.
      }
    }
    if (byYear.isEmpty) {
      throw Exception('Aucune donnée disponible (ni 2026 ni 2025).');
    }
    return byYear;
  }

  /// Équivalent de buildSchools() côté web : groupe par id, collecte les
  /// années d'étude et aplatit les filières + leurs admis (rang = ordre).
  List<_AdmisSchool> _buildSchools(List<Map<String, dynamic>> ecoles) {
    final byId = <String, _AdmisSchool>{};
    final order = <String>[];

    for (final e in ecoles) {
      final id = (e['id'] ?? '').toString();
      final s = byId.putIfAbsent(id, () {
        order.add(id);
        return _AdmisSchool(id: id, nom: (e['nom'] ?? '').toString());
      });

      final annee = (e['annee'] ?? '').toString();
      if (annee.isNotEmpty && !s.annees.contains(annee)) s.annees.add(annee);

      for (final f in ((e['filieres'] as List?) ?? [])) {
        if (f is! Map) continue;
        final admis = ((f['admis'] as List?) ?? []);
        final students = <_AdmisStudent>[];
        for (var i = 0; i < admis.length; i++) {
          final a = admis[i];
          if (a is! Map) continue;
          final sc = a['score'];
          students.add(_AdmisStudent(
            rank: i + 1,
            score: sc is num ? sc.toDouble() : null,
            nom: (a['nom'] ?? '').toString(),
            prenom: (a['prenom'] ?? '').toString(),
          ));
        }
        s.fils.add(_AdmisFiliere(
          code: (f['code'] ?? '---').toString(),
          nomFr: (f['nom_fr'] ?? f['nom'] ?? 'Filière sans nom').toString(),
          nomAr: (f['nom_ar'] ?? '').toString(),
          annee: annee,
          students: students,
        ));
      }
    }

    final list = order.map((id) => byId[id]!).toList();
    list.sort((a, b) => a.nom.toLowerCase().compareTo(b.nom.toLowerCase()));
    return list;
  }

  Future<void> _refresh() async {
    final data = await _load();
    if (!mounted) return;
    setState(() => _future = Future.value(data));
  }

  @override
  void dispose() {
    _adManager.dispose();
    super.dispose();
  }

  String get _activeYear => _year ?? '2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppHeader(
              eyebrow: 'Session $_activeYear · Listes officielles',
              title: 'Admis $_activeYear',
              bottom: FutureBuilder<Map<String, List<_AdmisSchool>>>(
                future: _future,
                builder: (context, snap) {
                  final years = snap.hasData ? snap.data!.keys.toList() : const <String>[];
                  final active =
                      (years.contains(_year)) ? _year! : (years.isNotEmpty ? years.first : _activeYear);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (years.length > 1) ...[
                        _yearSwitch(years, active),
                        const SizedBox(height: 10),
                      ],
                      _searchField('Rechercher une école (nom, code)…'),
                    ],
                  );
                },
              ),
            ),
            Expanded(child: SafeArea(top: false, child: _body())),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    return FutureBuilder<Map<String, List<_AdmisSchool>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _refreshable(_error(snap.error.toString()));

        final byYear = snap.data!;
        final years = byYear.keys.toList();
        final year = years.contains(_year) ? _year! : years.first;
        final schools = byYear[year]!;

        final q = _q.toLowerCase().trim();
        final list = schools.where((s) {
          if (q.isEmpty) return true;
          if (('${s.nom} ${s.id}').toLowerCase().contains(q)) return true;
          return s.fils.any((f) => f.nomFr.toLowerCase().contains(q));
        }).toList();

        if (list.isEmpty) {
          return _refreshable(_notice(
            icon: Icons.search_off,
            title: 'Aucune école',
            body: q.isEmpty
                ? 'Aucune donnée disponible.'
                : 'Aucune école ne correspond à « $q ».',
          ));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
              child: Text('${list.length} / ${schools.length} écoles',
                  style: const TextStyle(fontSize: 13, color: AppColors.gray)),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.blue,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
                  children: _buildFeed(list, year),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Liste : cartes écoles + un natif in-feed toutes les [_kAdEvery] écoles
  /// (jamais 1re/dernier, jamais deux collés), plafonné à [_kMaxAds], préchargé.
  List<Widget> _buildFeed(List<_AdmisSchool> list, String year) {
    final children = <Widget>[];
    int adSlot = 0;
    for (int i = 0; i < list.length; i++) {
      if (i > 0) children.add(const SizedBox(height: 12));
      children.add(_SchoolCard(school: list[i], year: year));
      final bool fin = (i + 1) % _kAdEvery == 0;
      final bool reste = i < list.length - 1;
      if (fin && reste && adSlot < _kMaxAds) {
        children.add(const SizedBox(height: 12));
        children.add(InFeedNativeAd(
            manager: _adManager, slotIndex: adSlot, height: _kNativeAdHeight));
        adSlot++;
      }
    }
    _adManager.preload(adSlot);
    return children;
  }

  // ── Header widgets ───────────────────────────────────────────────────────

  Widget _yearSwitch(List<String> years, String active) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final y in years)
              GestureDetector(
                onTap: () => setState(() => _year = y),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: y == active ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(y,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: y == active ? kBleuRoi : Colors.white,
                      )),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _searchField(String hint) {
    return TextField(
      onChanged: (v) => setState(() => _q = v),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.graySoft),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // ── Notices ──────────────────────────────────────────────────────────────

  Widget _refreshable(Widget child) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.blue,
      child: LayoutBuilder(
        builder: (ctx, c) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [SizedBox(height: c.maxHeight, child: child)],
        ),
      ),
    );
  }

  Widget _notice({required IconData icon, required String title, required String body}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.graySoft),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.gray)),
          ],
        ),
      ),
    );
  }

  Widget _error(String err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SoftCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: AppColors.graySoft),
              const SizedBox(height: 12),
              const Text('Chargement impossible',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 8),
              Text(err,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.gray)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  CARTE ÉCOLE (liste)
// ─────────────────────────────────────────────────────────────────────────

class _SchoolCard extends StatelessWidget {
  const _SchoolCard({required this.school, required this.year});
  final _AdmisSchool school;
  final String year;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      radius: 18,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _AdmisSchoolScreen(school: school, year: year)),
      ),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(school.id, style: AppTheme.mono(size: 12, color: AppColors.blue)),
          const SizedBox(height: 6),
          Text(school.nom,
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1.2)),
          if (school.annees.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final a in school.annees) _YearTag(a)],
            ),
          ],
          const SizedBox(height: 11),
          Container(
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEF0F7)))),
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('${school.total} admis · ${school.fils.length} filières',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.gray)),
                ),
                const Icon(Icons.arrow_forward, size: 16, color: AppColors.blue),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _YearTag extends StatelessWidget {
  const _YearTag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FD),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2B3A87))),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  ÉCRAN DÉTAIL D'UNE ÉCOLE
// ─────────────────────────────────────────────────────────────────────────

class _AdmisSchoolScreen extends StatelessWidget {
  const _AdmisSchoolScreen({required this.school, required this.year});
  final _AdmisSchool school;
  final String year;

  @override
  Widget build(BuildContext context) {
    // Scaffold transparent : indispensable pour fournir un ancêtre Material à
    // l'ExpansionTile / ListTile (sinon « No Material widget found »).
    // Transparent pour laisser voir le dégradé d'AppBackground.
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Natif fixe en bas, ancré comme une nav bar (façon _NativeAdBlock de
      // l'accueil). Reste en place pendant que la liste défile.
      bottomNavigationBar: const _AdmisBottomNativeAd(),
      body: AppBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barre supérieure : retour + fil d'ariane.
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Text('Admis $year',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.gray)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
                  children: [
                    _hero(),
                    const SizedBox(height: 16),
                    for (var i = 0; i < school.fils.length; i++) ...[
                      _FiliereTile(filiere: school.fils[i], initiallyOpen: i == 0),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    return SoftCard(
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFDBE3FB),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Text(_crest(school.nom),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.blue)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(school.id, style: AppTheme.mono(size: 11, color: AppColors.blue)),
                    const SizedBox(height: 2),
                    Text(school.nom,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1.2)),
                  ],
                ),
              ),
            ],
          ),
          if (school.annees.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final a in school.annees) _YearTag(a)]),
          ],
          const SizedBox(height: 14),
          Container(
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEF0F7)))),
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                _kpi('${school.total}', 'Admis'),
                _kpi('${school.fils.length}', 'Filières'),
                _kpi(school.bestScore != null ? _fmt1(school.bestScore!) : '—', 'Meilleur'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String n, String l) {
    return Expanded(
      child: Column(
        children: [
          Text(n,
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text(l, style: const TextStyle(fontSize: 11.5, color: AppColors.gray)),
        ],
      ),
    );
  }

  String _crest(String nom) {
    final letters = nom.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
    return (letters.isEmpty ? '?' : letters.substring(0, letters.length >= 3 ? 3 : letters.length))
        .toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  NATIF FIXE EN BAS (façon nav bar) — template « small », comme l'accueil
// ─────────────────────────────────────────────────────────────────────────

/// Natif ancré en bas de l'écran des admis d'une école. Utilise le template
/// Google « small » (compact, horizontal, ~120 px) : aucun code natif requis,
/// marche aussi sur iOS. Tant que l'annonce n'est pas chargée, rien n'est
/// affiché (le bottomNavigationBar prend une hauteur nulle).
class _AdmisBottomNativeAd extends StatefulWidget {
  const _AdmisBottomNativeAd();

  @override
  State<_AdmisBottomNativeAd> createState() => _AdmisBottomNativeAdState();
}

class _AdmisBottomNativeAdState extends State<_AdmisBottomNativeAd> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _ad = NativeAd(
      adUnitId: AdIds.native,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: Colors.white,
        cornerRadius: 0,
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          // Silencieux : pas de pub = pas de barre.
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Container(
      // Petite bordure haute pour détacher la barre du contenu.
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEF0F7))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 90, // hauteur mini du template small (monte à ~96 si rogné)
          width: double.infinity,
          child: AdWidget(ad: _ad!),
        ),
      ),
    );
  }
}

/// Filière repliable (accordéon) + tableau des admis.
class _FiliereTile extends StatelessWidget {
  const _FiliereTile({required this.filiere, required this.initiallyOpen});
  final _AdmisFiliere filiere;
  final bool initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final last = filiere.students.isNotEmpty ? filiere.students.last : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE3E7F5)),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyOpen,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            iconColor: AppColors.blue,
            collapsedIconColor: AppColors.blue,
            title: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 10, top: 2),
                  decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(filiere.nomFr,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                        [filiere.code, filiere.annee].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 11, color: AppColors.graySoft),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${filiere.students.length} admis',
                        style: const TextStyle(fontSize: 11, color: AppColors.gray)),
                    if (last != null)
                      Text('seuil ${_fmt2(last.score)}',
                          style: const TextStyle(fontSize: 11, color: AppColors.gray)),
                  ],
                ),
              ],
            ),
            children: [_table(filiere, last)],
          ),
        ),
      ),
    );
  }

  Widget _table(_AdmisFiliere f, _AdmisStudent? last) {
    const th = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.graySoft);
    Widget row(Widget rank, Widget name, Widget score, {bool border = true}) {
      return Container(
        decoration: border
            ? const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF0F7))))
            : null,
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(width: 46, child: rank),
            Expanded(child: name),
            SizedBox(width: 62, child: score),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: const [
              SizedBox(width: 46, child: Text('Rang', style: th)),
              Expanded(child: Text('Nom', style: th)),
              SizedBox(width: 62, child: Text('Score', style: th, textAlign: TextAlign.right)),
            ],
          ),
        ),
        for (final st in f.students)
          row(
            _rankBadge(st.rank),
            Text(_studentName(st),
                style: const TextStyle(fontSize: 13, color: AppColors.ink)),
            Text(_fmt2(st.score),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
        if (last != null)
          row(
            const Text('seuil',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.graySoft)),
            const SizedBox(),
            Text(_fmt2(last.score),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, color: AppColors.graySoft)),
          ),
      ],
    );
  }

  Widget _rankBadge(int rank) {
    final top = rank <= 3;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: top ? const Color(0xFFDBE3FB) : const Color(0xFFF1F3FA),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(rank.toString().padLeft(2, '0'),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: top ? AppColors.blue : AppColors.gray)),
      ),
    );
  }

  String _studentName(_AdmisStudent st) {
    final n = ('${st.prenom} ${st.nom}').trim();
    return n.isEmpty ? '—' : n;
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  MODÈLES + FORMATAGE
// ─────────────────────────────────────────────────────────────────────────

class _AdmisSchool {
  _AdmisSchool({required this.id, required this.nom});
  final String id;
  final String nom;
  final List<String> annees = [];
  final List<_AdmisFiliere> fils = [];

  int get total => fils.fold(0, (a, f) => a + f.students.length);

  double? get bestScore {
    double? best;
    for (final f in fils) {
      for (final st in f.students) {
        if (st.score != null && (best == null || st.score! > best)) best = st.score;
      }
    }
    return best;
  }
}

class _AdmisFiliere {
  _AdmisFiliere({
    required this.code,
    required this.nomFr,
    required this.nomAr,
    required this.annee,
    required this.students,
  });
  final String code, nomFr, nomAr, annee;
  final List<_AdmisStudent> students;
}

class _AdmisStudent {
  _AdmisStudent({required this.rank, required this.score, required this.nom, required this.prenom});
  final int rank;
  final double? score;
  final String nom, prenom;
}

/// Score à la française, 2 décimales (156.4 -> "156,40" ; null -> "—").
String _fmt2(double? v) =>
    v == null ? '—' : v.toStringAsFixed(2).replaceAll('.', ',');

/// Score à la française, 1 décimale (pour le « Meilleur »).
String _fmt1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');