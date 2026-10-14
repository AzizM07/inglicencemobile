// home_screen.dart — version finale avec monetisation AdMob
//
// PREREQUIS (a faire une seule fois, hors de ce fichier) :
//   1) pubspec.yaml    ->  google_mobile_ads: ^5.3.1
//                          shared_preferences: ^2.2.3
//                          + déclarer  assets/images/        (logo)
//                          + déclarer  assets/images/cards/  (photos des blocs)
//   2) main.dart       ->  WidgetsFlutterBinding.ensureInitialized();
//                          await ScoreAStore.init();            // <-- recharge le Score A
//                          await LicenceStore.init();           // <-- recharge la Licence
//                          await MobileAds.instance.initialize();
//                          await MobileAds.instance.updateRequestConfiguration(
//                            RequestConfiguration(
//                              maxAdContentRating: MaxAdContentRating.g,
//                            ),
//                          );
//   3) AndroidManifest.xml + Info.plist  ->  ton App ID AdMob.
//
// PHOTOS DES BLOCS (assets/images/cards/) — format paysage, ~600x400, WebP/JPG
// < 60 Ko chacune :
//   score_a.jpg   score_e.jpg   admis.jpg   ecoles.jpg   chance.jpg   concours.jpg
// Si une photo manque, le bloc affiche un fond bleu clair + l'icône (aucun crash).
//
// IDs DES PUBS : tous centralisés dans AdIds (services/ad_service.dart).
// Ce fichier utilise AdIds.banner et AdIds.rewarded.
// (Si AdIds.banner n'existe pas encore, ajoute-le — ID de test Google :
//  'ca-app-pub-3940256099942544/6300978111'.)
//
// BANNIERE DU HAUT (style Sofascore) : à la place du titre « Tout pour
// réussir votre mutation ». Bannière 320x50 centrée sous le header. Elle ne
// prend AUCUNE place tant qu'elle charge ou si elle échoue ; quand elle est
// chargée, elle apparaît et la grille se redimensionne automatiquement.
//
// HEADER : compact et très arrondi, sa hauteur s'adapte exactement à son
// contenu. Espace réduit au-dessus du titre (topPadding 4). Ligne 1 : logo + titre « Calculez votre score » (centrés).
// Ligne 2 : deux colonnes côte à côte — à GAUCHE « Votre Score A : » + le
// score en grand ; à DROITE « Licence : » + la licence (récupérée
// automatiquement depuis l'écran Score E via LicenceStore, réactif +
// persistant). Tant qu'aucun score NI licence n'existe, on affiche le
// sous-titre à la place.
//
// FIX RESPONSIVE : le contenu du header (logo, titre, score) est mis à
// l'échelle (`scale`) selon la hauteur réelle de l'écran, avec clamp.
//
// CONFETTIS : rejoués automatiquement toutes les 5 s tant qu'un Score A existe
// (widget _HeaderConfetti : l'asset Lottie est chargé une seule fois, la
// lecture est pilotée par un AnimationController relancé sur un Timer.periodic).
//
// PAGE SANS SCROLL : header + bannière + grille, rien d'autre. La grille
// remplit toute la hauteur restante (3 lignes égales ; photo ≈ 76 %, texte
// ≈ 24 %). Photo et titre sont
// dimensionnés selon l'espace réel -> compatible tous écrans (petits
// téléphones, grands écrans, tablettes ; scroll de secours si trop court).
//
// GRILLE FONCTIONNALITES (style « Bleu + Corail ») : 2 blocs par ligne.
// Badges : petits « Étape 1 / Étape 2 » corail sur Score A / Score E,
// badges normaux sur « Voir ma chance » et « Concours » ; aucun sur Les admis /
// Les écoles. L'icône est centrée dans la zone libre (jamais sous un badge).
// Chaque bloc = photo en haut (+ badge éventuel), un ARC blanc
// qui remplace le trait droit entre photo et texte, puis le titre seul,
// centré, dont la taille s'adapte à la largeur. Pas de flèche ni de CTA
// texte : toute la carte est cliquable.
// Blocs : Score A / Score E / Les admis / Les écoles / Voir ma chance
// (récompensée, l'état de la pub est dans le badge) / Concours indépendant
// (photo N&B). Plus de native ad sous la grille.
//
// INTERSTITIEL : « Les admis » et « Les écoles » comptent comme UNE action
// chacune, au retour de l'écran (InterstitialAdService.registerAction).
// La pub s'affiche toutes les 4 actions (voir ad_service.dart).

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:lottie/lottie.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_header.dart';
import '../services/ad_service.dart';
import '../services/score_a_store.dart';
import '../services/licence_store.dart';
import 'admis_screen.dart';
import 'ecoles_screen.dart';
import 'chance_screen.dart';

