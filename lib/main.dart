import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/score_a_screen.dart';
import 'screens/score_e_screen.dart';
import 'services/ad_service.dart';
import 'services/notification_service.dart';
import 'screens/onboarding_screen.dart';
import 'services/score_a_store.dart';
import 'services/licence_store.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Firebase / notifications push (FCM) ---
  // Protégé par try/catch : si la config Firebase d'une plateforme manque
  // (ex. iOS avant `flutterfire configure`), l'app démarre quand même,
  // simplement sans notifications push, au lieu de crasher au lancement.
  try {
    // 1) Init Firebase (utilise lib/firebase_options.dart généré par flutterfire).
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // 2) Handler des messages reçus quand l'app est en arrière-plan / fermée.
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    // 3) Permission + canal + abonnement au topic « all » + affichage foreground.
    await NotificationService.init();
  } catch (e) {
    debugPrint('Firebase / notifications désactivés : $e');
  }

  await ScoreAStore.init(); // recharge le Score A enregistré (session précédente)
  await LicenceStore.init(); // recharge la Licence enregistrée (affichée sur l'accueil)
  await MobileAds.instance.initialize();

  // Barre système Android (boutons / gestes) : l'app dessine dessous et elle
  // est transparente -> c'est notre barre de navigation blanche qui apparaît
  // derrière les boutons (plus de bande sombre sous la navbar).
  // iOS n'a pas de barre de navigation système : réglage Android uniquement.
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark, // icônes sombres sur blanc
      systemNavigationBarContrastEnforced: false,
    ));
  }

  InterstitialAdService.load();
  final bool onboardingVu = await OnboardingScreen.aEteVu();

  runApp(IngLicenceApp(afficherOnboarding: !onboardingVu));
}

class IngLicenceApp extends StatefulWidget {
  final bool afficherOnboarding;
  const IngLicenceApp({super.key, required this.afficherOnboarding});

  @override
  State<IngLicenceApp> createState() => _IngLicenceAppState();
}

class _IngLicenceAppState extends State<IngLicenceApp> {
  late bool _afficherOnboarding = widget.afficherOnboarding;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Permet à AdIncomingPill (« Pub dans 3 ») de s'afficher par-dessus
      // n'importe quel écran avant un interstitiel.
      navigatorKey: AdOverlay.navigatorKey,
      title: 'Ing-Licence',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 👇 setState direct au lieu de Navigator.of(context). L'ancien code
      // utilisait le context de IngLicenceApp.build, qui est AU-DESSUS du
      // Navigator créé en interne par MaterialApp — Navigator.of(context)
      // ne le trouvait donc pas et l'appel échouait silencieusement.
      home: _afficherOnboarding
          ? OnboardingScreen(
              onTermine: () => setState(() => _afficherOnboarding = false),
            )
          : const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  DateTime? _lastBack;

  void _go(int i) => setState(() => _index = i);

