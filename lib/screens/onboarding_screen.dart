import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Écran d'accueil (onboarding) de ing-licence.
///
/// Utilisation dans main.dart :
///
///   final bool vu = await OnboardingScreen.aEteVu();
///   runApp(MyApp(afficherOnboarding: !vu));
///
/// puis, comme première route :
///
///   OnboardingScreen(
///     onTermine: () => Navigator.of(context).pushReplacement(
///       MaterialPageRoute(builder: (_) => const HomeScreen()),
///     ),
///   )

// ---------------------------------------------------------------------------
// Couleurs de l'app (ajuste-les si tu as une charte définie)
// ---------------------------------------------------------------------------
const Color kViolet = Color(0xFF3B5BFF);
const Color kVioletFonce = Color(0xFF26215C);
const Color kGrisTexte = Color(0xFF6B6B78);
const Color kPointInactif = Color(0xFFD6D3F0);

/// Part de la hauteur écran occupée par l'illustration.
const double kRatioImage = 0.80;

// ---------------------------------------------------------------------------
// Modèle d'une slide
// ---------------------------------------------------------------------------
class OnboardingItem {
  final String image; // chemin de l'asset, ex: 'assets/images/welcome1.png'
  final String titre;
  final String sousTitre;

  const OnboardingItem({
    required this.image,
    required this.titre,
    required this.sousTitre,
  });
}

// ---------------------------------------------------------------------------
// Les slides — mets ici autant d'écrans que tu veux (1, 2, 3...)
// ---------------------------------------------------------------------------
const List<OnboardingItem> kSlides = [
  OnboardingItem(
    image: 'assets/images/welcome1.png',
    titre: 'Bienvenue sur\ning-licence',
    sousTitre:
        'Calcule ton Score E et découvre les écoles d\'ingénieurs à ta portée.',
  ),
  OnboardingItem(
    image: 'assets/images/welcome2.png',
    titre: 'Simule tes choix',
    sousTitre:
        'Teste différentes combinaisons et vois instantanément où tu peux aller.',
  ),
  OnboardingItem(
    image: 'assets/images/welcome3.png',
    titre: 'Prêt à commencer ?',
    sousTitre:
        'Tout ce qu\'il te faut pour préparer ton orientation, au même endroit.',
  ),
];

// ---------------------------------------------------------------------------
// Écran
// ---------------------------------------------------------------------------
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onTermine;

  const OnboardingScreen({super.key, required this.onTermine});

  static const String _cle = 'onboarding_vu';

  /// Renvoie true si l'utilisateur a déjà vu l'onboarding.
  static Future<bool> aEteVu() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cle) ?? false;
  }

  static Future<void> _marquerVu() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cle, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  bool get _estDerniere => _page == kSlides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _terminer() async {
    await OnboardingScreen._marquerVu();
    widget.onTermine();
  }

  void _suivant() {
    if (_estDerniere) {
      _terminer();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  void _precedent() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Blanc : c'est ce qu'on voit sous l'image, derrière la carte.
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double hauteurImage = constraints.maxHeight * kRatioImage;

          return Stack(
            children: [
              // ---- IMAGE sur les 80% du haut (le PageView derrière) ----
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: hauteurImage,
                  width: double.infinity,
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: kSlides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) {
                      return Image.asset(
                        kSlides[i].image,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        // Placeholder si l'asset n'existe pas encore
                        errorBuilder: (_, __, ___) => Container(color: kViolet),
                      );
                    },
                  ),
                ),
              ),

              // ---- Dégradé sombre en haut pour lisibilité du texte ----
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 160,
                child: IgnorePointer(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x66000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),

              // ---- Barre du haut : retour + Passer ----
              SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Flèche retour (visible seulement après la 1re slide)
                      IgnorePointer(
                        ignoring: _page == 0,
                        child: AnimatedOpacity(
                          opacity: _page > 0 ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: GestureDetector(
                            onTap: _precedent,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                // Flutter < 3.27 : remplace par
                                // Colors.white.withOpacity(0.20)
                                color: Colors.white.withValues(alpha: 0.20),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_back,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ),
                      // Passer
                      TextButton(
                        onPressed: _terminer,
                        child: const Text(
                          'Passer',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ---- Carte blanche du bas (au-dessus de la barre système) ----
              SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(26, 26, 26, 30),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(32)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Points de pagination
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(kSlides.length, (i) {
                            final actif = i == _page;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3.5),
                              width: actif ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: actif ? kViolet : kPointInactif,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 18),

                        // Titre
                        Text(
                          kSlides[_page].titre,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            color: kVioletFonce,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Sous-titre
                        Text(
                          kSlides[_page].sousTitre,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.6,
                            color: kGrisTexte,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Bouton
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _suivant,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kViolet,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              _estDerniere ? 'Commencer' : 'Suivant',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}