/// Chemins des photos des blocs.
class _CardPhotos {
  static const scoreA = 'assets/images/cards/score_a.jpg';
  static const scoreE = 'assets/images/cards/score_e.jpg';
  static const admis = 'assets/images/cards/admis.jpg';
  static const ecoles = 'assets/images/cards/ecoles.jpg';
  static const chance = 'assets/images/cards/chance.jpg';
  static const concours = 'assets/images/cards/concours.jpg';
}

/// Dimensions communes des blocs photo.
const double _kTileRadius = 18;
const double _kPhotoHeight = 100; // valeur par défaut (sinon calculée)
const double _kArcHeight = 18; // hauteur de l'arc entre photo et titre
const double _kPhotoRatio = 0.76; // part du bloc occupée par la photo (0.6 = plus de texte)

class HomeScreen extends StatelessWidget {
  /// [onNavigate] : 1 = Score A, 2 = Score E (index des onglets du RootShell)
  const HomeScreen({super.key, required this.onNavigate});

  final void Function(int tabIndex) onNavigate;

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Column(
        children: [
          _header(context),
          // ▼ BANNIERE AD (style Sofascore) au-dessus des blocs. Elle ne prend
          // AUCUNE place tant qu'elle n'est pas chargée (ou si elle échoue) :
          // la grille occupe alors tout l'espace, puis se resserre toute seule
          // quand la pub arrive.
          const _TopBannerAd(),
          // ▼ GRILLE PLEIN ÉCRAN — pas de scroll, rien en dessous.
          // Les 3 lignes se partagent la hauteur restante (entre bannière et
          // navbar). Tailles de photo et de titre calculées depuis l'espace
          // RÉEL du bloc -> s'adapte à tous les écrans :
          //  • petits téléphones : tout est réduit proportionnellement ;
          //  • écrans trop courts (paysage, très petits) : lignes de hauteur
          //    minimale + scroll de secours, rien n'est écrasé ;
          //  • tablettes : grille centrée, largeur max 620.
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
              child: LayoutBuilder(
                builder: (context, box) {
                  const double gap = 11, minRowH = 112, maxW = 620;
                  final double gridW = box.maxWidth.clamp(0.0, maxW);
                  final double fitRowH = (box.maxHeight - 2 * gap) / 3;
                  final bool scroll = fitRowH < minRowH;
                  final double rowH = scroll ? minRowH : fitRowH;

                  // Photo ≈ 76 % du bloc -> zone texte ≈ 24 % (moins de vide,
                  // l'arc descend plus bas). Réglable via _kPhotoRatio.
                  final double photoH =
                      (rowH * _kPhotoRatio).clamp(60.0, 200.0);
                  final double tileW = (gridW - gap) / 2;
                  final double textAreaH = rowH - photoH - 6;
                  // Taille du titre : limitée par la largeur ET par la hauteur
                  // d'UNE ligne (les titres longs passent sur 2 lignes et
                  // sont réduits automatiquement par le FittedBox du bloc).
                  final double titleSize = math.min(
                    (tileW - 16) / 8.2,
                    textAreaH / 1.25,
                  ).clamp(12.0, 24.0);

                  final grid = _GridMetrics(
                    photoHeight: photoH,
                    titleSize: titleSize,
                    child: _featureGrid(context, scroll ? rowH : null),
                  );

                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: gridW,
                      child: scroll
                          ? SingleChildScrollView(child: grid)
                          : grid,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── GRILLE DES FONCTIONNALITES (2 blocs photo par ligne) ─────────────────
  /// [fixedRowH] null = les 3 lignes se partagent la hauteur (Expanded) ;
  /// sinon hauteur fixe (mode scroll de secours pour les écrans courts).
  Widget _featureGrid(BuildContext context, double? fixedRowH) {
    Widget row(Widget child) => fixedRowH == null
        ? Expanded(child: child)
        : SizedBox(height: fixedRowH, child: child);

    return Column(
      mainAxisSize: fixedRowH == null ? MainAxisSize.max : MainAxisSize.min,
      children: [
        row(_gridRow(
          _PhotoTile(
            photo: _CardPhotos.scoreA,
            fallbackIcon: Icons.calculate_rounded,
            // Badge discret, couleur corail (comme Étape 2).
            badge: 'Étape 1',
            badgeSmall: true,
            title: 'Score A',
            onTap: () => onNavigate(1),
          ),
          _PhotoTile(
            photo: _CardPhotos.scoreE,
            fallbackIcon: Icons.functions,
            badge: 'Étape 2',
            badgeSmall: true,
            title: 'Score E',
            onTap: () => onNavigate(2),
          ),
        )),
        const SizedBox(height: 11),
        row(_gridRow(
          _PhotoTile(
            photo: _CardPhotos.admis,
            fallbackIcon: Icons.groups_rounded,
            title: 'Les admis', // pas de badge
            // Action comptée au RETOUR de l'écran : la pub n'apparaît jamais
            // pendant la navigation.
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AdmisScreen()))
                .then((_) => InterstitialAdService.registerAction()),
          ),
          _PhotoTile(
            photo: _CardPhotos.ecoles,
            fallbackIcon: Icons.account_balance_rounded,
            title: 'Les écoles', // pas de badge
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const EcolesScreen()))
                .then((_) => InterstitialAdService.registerAction()),
          ),
        )),
        const SizedBox(height: 11),
        row(_gridRow(
          // ▼ Carte récompensée (rewarded) — débloque via une courte vidéo.
          const _RewardedTile(),
          const _SoonTile(
            photo: _CardPhotos.concours,
            fallbackIcon: Icons.emoji_events_rounded,
            title: 'Concours',
            subtitle: 'indépendant',
          ),
        )),
      ],
    );
  }