  void _onBack() {
    // Score A / Score E -> retour à l'Accueil.
    if (_index != 0) {
      _go(0);
      return;
    }
    // Accueil -> double retour pour quitter (Android uniquement :
    // Apple interdit aux apps de se fermer elles-mêmes).
    if (!Platform.isAndroid) return;
    final now = DateTime.now();
    final last = _lastBack;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Appuyez encore une fois pour quitter'),
        duration: Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    // Blog volontairement retiré de la version mobile.
    final pages = [
      HomeScreen(onNavigate: _go),
      const ScoreAScreen(),
      const ScoreEScreen(),
    ];

    return PopScope(
      canPop: false, // on gère le retour nous-mêmes
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onBack();
      },
      child: Scaffold(
        // Le corps passe SOUS la barre : l'encoche et les côtés laissent voir
        // le vrai fond de la page (plus de bande vide au-dessus de la barre).
        // Flutter ajoute automatiquement la hauteur de la barre au padding
        // bas (MediaQuery) : les SafeArea des écrans évitent qu'elle cache
        // le contenu.
        extendBody: true,
        body: IndexedStack(
          sizing: StackFit.expand,
          index: _index,
          children: pages,
        ),
        // Barre de navigation « encoche + bulle » (voir _NotchNavBar plus bas).
        bottomNavigationBar: _NotchNavBar(
          index: _index,
          onTap: _go,
          items: const [
            _NavItem(Icons.home_rounded, 'Accueil'),
            _NavItem(Icons.calculate_rounded, 'Score A'),
            _NavItem(Icons.school_rounded, 'Score E'),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────
//  BARRE DE NAVIGATION « ENCOCHE + BULLE »
// ─────────────────────────────────────────────────────────────────────────
//
// Barre PLEINE LARGEUR, collée en bas de l'écran : sa couleur descend
// jusque sous la barre système (Android) / l'indicateur d'accueil (iPhone).
// L'icône active est dans une bulle corail centrée EXACTEMENT sur le bord
// haut de la barre ; l'encoche est un arc de cercle concentrique à la bulle
// (rayon + _gap), donc l'écart bulle/encoche est constant partout.
// Une seule position (cx), bornée une fois, pilote bulle ET encoche.
//
// COULEURS : barre blanche (avec un fin liseré en haut pour la détacher du
// contenu), bulle corail, icônes bleues.

const Color _kNavBar = Colors.white;
const Color _kNavBubble = Color(0xFFFF6B5B); // corail
const Color _kNavIcon = AppColors.blue; // icônes + libellés inactifs
const Color _kNavLine = Color(0xFFE3E8FB); // liseré du bord haut

class _NavItem {
  const _NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Géométrie partagée par le widget et le painter.
class _NavGeom {
  static const double bubbleR = 25; // rayon de la bulle (Ø 50)
  static const double gap = 5; // espace constant bulle ↔ encoche
  static const double notchR = bubbleR + gap; // rayon de l'encoche
  static const double fillet = 9; // rayon des congés de raccord
  static const double top = bubbleR + 4; // bord haut de la barre
  static const double barHeight = 62; // hauteur de la barre (hors zone système)

  /// Demi-largeur totale de l'encoche (congés inclus) sur le bord haut.
  static final double halfWidth =
      math.sqrt(math.pow(notchR + fillet, 2) - math.pow(fillet, 2));
}

class _NotchNavBar extends StatelessWidget {
  const _NotchNavBar({
    required this.index,
    required this.onTap,
    required this.items,
  });

  final int index;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    // Hauteur de la zone système en bas (gestes / boutons Android, indicateur
    // d'accueil iPhone) : la barre la recouvre aussi, les onglets restent
    // au-dessus.
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      height: _NavGeom.top + _NavGeom.barHeight + bottomInset,
      child: LayoutBuilder(
        builder: (context, c) {
          final double w = c.maxWidth;
          final double itemW = w / items.length;
          // Limites pour que l'encoche ne sorte jamais de l'écran.
          final double minX = _NavGeom.halfWidth;
          final double maxX = w - minX;

          return TweenAnimationBuilder<double>(
            tween: Tween(end: index.toDouble()),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            builder: (context, pos, _) {
              // ▼ Position UNIQUE, bornée une fois, utilisée partout.
              final double cx = ((pos + 0.5) * itemW).clamp(minX, maxX);
              final _NavItem active = items[index];

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── Barre + encoche (jusqu'en bas de l'écran) ──
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _NotchBarPainter(centerX: cx, color: _kNavBar),
                    ),
                  ),
                  // ── Onglets (l'actif s'efface, il est dans la bulle) ──
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _NavGeom.top,
                    height: _NavGeom.barHeight,
                    child: Row(
                      children: [
                        for (int i = 0; i < items.length; i++)
                          Expanded(
                            child: _NavButton(
                              item: items[i],
                              opacity: (pos - i).abs().clamp(0.0, 1.0),
                              selected: i == index,
                              onTap: () => onTap(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // ── Bulle : centrée sur (cx, bord haut de la barre) ──
                  Positioned(
                    left: cx - _NavGeom.bubbleR,
                    top: _NavGeom.top - _NavGeom.bubbleR,
                    child: GestureDetector(
                      onTap: () => onTap(index),
                      child: Container(
                        width: _NavGeom.bubbleR * 2,
                        height: _NavGeom.bubbleR * 2,
                        decoration: const BoxDecoration(
                          color: _kNavBubble,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: Icon(
                            active.icon,
                            key: ValueKey(index),
                            color: Colors.white,
                            size: 24,
                            semanticLabel: active.label,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.opacity,
    required this.selected,
    required this.onTap,
  });

  final _NavItem item;
  final double opacity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Opacity(
          opacity: opacity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, color: _kNavIcon, size: 24),
              const SizedBox(height: 3),
              Text(
                item.label,
                style: const TextStyle(
                  color: _kNavIcon,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barre pleine largeur + encoche concentrique à la bulle, avec congés.
/// Le rectangle va du bord haut (_NavGeom.top) jusqu'au bas du widget.
class _NotchBarPainter extends CustomPainter {
  const _NotchBarPainter({required this.centerX, required this.color});

  final double centerX;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const double t = _NavGeom.top;
    const double rn = _NavGeom.notchR;
    const double s = _NavGeom.fillet;
    final double w = size.width, b = size.height;
    final double cx = centerX;
    final double dx = _NavGeom.halfWidth;

    // Angles des points de tangence (congé ↔ encoche).
    final double a = math.atan2(-s, dx); // sur le congé gauche
    final double bAng = math.atan2(s, -dx); // sur l'encoche, côté gauche

    // Bord haut seul (gauche -> encoche -> droite) : sert au liseré.
    final edge = Path()
      ..moveTo(0, t)
      ..lineTo(cx - dx, t)
      // Congé gauche : du haut du cercle jusqu'au point de tangence.
      ..arcTo(
        Rect.fromCircle(center: Offset(cx - dx, t + s), radius: s),
        -math.pi / 2,
        a + math.pi / 2,
        false,
      )
      // Encoche : arc centré sur la bulle, en passant par le bas.
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, t), radius: rn),
        bAng,
        (math.pi - bAng) - bAng,
        false,
      )
      // Congé droit : symétrique du gauche.
      ..arcTo(
        Rect.fromCircle(center: Offset(cx + dx, t + s), radius: s),
        math.pi - a,
        -math.pi / 2 - (math.pi - a) + 2 * math.pi,
        false,
      )
      ..lineTo(w, t);

    // Forme pleine = bord haut + descente jusqu'en bas de l'écran.
    final body = Path.from(edge)
      ..lineTo(w, b)
      ..lineTo(0, b)
      ..close();

    // Pas d'ombre : elle s'accumulait dans l'encoche et dessinait un
    // anneau noir autour de la bulle. Le liseré suffit à détacher la barre.
    canvas.drawPath(body, Paint()..color = color);
    canvas.drawPath(
      edge,
      Paint()
        ..color = _kNavLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _NotchBarPainter old) =>
      old.centerX != centerX || old.color != color;
}