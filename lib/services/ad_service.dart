import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// ═══════════════════════════════════════════════════════════════════════
///  IDs AdMob — SEUL ENDROIT de toute l'app où se trouvent les IDs.
/// ═══════════════════════════════════════════════════════════════════════
///
/// Les écrans utilisent uniquement AdIds.banner / interstitial / native /
/// rewarded. La bascule se fait ici, même règle sur les deux plateformes :
///  • RELEASE (Play Store, TestFlight, App Store) → VRAIS IDs Ing-Licence ;
///  • DEBUG (flutter run, simulateur)             → IDs de TEST Google
///    (aucun risque de ban).
///
/// Où chaque ID est utilisé :
///  • banner       → bannière 320x50 en haut de l'accueil (home_screen.dart)
///  • interstitial → InterstitialAdService (ci-dessous)
///  • native       → pub native de l'écran « Les admis » (admis_screen.dart)
///  • rewarded     → bloc « Voir ma chance » de l'accueil
///
/// (AdMob → Applications → IngLicence Android / IngLicence iOS → Blocs d'annonces)
class AdIds {
  // ── VRAIS IDs Android (Ing-Licence) ──
  static const String _realBannerAndroid =
      'ca-app-pub-4805254666545297/4273642646';
  static const String _realInterstitialAndroid =
      'ca-app-pub-4805254666545297/2960560975';
  static const String _realNativeAndroid =
      'ca-app-pub-4805254666545297/3251460150';
  static const String _realRewardedAndroid =
      'ca-app-pub-4805254666545297/1955435211';

  // ── VRAIS IDs iOS (Ing-Licence) ──
  // ID d'application iOS (dans Info.plist) : ca-app-pub-4805254666545297~7466814012
  static const String _realBannerIos =
      'ca-app-pub-4805254666545297/6174088652';
  static const String _realInterstitialIos =
      'ca-app-pub-4805254666545297/2222226193';
  static const String _realNativeIos =
      'ca-app-pub-4805254666545297/5982516966';
  static const String _realRewardedIos =
      'ca-app-pub-4805254666545297/2924933771';

  // ── IDs de TEST officiels Google ──
  static const String _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _testNativeAndroid = 'ca-app-pub-3940256099942544/2247696110';
  static const String _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';
  static const String _testRewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  static String _pick({
    required String realAndroid,
    required String realIos,
    required String testAndroid,
    required String testIos,
  }) {
    final bool ios = Platform.isIOS;
    if (kReleaseMode) return ios ? realIos : realAndroid;
    return ios ? testIos : testAndroid;
  }

  static String get banner => _pick(
        realAndroid: _realBannerAndroid,
        realIos: _realBannerIos,
        testAndroid: _testBannerAndroid,
        testIos: _testBannerIos,
      );
  static String get interstitial => _pick(
        realAndroid: _realInterstitialAndroid,
        realIos: _realInterstitialIos,
        testAndroid: _testInterstitialAndroid,
        testIos: _testInterstitialIos,
      );
  static String get native => _pick(
        realAndroid: _realNativeAndroid,
        realIos: _realNativeIos,
        testAndroid: _testNativeAndroid,
        testIos: _testNativeIos,
      );
  static String get rewarded => _pick(
        realAndroid: _realRewardedAndroid,
        realIos: _realRewardedIos,
        testAndroid: _testRewardedAndroid,
        testIos: _testRewardedIos,
      );
}

// NB : l'ancienne bannière du bas (HomeBannerAd) a été supprimée — la
// bannière est désormais en haut de l'accueil (_TopBannerAd, home_screen.dart).

/// Service interstitiel avec DEUX déclencheurs indépendants, un même pool
/// d'annonce et un même cap de temps :
///
///  • [registerEcoleOpen] — déclencheur PRINCIPAL : une pub toutes les
///    [_everyEcole] ouvertures de fiche école (point de rupture naturel, peu
///    gênant). À appeler AU RETOUR d'une fiche.
///  • [registerAction] — actions générales (ex. « Calculer le Score A ») :
///    une pub toutes les [_every]. Rare, donc quasi silencieux.
///
/// Cap de temps [_cooldown] GLOBAL : jamais deux plein-écran à moins de 60 s,
/// quel que soit le compteur qui déclenche. C'est le vrai levier anti-agacement.
///
/// AVERTISSEMENT « Pub dans 3 » : avant chaque interstitiel, une pilule
/// navy avec compte à rebours (AdIncomingPill) s'affiche 3 s au-dessus de la
/// navbar, PUIS la pub s'ouvre. Elle n'apparaît QUE si la pub est déjà
/// chargée (jamais d'annonce d'une pub qui ne vient pas).
///
/// N'appelle JAMAIS ces méthodes dans les onChanged des champs de notes, ni
/// sur un simple changement d'onglet.
class InterstitialAdService {
  static InterstitialAd? _ad;
  static bool _loading = false;

  // Compteur "actions générales" (ex. clic sur « Calculer le Score A »).
  static int _actions = 0;
  static const int _every = 4;

  // Compteur DÉDIÉ aux ouvertures de fiche école (déclencheur principal).
  static int _ecoleOpens = 0;
  static const int _everyEcole = 3; // une pub toutes les 3 fiches ouvertes

  // Cap de temps global entre deux interstitiels.
  static const Duration _cooldown = Duration(seconds: 60);
  static DateTime? _lastShown;

  // true pendant le compte à rebours + la pub : évite un double déclenchement.
  static bool _showing = false;