  /// Une ligne = deux cases côte à côte ; sa hauteur vient de l'Expanded
  /// de la grille (les 3 lignes se partagent l'écran).
  Widget _gridRow(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: left),
        const SizedBox(width: 11),
        Expanded(child: right),
      ],
    );
  }

  // ── HEADER : logo + titre / Score A (gauche) · Licence (droite) ──────────
  Widget _header(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Échelle basée sur la hauteur d'écran (812 = iPhone standard).
    final double refHeight = mq.orientation == Orientation.landscape ? 400 : 812;
    final double scale = (mq.size.height / refHeight).clamp(0.62, 1.0);

    return ValueListenableBuilder<ScoreASnapshot?>(
      valueListenable: ScoreAStore.current,
      builder: (context, snap, _) {
        final double? scoreA = snap?.total;
        final header = AppHeader(
          // 0 / 0 = aucune hauteur minimale : le header épouse son contenu.
          heightFactor: 0,
          minHeight: 0,
          radius: 40, // très arrondi (24 par défaut)
          topPadding: 4, // juste sous la barre de statut (était 22)
          bottomPadding: 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Ligne 1 : logo + titre, centrés.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo2.png',
                    height: 30 * scale,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                  SizedBox(width: 10 * scale),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Calculez votre score',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24 * scale,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12 * scale),
              // Ligne 2 : deux colonnes (Score A à gauche, Licence à droite),
              // OU le sous-titre tant qu'aucune des deux valeurs n'existe.
              // On écoute la licence en plus du score : le header se met à jour
              // tout seul dès qu'une licence est choisie sur l'écran Score E.
              ValueListenableBuilder<LicenceSnapshot?>(
                valueListenable: LicenceStore.current,
                builder: (context, lic, __) {
                  if (scoreA == null && lic == null) {
                    return _heroSubtitle(scale);
                  }
                  return _heroRow(scoreA, lic, scale);
                },
              ),
            ],
          ),
        );

        // Confettis rejoués automatiquement toutes les 5 s tant qu'un Score A
        // existe. IgnorePointer (dans _HeaderConfetti) : ne bloque aucun toucher.
        return Stack(
          children: [
            header,
            if (scoreA != null) _HeaderConfetti(scoreA: scoreA),
          ],
        );
      },
    );
  }

  /// Deux colonnes du header :
  ///  • GAUCHE  : « Votre Score A : » + le score en grand (l'un au-dessus
  ///              de l'autre) ;
  ///  • DROITE  : « Licence : » + la licence (RTL), sur 2 lignes max.
  /// Un fin séparateur vertical sépare les deux.
  Widget _heroRow(double? scoreA, LicenceSnapshot? lic, double scale) {
    final String licLabel =
        (lic != null && lic.label.isNotEmpty) ? lic.label : 'Non choisie';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Score A (gauche) ──
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Votre Score A :',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 5 * scale),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  scoreA != null ? _fmt(scoreA) : '—',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32 * scale,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.5,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Séparateur vertical ──
        Container(
          width: 1,
          height: 44 * scale,
          margin: EdgeInsets.symmetric(horizontal: 12 * scale),
          color: Colors.white.withOpacity(0.28),
        ),

        // ── Licence (droite) ──
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Licence :',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 7 * scale),
              Text(
                licLabel,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: (lic != null && lic.label.isNotEmpty)
                      ? Colors.white
                      : Colors.white70,
                  fontSize: 16 * scale,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Sous-titre (affiché tant qu'aucun score NI licence n'est renseigné).
  Widget _heroSubtitle(double scale) {
    return Text(
      'Score A, Score E et les 27 écoles d\'ingénieurs à votre portée.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: 14.5 * scale,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// Formate un nombre à la française (156.4 -> "156,40").
  static String _fmt(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
}

// ─────────────────────────────────────────────────────────────────────────
//  CONFETTIS DU HEADER (rejoués en boucle toutes les 5 s)
// ─────────────────────────────────────────────────────────────────────────

/// Confettis rejoués en boucle toutes les 5 secondes tant qu'un Score A existe.
/// L'asset Lottie est chargé UNE seule fois : on pilote la lecture via un
/// AnimationController relancé par un Timer.periodic (pas de re-montage du
/// widget, donc pas de flash). Timer et controller sont libérés au dispose.
class _HeaderConfetti extends StatefulWidget {
  const _HeaderConfetti({required this.scoreA});

  final double scoreA;

  @override
  State<_HeaderConfetti> createState() => _HeaderConfettiState();
}

class _HeaderConfettiState extends State<_HeaderConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  static const Duration _interval = Duration(seconds: 5); // ← rythme

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _timer = Timer.periodic(_interval, (_) => _play());
  }

  /// Relance l'animation depuis le début.
  void _play() {
    if (!mounted) return;
    _controller
      ..reset()
      ..forward();
  }

  @override
  void didUpdateWidget(covariant _HeaderConfetti old) {
    super.didUpdateWidget(old);
    // Nouveau score calculé -> relance immédiate (sans attendre le prochain tick).
    if (old.scoreA != widget.scoreA) _play();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRRect(
          // Suit les coins arrondis du header (radius: 40).
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(40)),
          child: Lottie.asset(
            'assets/lottie/confetti.json',
            controller: _controller,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            onLoaded: (composition) {
              // Cale la durée du controller sur celle de l'animation,
              // puis joue une première fois immédiatement.
              _controller.duration = composition.duration;
              _controller.forward();
            },
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  BRIQUES DU STYLE « PHOTO + BADGE FLOTTANT »
// ─────────────────────────────────────────────────────────────────────────

/// Transmet aux blocs les tailles calculées selon l'espace réel de l'écran.
class _GridMetrics extends InheritedWidget {
  const _GridMetrics({
    required this.photoHeight,
    required this.titleSize,
    required super.child,
  });

  final double photoHeight;
  final double titleSize;

  static _GridMetrics? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GridMetrics>();

  static double photoOf(BuildContext context) =>
      _of(context)?.photoHeight ?? _kPhotoHeight;

  static double titleOf(BuildContext context) =>
      _of(context)?.titleSize ?? 18;

  @override
  bool updateShouldNotify(_GridMetrics old) =>
      old.photoHeight != photoHeight || old.titleSize != titleSize;
}

/// Matrice niveaux de gris (pour les blocs « Bientôt »).
const ColorFilter _kGrayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// Couleur d'accent qui accompagne le bleu (palette « Bleu + Corail »).
const Color _kCoral = Color(0xFFFF6B5B);

/// Couleur des éléments « Bientôt » (grisés).
const Color _kMuted = Color(0xFF8A90A8);

/// Coque commune d'un bloc photo :
///  • photo en haut + badge coloré flottant (bleu ou corail) ;
///  • ARC blanc qui mord dans le bas de la photo (au lieu d'un trait droit) ;
///  • titre seul, centré, dont la taille s'adapte à la largeur du bloc.
/// Pas de flèche ni de « Voir / Explorer » : toute la carte est cliquable.
class _PhotoCardShell extends StatelessWidget {
  const _PhotoCardShell({
    required this.photo,
    required this.fallbackIcon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.badgeColor = _kCoral,
    this.badgeSmall = false,
    this.badgeLeading,
    this.badgeTrailing,
    this.dimmed = false,
  });

  final String photo;
  final IconData fallbackIcon;
  final String title;
  final String? subtitle; // petite ligne sous le titre (ex. « indépendant »)
  final VoidCallback onTap;
  final String? badge; // null = pas de badge
  final Color badgeColor;
  final bool badgeSmall; // badge discret (Étape 1 / Étape 2)
  final IconData? badgeLeading;
  final Widget? badgeTrailing; // ex. petit indicateur de chargement
  final bool dimmed; // bloc « Bientôt » : gris, mais lisible

  // Couleurs du bloc « Bientôt » (option A : sobre mais lisible).
  static const Color _dimBg = Color(0xFFECECEC);
  static const Color _dimIcon = Color(0xFF9AA0B4);
  static const Color _dimTitle = Color(0xFF4A5070);
  static const Color _dimSub = Color(0xFF6B7194);

  @override
  Widget build(BuildContext context) {
    final double photoH = _GridMetrics.photoOf(context);
    final double titleSize = _GridMetrics.titleOf(context);

    // Zone LIBRE pour l'icône : sous le badge et au-dessus de l'arc, pour
    // qu'aucun badge ne la cache. L'icône y est centrée et dimensionnée.
    final double topReserve =
        badge == null ? 6 : (badgeSmall ? 26 : 34);
    final double freeH = photoH - topReserve - _kArcHeight;
    final double iconSize = (freeH * 0.62).clamp(22.0, 52.0);

    Widget image = Image.asset(
      photo,
      height: photoH,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        height: photoH,
        color: dimmed ? _dimBg : const Color(0xFFDBE3FB),
        padding: EdgeInsets.only(top: topReserve, bottom: _kArcHeight),
        alignment: Alignment.center,
        child: Icon(
          fallbackIcon,
          size: iconSize,
          color: dimmed ? _dimIcon : AppColors.blue,
        ),
      ),
    );
    if (dimmed) {
      // Vraies photos : noir & blanc légèrement atténué.
      image = Opacity(
          opacity: 0.85,
          child: ColorFiltered(colorFilter: _kGrayscale, child: image));
    }

    // Titre (+ sous-titre éventuel), réduit si besoin pour tenir dans la zone.
    final Color titleColor = dimmed ? _dimTitle : AppColors.ink;
    final Widget titleBlock = subtitle == null
        ? Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.15,
              color: titleColor,
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.05,
                  color: titleColor,
                ),
              ),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: (titleSize * 0.58).clamp(10.0, 13.0),
                  fontWeight: FontWeight.w600,
                  height: 1.05,
                  color: dimmed ? _dimSub : AppColors.gray,
                ),
              ),
            ],
          );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_kTileRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kTileRadius),
            border: Border.all(color: const Color(0xFFE3E8FB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Photo (ou icône centrée) + badge + arc ──
              SizedBox(
                height: photoH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    image,
                    if (badge != null)
                      Positioned(
                        top: badgeSmall ? 7 : 8,
                        left: badgeSmall ? 7 : 8,
                        right: 8,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _PhotoBadge(
                            label: badge!,
                            color: badgeColor,
                            small: badgeSmall,
                            leading: badgeLeading,
                            trailing: badgeTrailing,
                            muted: dimmed,
                          ),
                        ),
                      ),
                    // Arc blanc : le bas de la carte « remonte » en courbe
                    // dans la photo. -1 évite une ligne de pixel visible.
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: -1,
                      height: _kArcHeight + 1,
                      child: CustomPaint(painter: _ArcPainter(Colors.white)),
                    ),
                  ],
                ),
              ),
              // ── Titre centré, taille calculée par la grille ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: titleBlock,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Peint un arc convexe (sommet au centre) qui recouvre le bas de la photo.
