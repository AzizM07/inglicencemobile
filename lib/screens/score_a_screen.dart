import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_header.dart';
import '../logic/score_a.dart';
import '../services/score_a_store.dart';
import '../services/ad_service.dart';

// PUBS : l'ID du bloc natif vient de AdIds.native (ad_service.dart).
//
// FORMULAIRE — design « A · Minimal » :
//  • une carte blanche par section, titre précédé d'un petit trait bleu ;
//  • champs gris doux, sans bordure, contour bleu au focus ;
//  • aucun compteur / coche / barre : simple et pro.
// SAISIE : toutes les MOYENNES sont limitées de 0 à 20 (max 2 décimales,
// virgule ou point acceptés) ; Rang et Effectif = entiers sans limite.
// Logique inchangée : ScoreACalculator, ScoreAStore, interstitiel, pub native.
// Le bas de la liste n'est plus caché par la barre de navigation.

const Color _kFieldBg = Color(0xFFF3F5FC);
const Color _kLabel = Color(0xFF8A90A8);
const Color _kHint = Color(0xFFB4BAD0);

class ScoreAScreen extends StatefulWidget {
  const ScoreAScreen({super.key});
  @override
  State<ScoreAScreen> createState() => _ScoreAScreenState();
}

class _ScoreAScreenState extends State<ScoreAScreen> {
  final _moyBac = TextEditingController();
  final _moyL1 = TextEditingController();
  final _rangL1 = TextEditingController();
  final _effL1 = TextEditingController();
  final _moyL2 = TextEditingController();
  final _rangL2 = TextEditingController();
  final _effL2 = TextEditingController();
  final _frL1 = TextEditingController();
  final _frL2 = TextEditingController();
  final _enL1 = TextEditingController();
  final _enL2 = TextEditingController();
  int? _annee;

  ScoreAResult? _result;
  String? _error;