  static void load() {
    if (_loading || _ad != null) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _ad = ad;
        },
        onAdFailedToLoad: (_) {
          _loading = false;
          _ad = null;
        },
      ),
    );
  }

  /// Ouverture de fiche école (à appeler AU RETOUR de la fiche).
  /// Affiche une pub toutes les [_everyEcole] ouvertures, si prête et si le
  /// cooldown est respecté.
  static void registerEcoleOpen() {
    _ecoleOpens++;
    if (_ecoleOpens < _everyEcole) return;
    if (_tryShow()) _ecoleOpens = 0;
  }

  /// Action générale significative (ex. « Calculer le Score A »).
  /// Affiche une pub toutes les [_every] actions.
  static void registerAction() {
    _actions++;
    if (_actions < _every) return;
    if (_tryShow()) _actions = 0;
  }

  /// Tente d'afficher l'interstitiel.
  /// Retourne true UNIQUEMENT si la pub a été réellement affichée (→ l'appelant
  /// remet alors son compteur à zéro). Sinon on garde le compteur : la pub
  /// partira à la prochaine action, une fois le cooldown écoulé / l'ad prête.
  static bool _tryShow() {
    // Déjà en cours (compte à rebours ou pub à l'écran).
    if (_showing) return false;

    // Cap de temps : on ne montre pas, mais on n'oublie pas le compteur.
    final last = _lastShown;
    if (last != null && DateTime.now().difference(last) < _cooldown) {
      return false;
    }

    final ad = _ad;
    if (ad == null) {
      load(); // pas prête : on précharge pour la prochaine fois
      return false;
    }

    // La pub est prête -> on la réserve, puis avertissement 3 s, puis pub.
    _ad = null;
    _showing = true;
    _lastShown = DateTime.now();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _showing = false;
        load(); // précharge la prochaine
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        _showing = false;
        load();
      },
    );
    AdIncomingPill.show(onDone: ad.show);
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  AVERTISSEMENT « PUB DANS 3 » — pilule compacte avec compte à rebours
// ═══════════════════════════════════════════════════════════════════════

/// Clé du Navigator racine : permet d'afficher la pilule par-dessus
/// N'IMPORTE QUEL écran, sans BuildContext. À brancher dans main.dart :
///   MaterialApp(navigatorKey: AdOverlay.navigatorKey, ...)
class AdOverlay {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
}

/// Pilule navy centrée en bas : [icône]  Pub dans  (3)
/// L'anneau corail se vide en [duration], puis la pilule disparaît et
/// [onDone] lance l'interstitiel. Ne bloque aucun toucher (IgnorePointer).
class AdIncomingPill extends StatefulWidget {
  const AdIncomingPill({super.key, required this.duration, required this.onFinished});

  final Duration duration;
  final VoidCallback onFinished;

  static const Color _navy = Color(0xFF14183A);
  static const Color _track = Color(0xFF2B3790);
  static const Color _coral = Color(0xFFFF6B5B);
  static const Color _coralSoft = Color(0xFFFF8A7D);

  /// Affiche la pilule puis appelle [onDone]. Sans Overlay disponible,
  /// la pub est lancée directement (comportement d'avant).
  static void show({
    required VoidCallback onDone,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = AdOverlay.navigatorKey.currentState?.overlay;
    if (overlay == null) {
      onDone();
      return;
    }
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => AdIncomingPill(
        duration: duration,
        onFinished: () {
          entry.remove();
          onDone();
        },
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<AdIncomingPill> createState() => _AdIncomingPillState();
}

class _AdIncomingPillState extends State<AdIncomingPill>
    with TickerProviderStateMixin {
  // Apparition / disparition (glisse + fondu).
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 200),
  );
  // Compte à rebours (0 -> 1).
  late final AnimationController _count =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    _enter.forward();
    _count.forward().whenComplete(() async {
      if (!mounted) return;
      await _enter.reverse();
      widget.onFinished();
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Au-dessus de la navbar (~91 px) + zone système (Android / iPhone).
    final double bottom = MediaQuery.paddingOf(context).bottom + 104;
    final curved = CurvedAnimation(
      parent: _enter,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _enter,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.8), end: Offset.zero)
                  .animate(curved),
              child: Material(
                type: MaterialType.transparency,
                child: Semantics(
                  liveRegion: true,
                  label: 'Une publicité va s\'afficher dans quelques secondes',
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
                    decoration: BoxDecoration(
                      color: AdIncomingPill._navy,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.campaign_rounded,
                            size: 18, color: AdIncomingPill._coralSoft),
                        const SizedBox(width: 8),
                        const Text(
                          'Pub dans',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Anneau + chiffre
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: AnimatedBuilder(
                            animation: _count,
                            builder: (context, _) {
                              final double t = _count.value;
                              final int secs = math.max(
                                  1,
                                  (widget.duration.inMilliseconds *
                                          (1 - t) /
                                          1000)
                                      .ceil());
                              return CustomPaint(
                                painter: _RingPainter(
                                  progress: 1 - t,
                                  track: AdIncomingPill._track,
                                  color: AdIncomingPill._coral,
                                ),
                                child: Center(
                                  child: Text(
                                    '$secs',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anneau de progression : piste + arc restant (part du haut, sens horaire).
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.track,
    required this.color,
  });

  final double progress; // 1 = plein, 0 = vide
  final Color track, color;

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 3;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawArc(
      arcRect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}