class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Bézier quadratique : point de contrôle à -h -> le sommet touche y = 0.
    final path = Path()
      ..moveTo(0, h)
      ..quadraticBezierTo(w / 2, -h, w, h)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter old) => old.color != color;
}

/// Badge coloré posé sur la photo (« Étape 1 », « 27 écoles », « Ad »…).
class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge({
    required this.label,
    required this.color,
    this.small = false,
    this.leading,
    this.trailing,
    this.muted = false,
  });

  final String label;
  final Color color;
  final bool small; // version discrète (Étape 1 / Étape 2)
  final IconData? leading;
  final Widget? trailing;
  final bool muted; // badge blanc + texte gris (blocs « Bientôt »)

  @override
  Widget build(BuildContext context) {
    final Color bg = muted ? Colors.white : color;
    final Color fg = muted ? const Color(0xFF6B7194) : Colors.white;
    final double fs = small ? 9.5 : 11;
    return Container(
      padding: small
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            Icon(leading, size: fs + 1, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 5),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Bloc photo standard (Score A, Score E, Les admis, Les écoles).
/// [badge] null = aucun badge.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.fallbackIcon,
    required this.title,
    required this.onTap,
    this.badge,
    this.badgeColor = _kCoral,
    this.badgeSmall = false,
  });

  final String photo;
  final IconData fallbackIcon;
  final String title;
  final String? badge;
  final Color badgeColor;
  final bool badgeSmall;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PhotoCardShell(
      photo: photo,
      fallbackIcon: fallbackIcon,
      badge: badge,
      badgeColor: badgeColor,
      badgeSmall: badgeSmall,
      title: title,
      onTap: onTap,
    );
  }
}

