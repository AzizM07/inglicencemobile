import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_header.dart';
import '../services/dataset_service.dart';
import 'ecole_detail_screen.dart';
import '../services/ad_service.dart';
import '../services/licence_store.dart';
import '../services/native_ad_manager.dart';

// PUBS : l'ID du bloc natif vient de AdIds.native (ad_service.dart).

// Rythme du natif in-feed : une pub toutes les _kAdEvery écoles, avec un
// plafond _kMaxAds pour ne jamais charger trop de natifs d'un coup (fill /
// rate-limit AdMob). Change juste ces deux valeurs pour ajuster (4/5/6…).
const int _kAdEvery = 5;
const int _kMaxAds = 3;

// Hauteur de la carte native PERSONNALISÉE (layout Android
// ecole_native_ad.xml). 205 laisse de la marge pour que le bouton « Install »
// ne soit jamais rogné. Si tu la trouves trop haute, passe le body à
// maxLines="1" dans le XML et redescends vers ~170.
const double _kNativeAdHeight = 205;

// Nombre de filières affichées sur une carte avant « +N ».
const int _kChipsPreview = 4;

// Couleurs du style « minimal » (identiques à Score A).
const Color _kSoftBg = Color(0xFFF3F5FC);
const Color _kAvatarBg = Color(0xFFE8EDFF);
const Color _kMuted = Color(0xFF8A90A8);
const Color _kChipText = Color(0xFF2F3A72);
const Color _kLine = Color(0xFFEEF0F7);

/// Sélection d'une licence → écoles où cette licence est acceptée.
/// Le filtre compare le `license_id` choisi aux `license_ids` des filières
/// (les datasets `data` et `formules_score_e` doivent être en version *.with_ids).
///
/// La licence choisie est ENREGISTRÉE dans LicenceStore : le header de
/// l'accueil l'affiche alors automatiquement (à droite du Score A). Elle est
/// aussi rechargée ici à l'ouverture, pour que l'écran se souvienne du dernier
/// choix.
///
/// DESIGN « minimal » (même style que Score A) :
///  • sans licence : écran d'accueil avec icône + bouton « Choisir ma licence » ;
///  • compteur « N écoles acceptent votre licence » ;
///  • grandes cartes école : pastille sigle, nom complet (2 lignes, jamais
///    coupé), code, bouton rond ›, filières en étiquettes (4 max + « +N ») ;
///  • le bas de la liste n'est plus caché par la barre de navigation.
///
/// MONÉTISATION :
///  • Natif in-feed : une carte pub PERSONNALISÉE tous les _kAdEvery résultats,
///    plafonnée à _kMaxAds. Les annonces sont PRÉCHARGÉES et MISES EN CACHE par
///    NativeAdManager → elles restent à leur place quand on scrolle.
///  • Interstitiel : SEUL déclencheur gardé = l'ouverture de fiche école
///    (InterstitialAdService.registerEcoleOpen) → une pub toutes les 3 fiches
///    ouvertes, avec un cap de temps de 60 s (voir ad_service.dart). Le choix
///    de licence et les changements d'onglet ne déclenchent AUCUN interstitiel.
class ScoreEScreen extends StatefulWidget {
  const ScoreEScreen({super.key});
  @override
  State<ScoreEScreen> createState() => _ScoreEScreenState();
}

class _ScoreEScreenState extends State<ScoreEScreen> {
  late Future<_ScoreEData> _future;

  /// Licence sélectionnée par l'étudiant.
  Map<String, dynamic>? _selected;