  // --- Publicité native (affichée SOUS le résultat) ---
  NativeAd? _nativeAd;
  bool _nativeAdReady = false;

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  void _loadNativeAd() {
    _nativeAd = NativeAd(
      adUnitId: AdIds.native,
      request: const AdRequest(),
      // Template « medium » ≈ 300×250 : c'est le format qui capte le plus de
      // demande (display + vidéo) tout en restant intégré au design.
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: Colors.white,
        cornerRadius: 14,
        callToActionTextStyle: NativeTemplateTextStyle(
          backgroundColor: AppColors.blue,
          textColor: Colors.white,
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _nativeAdReady = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _nativeAd = null;
          // On reste silencieux : pas de pub = pas de bloc, l'écran reste propre.
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    for (final c in [
      _moyBac, _moyL1, _rangL1, _effL1, _moyL2, _rangL2, _effL2,
      _frL1, _frL2, _enL1, _enL2
    ]) {
      c.dispose();
    }
    _nativeAd?.dispose();
    super.dispose();
  }

  double _d(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  /// rang/effectif : défaut 1 comme dans le JS (parseInt || 1).
  int _i(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    return (v == null || v < 1) ? 1 : v;
  }

  void _calculer() {
    FocusScope.of(context).unfocus();
    if (_annee == null) {
      setState(() {
        _error =
            'Veuillez sélectionner votre année de naissance avant de lancer le calcul.';
        _result = null;
      });
      return;
    }
    final res = ScoreACalculator.compute(ScoreAInput(
      anneeNaissance: _annee,
      moyBac: _d(_moyBac),
      moyL1: _d(_moyL1), rangL1: _i(_rangL1), effL1: _i(_effL1),
      moyL2: _d(_moyL2), rangL2: _i(_rangL2), effL2: _i(_effL2),
      frL1: _d(_frL1), frL2: _d(_frL2), enL1: _d(_enL1), enL2: _d(_enL2),
    ));
    // Persistance + mise à jour du header Home : on enregistre le score ET la
    // moyenne du bac (null si le champ est vide, pour ne pas afficher 0,00).
    final moyBac = _moyBac.text.trim().isEmpty ? null : _d(_moyBac);
    ScoreAStore.save(res, moyBac: moyBac);
    setState(() {
      _error = null;
      _result = res;
    });
    InterstitialAdService.registerAction();
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Column(
        children: [
          AppHeader(
            // Logo à gauche de l'eyebrow + titre.
            leading: Image.asset(
              'assets/images/logo2.png',
              height: 34,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            eyebrow: 'Concours spécifiques · 1ère étape',
            title: 'Calculer le Score A',
          ),
          // Pas de SafeArea : la liste va jusqu'en bas de l'écran et son
          // padding bas (qui inclut la hauteur de la navbar grâce à
          // extendBody) évite que le contenu soit caché par la barre.
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                  16, 18, 16, 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                const Text(
                  'Renseignez vos moyennes, rangs et langues. Le calcul suit les critères du MESRS (base 100).',
                  style: TextStyle(fontSize: 14, height: 1.55, color: AppColors.gray),
                ),
                const SizedBox(height: 16),

                _Section(
                  title: 'Informations générales',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _yearField()),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Field(label: 'Moyenne Bac', c: _moyBac, hint: '15,50'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: '1ère année',
                  child: _yearRow(_moyL1, _rangL1, _effL1, '14,25', '15', '120'),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: '2ème année',
                  child: _yearRow(_moyL2, _rangL2, _effL2, '13,80', '20', '118'),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Langues',
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: _Field(label: 'Français L1', c: _frL1, hint: '16,00')),
                      const SizedBox(width: 10),
                      Expanded(child: _Field(label: 'Français L2', c: _frL2, hint: '15,50')),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _Field(label: 'Anglais L1', c: _enL1, hint: '14,00')),
                      const SizedBox(width: 10),
                      Expanded(child: _Field(label: 'Anglais L2', c: _enL2, hint: '13,75')),
                    ]),
                  ]),
                ),
                const SizedBox(height: 18),

                _CalcButton(onTap: _calculer),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDECEC),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: const Color(0xFFF6C9C9)),
                    ),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: Color(0xFFB83535))),
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 22),
                  _ResultCard(res: _result!),
                  // --- Natif juste sous le résultat : moment de valeur,
                  // 100% de visibilité, et il ne s'affiche que si l'ad
                  // est bien chargée (sinon rien, écran propre). ---
                  if (_nativeAdReady && _nativeAd != null) ...[
                    const SizedBox(height: 18),
                    _NativeAdCard(ad: _nativeAd!),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Moyenne · Rang · Effectif sur une ligne.
  Widget _yearRow(TextEditingController m, TextEditingController r,
      TextEditingController e, String hm, String hr, String he) {
    return Row(children: [
      Expanded(child: _Field(label: 'Moyenne', c: m, hint: hm)),
      const SizedBox(width: 10),
      Expanded(child: _Field(label: 'Rang', c: r, hint: hr, intOnly: true)),
      const SizedBox(width: 10),
      Expanded(child: _Field(label: 'Effectif', c: e, hint: he, intOnly: true)),
    ]);
  }

  Widget _yearField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Année de naissance'),
        DropdownButtonFormField<int>(
          value: _annee,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _kLabel),
          style: const TextStyle(fontSize: 14.5, color: AppColors.ink),
          decoration: _fieldDecoration(),
          hint: const Text('Choisir', style: TextStyle(fontSize: 14, color: _kHint)),
          items: [
            for (int y = 2008; y >= 1995; y--)
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
          onChanged: (v) => setState(() => _annee = v),
        ),
      ],
    );
  }
}

/// Champ « minimal » : fond gris doux, pas de bordure, contour bleu au focus.
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

/// Limite la saisie d'une moyenne à [0 ; max] avec au plus 2 décimales.
/// Accepte la virgule ou le point ; refuse toute frappe qui dépasserait max
/// (ex. « 21 », « 20,5 ») — le champ garde alors sa valeur précédente.
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

