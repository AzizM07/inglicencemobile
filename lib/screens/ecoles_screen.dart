// ecoles_screen.dart — Répertoire des écoles (portage mobile de ecoles.html)
//
// Charge le dataset 'data' via DatasetService et liste les écoles.
// Recherche par sigle / nom / ville. Touche une carte -> EcoleInfoScreen
// (la fiche de l'école : infos + filières + licences acceptées).
//
// MONÉTISATION : natif in-feed personnalisé (style _EcoleCard) toutes les
// _kAdEvery écoles, plafonné à _kMaxAds, préchargé + gardé en cache.
// L'ID du bloc natif vient de AdIds.native (ad_service.dart).

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_header.dart';
import '../services/ad_service.dart';
import '../services/dataset_service.dart';
import '../services/native_ad_manager.dart';
import 'ecole_info_screen.dart';

const int _kAdEvery = 5;
const int _kMaxAds = 3;
const double _kNativeAdHeight = 205;

class EcolesScreen extends StatefulWidget {
  const EcolesScreen({super.key});
  @override
  State<EcolesScreen> createState() => _EcolesScreenState();
}

class _EcolesScreenState extends State<EcolesScreen> {
  late Future<List<Map<String, dynamic>>> _future;
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
  }

  @override
  void dispose() {
    _adManager.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await DatasetService.load('data');
    return ((data['ecoles'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<void> _refresh() async {
    final data = await _load();
    if (!mounted) return;
    setState(() => _future = Future.value(data));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppHeader(
              eyebrow: 'Répertoire · Mutation MESRS',
              title: 'Les écoles d\'ingénieurs',
              bottom: _searchField('Rechercher (sigle, nom, ville)…'),
            ),
            Expanded(child: SafeArea(top: false, child: _body())),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _refreshable(_error(snap.error.toString()));

        final all = snap.data!;
        final q = _q.toLowerCase().trim();
        final list = all.where((ec) {
          if (q.isEmpty) return true;
          final hay = '${ec['sigle'] ?? ''} ${ec['id'] ?? ''} '
                  '${ec['nom'] ?? ''} ${ec['adresse'] ?? ''}'
              .toLowerCase();
          return hay.contains(q);
        }).toList();

        if (list.isEmpty) {
          return _refreshable(_notice(
            icon: Icons.search_off,
            title: 'Aucune école',
            body: q.isEmpty ? 'Aucune donnée disponible.' : 'Aucune école trouvée.',
          ));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
              child: Text('${list.length} école${list.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 13, color: AppColors.gray)),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: AppColors.blue,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
                  children: _buildFeed(list),
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
  List<Widget> _buildFeed(List<Map<String, dynamic>> list) {
    final children = <Widget>[];
    int adSlot = 0;
    for (int i = 0; i < list.length; i++) {
      if (i > 0) children.add(const SizedBox(height: 12));
      children.add(_EcoleCard(ecole: list[i]));
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
//  CARTE ÉCOLE
// ─────────────────────────────────────────────────────────────────────────

class _EcoleCard extends StatelessWidget {
  const _EcoleCard({required this.ecole});
  final Map<String, dynamic> ecole;

  @override
  Widget build(BuildContext context) {
    final id = (ecole['id'] ?? '').toString();
    final sigle = (ecole['sigle'] ?? id).toString();
    final nom = (ecole['nom'] ?? '').toString();
    final nbFil = ((ecole['filieres'] as List?) ?? const []).length;
    final places = (ecole['total_places_annee1'] is num)
        ? (ecole['total_places_annee1'] as num).toInt()
        : 0;

    return SoftCard(
      radius: 18,
      // « Les écoles » ouvre la FICHE de l'école (infos + filières).
      // Le bouton « Calculer le Score E » de la fiche mène à EcoleDetailScreen.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EcoleInfoScreen(ecole: ecole)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sigle,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.3)),
          if (nom.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(nom,
                textDirection: TextDirection.rtl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF3D4266), height: 1.5)),
          ],
          const SizedBox(height: 12),
          Container(
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEF0F7)))),
            padding: const EdgeInsets.only(top: 11),
            child: Row(
              children: [
                _stat('$nbFil', 'filière${nbFil > 1 ? 's' : ''}'),
                const SizedBox(width: 18),
                _stat('$places', 'place${places > 1 ? 's' : ''}'),
                const Spacer(),
                const Icon(Icons.arrow_forward, size: 16, color: AppColors.blue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String n, String l) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12.5, color: AppColors.gray),
        children: [
          TextSpan(
              text: '$n ',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.blue)),
          TextSpan(text: l),
        ],
      ),
    );
  }
}