  /// Gestionnaire de natifs : précharge + garde les annonces en cache pour
  /// toute la durée de vie de l'écran.
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
    // Recharge la dernière licence enregistrée (partagée avec l'accueil).
    final saved = LicenceStore.current.value;
    if (saved != null) {
      _selected = saved.toMap();
    }
  }

  @override
  void dispose() {
    _adManager.dispose(); // libère toutes les annonces natives en cache
    super.dispose();
  }

  Future<_ScoreEData> _load() async {
    final data = await DatasetService.load('data');
    final lic = await DatasetService.load('licences');

    final ecoles =
        ((data['ecoles'] as List?) ?? []).cast<Map<String, dynamic>>();

    final licences = ((lic['licences'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        // On n'affiche pas le pseudo-code "ANY" dans le menu.
        .where((l) => (l['license_id'] ?? '') != 'ANY')
        .toList()
      ..sort((a, b) =>
          (a['ar'] ?? '').toString().compareTo((b['ar'] ?? '').toString()));

    return _ScoreEData(ecoles: ecoles, licences: licences);
  }

  /// Pull-to-refresh : recharge sans faire clignoter l'écran (on garde
  /// l'ancien contenu affiché pendant que le spinner tourne).
  Future<void> _refresh() async {
    final data = await _load();
    if (!mounted) return;
    setState(() => _future = Future.value(data));
  }

  /// Ouvre la liste des licences et enregistre le choix (header + bouton).
  Future<void> _pickLicence(List<Map<String, dynamic>> licences) async {
    final choice = await _openPicker(licences);
    if (choice != null) {
      setState(() => _selected = choice);
      LicenceStore.save(choice); // → affichée auto sur l'accueil
      // Pas d'interstitiel ici : on ne coupe pas l'affichage des résultats.
      // La pub plein écran est réservée aux ouvertures de fiche.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader(
            eyebrow: 'Mutation 2025 · 27 écoles',
            title: 'Trouvez vos écoles par licence',
            bottom: FutureBuilder<_ScoreEData>(
              future: _future,
              builder: (context, snap) {
                final ready = snap.hasData;
                return _LicenceField(
                  selected: _selected,
                  enabled: ready,
                  onTap: !ready ? null : () => _pickLicence(snap.data!.licences),
                  onClear: _selected == null
                      ? null
                      : () {
                          setState(() => _selected = null);
                          LicenceStore.clear(); // retire aussi la licence de l'accueil
                        },
                );
              },
            ),
          ),
          // Pas de SafeArea : les listes vont jusqu'en bas de l'écran et leur
          // padding bas (hauteur de la navbar incluse grâce à extendBody)
          // évite que le contenu soit caché par la barre.
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    return FutureBuilder<_ScoreEData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _refreshable(_error(snap.error.toString()));

        final ecoles = snap.data!.ecoles;

        // Aucune licence choisie → écran d'accueil + bouton.
        if (_selected == null) {
          return _refreshable(_prompt(snap.data!.licences));
        }

        // Garde-fou : si le dataset `data` ne contient AUCUN license_ids,
        // c'est qu'il n'a pas été mis à jour (version sans *.with_ids).
        final bool hasAnyIds = ecoles.any((ec) =>
            ((ec['filieres'] as List?) ?? []).any((f) => f is Map &&
                f.keys.any((k) => k.toString().startsWith('license_ids'))));
        if (!hasAnyIds) {
          return _refreshable(_notice(
            icon: Icons.sync_problem,
            title: 'Données pas à jour',
            body:
                'Le dataset « data » ne contient pas encore les codes de licence '
                '(license_ids). Charge la version data.with_ids.json dans la clé KV, '
                'puis tire pour rafraîchir.',
          ));
        }

        final lid = (_selected!['license_id'] ?? '').toString();
        final eligibles = <_EcoleMatch>[];
        for (final ec in ecoles) {
          final fils = _eligibleFilieres(ec, lid);
          if (fils.isNotEmpty) eligibles.add(_EcoleMatch(ec, fils));
        }

        if (eligibles.isEmpty) {
          return _refreshable(_notice(
            icon: Icons.search_off,
            title: 'Aucune école',
            body: 'Aucune école n\'accepte cette licence dans ce dataset.',
          ));
        }

        final n = eligibles.length;
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.blue,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                16, 14, 16, 24 + MediaQuery.paddingOf(context).bottom),
            children: [
              // Compteur : « 12 écoles acceptent votre licence ».
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 10),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '$n école${n > 1 ? 's' : ''}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.blue),
                    ),
                    TextSpan(
                        text: ' accepte${n > 1 ? 'nt' : ''} votre licence'),
                  ]),
                  style: const TextStyle(fontSize: 13, color: AppColors.gray),
                ),
              ),
              ..._buildFeed(eligibles),
            ],
          ),
        );
      },
    );
  }

  /// Construit la liste défilante : cartes écoles + un natif in-feed tous les
  /// [_kAdEvery] résultats (jamais en 1re position, jamais en dernier, jamais
  /// deux collés), plafonné à [_kMaxAds]. Chaque natif reçoit un numéro de slot
  /// stable, et on PRÉCHARGE d'avance le nombre exact de slots présents.
  List<Widget> _buildFeed(List<_EcoleMatch> eligibles) {
    final children = <Widget>[];
    int adSlot = 0;

    for (int i = 0; i < eligibles.length; i++) {
      if (i > 0) children.add(const SizedBox(height: 14));
      children.add(_EcoleCard(match: eligibles[i]));

      final bool finDeBloc = (i + 1) % _kAdEvery == 0;
      final bool resteApres = i < eligibles.length - 1;
      if (finDeBloc && resteApres && adSlot < _kMaxAds) {
        children.add(_InFeedNativeAd(manager: _adManager, slotIndex: adSlot));
        adSlot++;
      }
    }

    // Précharge exactement le nombre de slots réellement affichés (idempotent :
    // les annonces déjà chargées/en cours ne sont pas rechargées).
    _adManager.preload(adSlot);
    return children;
  }

  /// Rend n'importe quel contenu "tirable pour rafraîchir", même s'il ne
  /// remplit pas l'écran (invite, messages vides), en le forçant scrollable.
  /// Le contenu est centré dans la zone VISIBLE (au-dessus de la navbar).
  Widget _refreshable(Widget child) {
    final double bottom = MediaQuery.paddingOf(context).bottom;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.blue,
      child: LayoutBuilder(
        builder: (ctx, c) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: c.maxHeight,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottom),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Écran d'accueil sans licence : icône, message, bouton.
  Widget _prompt(List<Map<String, dynamic>> licences) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: _kAvatarBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.travel_explore_rounded,
                  size: 36, color: AppColors.blue),
            ),
            const SizedBox(height: 16),
            const Text('Choisissez votre licence',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            const SizedBox(height: 6),
            const Text(
              'On affiche uniquement les écoles où vous pouvez postuler.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.gray),
            ),
            const SizedBox(height: 18),
            Material(
              color: AppColors.blue,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _pickLicence(licences),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_rounded, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Choisir ma licence',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notice(
      {required IconData icon, required String title, required String body}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: _kSoftBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: _kMuted),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, height: 1.5, color: AppColors.gray)),
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
              Text('Chargement impossible',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 8),
              Text(err,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, height: 1.5, color: AppColors.gray)),
            ],
          ),
        ),
      ),
    );
  }

  /// Feuille modale : recherche + liste des licences (RTL).
  Future<Map<String, dynamic>?> _openPicker(
      List<Map<String, dynamic>> licences) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LicencePicker(licences: licences),
    );
  }

  // ---- logique de filtrage ----

  /// Tous les codes license_ids* d'une filière (annee1, annee1_a, options…).
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

  List<Map<String, dynamic>> _eligibleFilieres(Map ecole, String lid) {
    final fs =
        ((ecole['filieres'] as List?) ?? []).cast<Map<String, dynamic>>();
    return fs.where((f) => _filiereAccepts(f, lid)).toList();
  }
}