// ─────────────────────────────────────────────────────────────────────────
//  COMPOSANTS DU FORMULAIRE
// ─────────────────────────────────────────────────────────────────────────

/// Carte blanche + titre précédé d'un petit trait bleu.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 3,
              height: 15,
              decoration: BoxDecoration(
                color: AppColors.blue,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink)),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// --- Bloc natif stylé (bordure + coins arrondis raccord avec le design) ---

class _NativeAdCard extends StatelessWidget {
  const _NativeAdCard({required this.ad});
  final NativeAd ad;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      // Hauteur fixe indispensable : dans un ListView, le AdWidget n'a pas de
      // contrainte de hauteur propre. 320 = taille du template « medium ».
      child: SizedBox(
        height: 320,
        width: double.infinity,
        child: AdWidget(ad: ad),
      ),
    );
  }
}

// --- petits composants d'UI ---

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w500, color: _kLabel)),
      );
}

/// Champ numérique. Moyennes : 0 → 20 (2 décimales max).
/// Rang / Effectif ([intOnly]) : entiers, sans limite.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.c,
    this.hint,
    this.intOnly = false,
  });

  final String label;
  final TextEditingController c;
  final String? hint;
  final bool intOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        TextField(
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: !intOnly),
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 14.5, color: AppColors.ink),
          inputFormatters: intOnly
              ? [FilteringTextInputFormatter.digitsOnly]
              : const [_MoyenneFormatter(max: 20)],
          decoration: _fieldDecoration(hint: hint),
        ),
      ],
    );
  }
}

/// Bouton plein, bleu de marque, coins arrondis.
class _CalcButton extends StatelessWidget {
  const _CalcButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppColors.blue,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Center(
              child: Text('Calculer mon Score A',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.res});
  final ScoreAResult res;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: const Color(0xFFDBE2FB)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEEF2FD), Color(0xFFE7EBFD)],
            ),
          ),
          // FIX overflow : le libellé prend l'espace restant (Expanded) et se
          // met sur 2 lignes si besoin ; le gros score ne déborde plus jamais
          // grâce au FittedBox (il se réduit si la valeur est large).
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VOTRE SCORE A',
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                            color: AppColors.blue)),
                    const SizedBox(height: 6),
                    const Text('Critères MESRS · base 100',
                        style: TextStyle(fontSize: 12, color: AppColors.graySoft)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                flex: 0,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(res.total.toStringAsFixed(2),
                      style: AppTheme.mono(size: 40, color: AppColors.ink)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _Bd(k: 'M · Moyennes', v: res.m, dec: 1, max: '/ 100'),
          const SizedBox(width: 10),
          _Bd(k: 'R · Rang', v: res.r, dec: 1, max: '/ 100'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _Bd(k: 'ML · Langues', v: res.ml, dec: 2, max: '/ 20'),
          const SizedBox(width: 10),
          _Bd(k: 'Bonus', v: res.bonus.toDouble(), dec: 0, max: 'âge + mention'),
        ]),
        const SizedBox(height: 12),
        const Text(
          'Formule officielle : 0,2·M + (1,4/3)·R + (5/6)·ML + (2/3)·(B1+B2).',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.graySoft),
        ),
      ],
    );
  }
}

class _Bd extends StatelessWidget {
  const _Bd({required this.k, required this.v, required this.max, this.dec = 1});
  final String k;
  final double v;
  final String max;
  final int dec;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.field,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(children: [
          Text(k.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.graySoft)),
          const SizedBox(height: 6),
          // FittedBox aussi ici par sécurité (évite un futur overflow sur les
          // petites cartes si une valeur devient large).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(v.toStringAsFixed(dec), style: AppTheme.mono(size: 18)),
          ),
          Text(max, style: const TextStyle(fontSize: 10, color: AppColors.graySoft)),
        ]),
      ),
    );
  }
}