/// Bloc « verrouillé » : fonctionnalité pas encore dispo. Photo en N&B +
/// badge « Bientôt » ; au tap, un popup « prochainement » (pas de navigation).
class _SoonTile extends StatelessWidget {
  const _SoonTile({
    required this.photo,
    required this.fallbackIcon,
    required this.title,
    this.subtitle,
  });

  final String photo;
  final IconData fallbackIcon;
  final String title;
  final String? subtitle;

  String get _fullName => subtitle == null ? title : '$title $subtitle';

  void _showSoon(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FD),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.lock_rounded, size: 26, color: AppColors.blue),
              ),
              const SizedBox(height: 16),
              Text(_fullName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 8),
              const Text('Cette fonctionnalité arrive prochainement.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.gray)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    backgroundColor: kBleuRoi,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999)),
                  ),
                  child: const Text('Compris',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PhotoCardShell(
      photo: photo,
      fallbackIcon: fallbackIcon,
      badge: 'Bientôt',
      badgeColor: _kMuted,
      badgeLeading: Icons.lock_outline_rounded,
      title: title,
      subtitle: subtitle,
      dimmed: true,
      onTap: () => _showSoon(context),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  MONETISATION  (IDs : voir AdIds dans services/ad_service.dart)
// ─────────────────────────────────────────────────────────────────────────

/// « Voir ma chance » — tuile récompensée (le format le mieux payé).
/// Opt-in : l'utilisateur choisit de regarder une vidéo pour débloquer un
/// contenu. Aucune interruption. Précharge et recharge automatiquement.
/// Rendue au format bloc photo pour s'insérer dans la grille 2 colonnes.
/// Le bouton rond reflète l'état : play (prête), sablier (chargement),
/// rafraîchir (échec).
class _RewardedTile extends StatefulWidget {
  const _RewardedTile();

  @override
  State<_RewardedTile> createState() => _RewardedTileState();
}

class _RewardedTileState extends State<_RewardedTile> {
  RewardedAd? _ad;
  bool _loading = false;
  bool _failed = false; // dernier chargement échoué
  int _retries = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (_loading || _ad != null) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _retries = 0;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _ad = null;
              _load(); // précharge la prochaine
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _ad = null;
              _load();
            },
          );
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = ad;
            _failed = false;
          });
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          _ad = null;
          if (mounted) setState(() => _failed = true);
          // Réessaie quelques fois (échec réseau / pas de disponibilité au
          // démarrage). L'accès reste bloqué tant qu'aucune pub n'a été vue.
          if (_retries < _maxRetries) {
            _retries++;
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) _load();
            });
          }
        },
      ),
    );
  }

  void _openChance() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChanceScreen()),
    );
  }

  void _show() {
    final ad = _ad;
    if (ad == null) return;
    setState(() => _ad = null); // consommé ; onAdDismissed rechargera
    ad.show(onUserEarnedReward: (ad, reward) => _openChance());
  }

  void _onTap() {
    if (_ad != null) {
      _show(); // pub prête → vidéo → récompense → simulateur
      return;
    }
    // Pas de pub prête : on NE débloque PAS. On (re)lance le chargement et on
    // invite à réessayer. L'accès n'est possible qu'après avoir vu la vidéo.
    _load();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('La vidéo n\'est pas encore prête, réessaie dans un instant.')),
    );
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ad != null;
    // Plus de bouton rond : l'état de la pub est porté par le badge.
    final String badge =
        ready ? 'Ad · Vidéo' : (_failed ? 'Réessayer' : 'Chargement');
    final IconData badgeIcon = ready
        ? Icons.play_arrow_rounded
        : (_failed ? Icons.refresh_rounded : Icons.hourglass_empty_rounded);

    return _PhotoCardShell(
      photo: _CardPhotos.chance,
      fallbackIcon: Icons.lock_open_rounded,
      badge: badge,
      badgeColor: ready ? _kCoral : _kMuted,
      badgeLeading: badgeIcon,
      title: 'Voir ma chance',
      onTap: _onTap,
    );
  }
}