class _ScoreEData {
  _ScoreEData({required this.ecoles, required this.licences});
  final List<Map<String, dynamic>> ecoles;
  final List<Map<String, dynamic>> licences;
}

class _EcoleMatch {
  _EcoleMatch(this.ecole, this.filieres);
  final Map<String, dynamic> ecole;
  final List<Map<String, dynamic>> filieres;
}

// ─────────────────────────────────────────────────────────────────────────
//  NATIF IN-FEED — carte personnalisée, préchargée & mise en cache
// ─────────────────────────────────────────────────────────────────────────

/// Affiche l'annonce native du slot [slotIndex] fournie par [manager].
///
/// • La mise en page est 100 % maison (Android : ecole_native_ad.xml +
///   EcoleNativeAdFactory.kt).
/// • L'annonce est PRÉCHARGÉE et MISE EN CACHE par le manager : elle n'est ni
///   rechargée ni détruite quand on scrolle (wantKeepAlive) → elle reste en
///   place et réapparaît instantanément.
/// • Tant que l'annonce n'est pas prête, la carte n'occupe aucune place
///   (l'espacement est inclus ici pour ne pas laisser de trou).
///
/// NB iOS : sans factory iOS enregistrée, ce natif ne s'affiche pas (pas de
/// crash) tant qu'on n'a pas fait l'équivalent Swift.
class _InFeedNativeAd extends StatefulWidget {
  const _InFeedNativeAd({required this.manager, required this.slotIndex});

  final NativeAdManager manager;
  final int slotIndex;

  @override
  State<_InFeedNativeAd> createState() => _InFeedNativeAdState();
}

class _InFeedNativeAdState extends State<_InFeedNativeAd>
    with AutomaticKeepAliveClientMixin {
  // Empêche la destruction de la carte quand elle sort de l'écran au scroll.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // requis par AutomaticKeepAliveClientMixin

    return ValueListenableBuilder<NativeAd?>(
      valueListenable: widget.manager.slot(widget.slotIndex),
      builder: (context, ad, _) {
        if (ad == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: _kNativeAdHeight,
              width: double.infinity,
              child: AdWidget(ad: ad),
            ),
          ),
        );
      },
    );
  }
}

/// Champ affiché dans le header : licence choisie ou invite.
class _LicenceField extends StatelessWidget {
  const _LicenceField({
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onClear,
  });

  final Map<String, dynamic>? selected;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final label = selected == null
        ? 'اختر إجازتك…'
        : (selected!['ar'] ?? selected!['fr'] ?? '').toString();
    final isPlaceholder = selected == null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.school_outlined,
                  size: 19,
                  color: enabled ? AppColors.blue : AppColors.graySoft),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  enabled ? label : 'Chargement…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: isPlaceholder ? const Color(0xFFA6ACC4) : AppColors.ink,
                    fontWeight:
                        isPlaceholder ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 18, color: _kMuted),
                  ),
                )
              else
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: _kMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feuille modale de sélection avec recherche.
class _LicencePicker extends StatefulWidget {
  const _LicencePicker({required this.licences});
  final List<Map<String, dynamic>> licences;
  @override
  State<_LicencePicker> createState() => _LicencePickerState();
}

class _LicencePickerState extends State<_LicencePicker> {
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
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE2E4EE),
                  borderRadius: BorderRadius.circular(4)),
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
                  fillColor: _kSoftBg,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
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
                      child: Text('Aucune licence',
                          style: TextStyle(color: AppColors.gray)))
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                          8, 0, 8, 24 + MediaQuery.paddingOf(context).bottom),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFF0F1F6)),
                      itemBuilder: (_, i) {
                        final l = items[i];
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(l),
                          title: Text(
                            (l['ar'] ?? '').toString(),
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink),
                          ),
                          subtitle: (l['fr'] ?? '').toString().isEmpty
                              ? null
                              : Text((l['fr']).toString(),
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.gray)),
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