/// BANNIERE DU HAUT — format 320x50, centrée, façon Sofascore.
///  • pendant le chargement ET en cas d'échec : elle ne prend aucune place,
///    la page s'affiche comme s'il n'y avait pas de pub (aucun vide) ;
///  • une fois chargée : elle apparaît et la grille se resserre d'elle-même.
/// La bannière n'est ni rognée ni recouverte (règles AdMob : le logo
/// AdChoices dans le coin doit rester visible).
class _TopBannerAd extends StatefulWidget {
  const _TopBannerAd();

  @override
  State<_TopBannerAd> createState() => _TopBannerAdState();
}

class _TopBannerAdState extends State<_TopBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;

  static const AdSize _size = AdSize.banner; // 320 x 50

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: AdIds.banner,
      size: _size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          if (mounted) setState(() => _loaded = false);
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
    final bool show = _loaded && _ad != null;
    // AnimatedSize : quand la pub arrive, la grille se resserre en douceur
    // (250 ms) au lieu de sauter d'un coup.
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: show
          // Chargée : la bannière apparaît avec sa marge.
          ? Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: SizedBox(
                  width: _size.width.toDouble(),
                  height: _size.height.toDouble(),
                  child: AdWidget(ad: _ad!),
                ),
              ),
            )
          // Chargement en cours OU échec : AUCUNE place, aucun rectangle
          // gris -> la page est exactement comme sans pub.
          : const SizedBox(width: double.infinity, height: 0),
    );
  }
}