/// Carte école « minimale » : pastille sigle · nom · code · bouton ›,
/// puis les filières éligibles en étiquettes douces (4 max + « +N »).
class _EcoleCard extends StatelessWidget {
  const _EcoleCard({required this.match});
  final _EcoleMatch match;

  String _filiereName(Map f) {
    for (final k in const [
      'nom',
      'nom_annee1_a',
      'nom_annee1_b',
      'nom_annee1',
      'nom_annee1_a_option1',
    ]) {
      final v = f[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return (f['code'] ?? f['code_annee1'] ?? '').toString();
  }

  /// Texte de la pastille : le sigle, sinon les initiales du nom.
  String _avatarText(String sigle, String nom) {
    if (sigle.trim().isNotEmpty) return sigle.trim();
    final words = nom.split(RegExp(r"[\s'’-]+")).where((w) => w.length > 2);
    final initials = words.take(4).map((w) => w[0].toUpperCase()).join();
    return initials.isEmpty ? '?' : initials;
  }

  @override
  Widget build(BuildContext context) {
    final ecole = match.ecole;
    final id = (ecole['id'] ?? '').toString();
    final nom = (ecole['nom'] ?? ecole['sigle'] ?? '').toString();
    final sigle = (ecole['sigle'] ?? '').toString();
    final ville = (ecole['ville'] ?? ecole['gouvernorat'] ?? '').toString();
    final noms = match.filieres.map(_filiereName).toList();
    final apercu = noms.take(_kChipsPreview).toList();
    final reste = noms.length - apercu.length;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        // Ouvrir une fiche = 1 ouverture comptée AU RETOUR (jamais pendant la
        // navigation). La pub plein écran s'affiche toutes les 3 ouvertures de
        // fiche (compteur dédié dans ad_service.dart), avec le cooldown de 60 s.
        // C'est le SEUL déclencheur d'interstitiel gardé (le moins gênant).
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => EcoleDetailScreen(ecoleId: id)))
            .then((_) => InterstitialAdService.registerEcoleOpen()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Ligne du haut : pastille · nom/code · bouton › ──
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kAvatarBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    // FittedBox : les sigles longs (ENET'Com…) rétrécissent.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _avatarText(sigle, nom),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .2,
                          color: AppColors.blue,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nom complet sur 2 lignes (plus de noms coupés).
                        Text(
                          nom,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16.5,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ville.isEmpty ? id : '$id · $ville',
                          style: const TextStyle(fontSize: 13, color: _kMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: _kSoftBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chevron_right_rounded,
                        size: 24, color: AppColors.blue),
                  ),
                ],
              ),

              // ── Séparateur ──
              const Padding(
                padding: EdgeInsets.only(top: 14, bottom: 12),
                child: Divider(height: 1, thickness: 1, color: _kLine),
              ),

              // ── Filières ouvertes ──
              Row(children: [
                Container(
                  width: 3,
                  height: 13,
                  decoration: BoxDecoration(
                    color: AppColors.blue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('Filières ouvertes à votre licence',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _kMuted)),
              ]),
              const SizedBox(height: 10),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final n in apercu) _FiliereChip(n),
                    if (reste > 0) _MoreChip(reste),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Étiquette de filière (style minimal, fond gris-bleu doux).
class _FiliereChip extends StatelessWidget {
  const _FiliereChip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _kSoftBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500, color: _kChipText)),
    );
  }
}

/// « +N » : filières supplémentaires (visibles dans la fiche).
class _MoreChip extends StatelessWidget {
  const _MoreChip(this.count);
  final int count;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE3FF)),
      ),
      child: Text('+$count',
          textDirection: TextDirection.ltr,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.blue)),
    );
  }
}

/// Ancienne étiquette, gardée publique au cas où un autre écran l'utilise.
class LicenceChip extends StatelessWidget {
  const LicenceChip(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.violetTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDFE4F6)),
      ),
      child: Text(text,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF2F3A72))),
    );
  }
}