import 'package:flutter/material.dart';

/// Couleur d'accent principale (remplace l'ancien bleu sombre).
/// Point unique : change la teinte ici pour toute l'app.
const Color kBleuRoi = Color(0xFF3B5BFF);

/// Header commun à tous les écrans : bloc coloré plein écran, collé en haut
/// (la couleur passe derrière la barre de statut) et bord à bord sur les
/// côtés, coins inférieurs arrondis.
///
/// Hauteur : au lieu d'un padding fixe (statique, mauvais sur petits/grands
/// écrans), la hauteur minimale du bloc est calculée comme un pourcentage
/// de la hauteur d'écran ([heightFactor]), avec un plancher [minHeight]
/// pour rester lisible sur les petits téléphones. Si le contenu (titre long,
/// champ de recherche, boutons…) a besoin de plus de place, le bloc grandit
/// naturellement au-delà de ce minimum — seul le plancher est contraint.
///
/// Les valeurs par défaut sont volontairement basses : un header standard
/// (eyebrow + titre, sans champ dessous) « colle » alors son contenu en haut
/// au lieu de flotter au centre d'un grand bloc coloré. Les écrans plus
/// riches (champ de recherche, licence…) dépassent ce minimum et grandissent
/// tout seuls — leur rendu est donc inchangé.
///
/// Deux façons de l'utiliser :
///  • cas standard : passer [eyebrow], [title], et éventuellement [leading]
///    (un logo à gauche), [onBack], [trailing] et [bottom] (un champ de
///    recherche, des boutons…) ;
///  • cas custom (ex. Home) : passer [child] pour remplacer tout le contenu,
///    et ajuster [heightFactor], [radius], [topPadding], [bottomPadding].
///
/// À placer TOUT EN HAUT de l'arbre, HORS du SafeArea (il gère lui-même
/// l'inset du haut). Le contenu en dessous va dans un SafeArea(top: false).
/// ⚠️ Vérifie que le RootShell n'enveloppe pas déjà le body dans un
///    SafeArea(top: true), sinon le header ne remontera pas sous la barre.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    this.eyebrow,
    this.title,
    this.leading,
    this.onBack,
    this.trailing,
    this.bottom,
    this.child,
    this.centerTitle = false,
    this.color = kBleuRoi,
    this.heightFactor = 0.14,
    this.minHeight = 110,
    this.radius = 24,
    this.topPadding = 14,
    this.bottomPadding = 20,
  });

  /// Petit sur-titre en capitales (optionnel).
  final String? eyebrow;

  /// Titre principal (optionnel si [child] est fourni).
  final String? title;

  /// Logo (ou toute autre widget) placé À GAUCHE du bloc eyebrow + titre,
  /// dans le contenu standard. Null par défaut : les écrans qui ne le passent
  /// pas gardent exactement leur rendu actuel.
  final Widget? leading;

  /// Si non-null, affiche une flèche retour en haut à gauche.
  final VoidCallback? onBack;

  /// Widget optionnel en haut à droite (ex. icône favoris).
  final Widget? trailing;

  /// Contenu libre sous le titre (champ de recherche, boutons…).
  final Widget? bottom;

  /// Remplace entièrement le contenu standard (utilisé par le Home).
  final Widget? child;

  final bool centerTitle;
  final Color color;

  /// Fraction de la hauteur d'écran utilisée comme hauteur MINIMALE du
  /// header (ex. 0.14 = 14% de l'écran). Le header peut dépasser ce
  /// minimum si le contenu l'exige, mais ne descendra jamais en dessous
  /// (sous réserve de [minHeight]).
  final double heightFactor;

  /// Plancher absolu en pixels logiques, pour les très petits écrans où
  /// [heightFactor] donnerait une valeur trop faible pour rester lisible.
  final double minHeight;

  /// Rayon des coins inférieurs (plus grand = plus arrondi).
  final double radius;

  /// Espace au-dessus du contenu (sous la barre de statut) et en dessous.
  final double topPadding, bottomPadding;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final double topInset = mq.padding.top;

    // En paysage (tablette tournée, ou tout écran plus large que haut),
    // la hauteur d'écran devient petite : un plancher absolu (minHeight)
    // y représenterait une part énorme de l'écran. On réduit donc le
    // facteur ET le plancher dans ce cas, et on plafonne plus fort le
    // maximum autorisé (28% de la hauteur au lieu de 70%).
    final bool isLandscape = mq.orientation == Orientation.landscape;
    final double effectiveFactor = isLandscape ? heightFactor * 0.55 : heightFactor;
    final double effectiveMinHeight = isLandscape ? minHeight * 0.65 : minHeight;
    final double maxAllowed = mq.size.height * (isLandscape ? 0.28 : 0.7);

    final double targetMinHeight = (mq.size.height * effectiveFactor).clamp(
        effectiveMinHeight,
        maxAllowed > effectiveMinHeight ? maxAllowed : effectiveMinHeight);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: targetMinHeight),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, topInset + topPadding, 20, bottomPadding),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
        ),
        alignment: Alignment.center,
        child: child ?? _standardContent(),
      ),
    );
  }

  Widget _standardContent() {
    final bool hasTopRow = onBack != null || trailing != null;

    // Bloc texte eyebrow + titre (l'un au-dessus de l'autre).
    final Widget textColumn = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment:
          centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (title != null)
          Text(
            title!,
            textAlign: centerTitle ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
      ],
    );

    // Si un [leading] (logo) est fourni, on le pose à GAUCHE du bloc titre.
    // Sinon, rendu identique à avant.
    final Widget titleBlock = leading == null
        ? textColumn
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              leading!,
              const SizedBox(width: 12),
              Expanded(child: textColumn),
            ],
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment:
          centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (hasTopRow) ...[
          Row(
            children: [
              if (onBack != null)
                HeaderIconButton(icon: Icons.arrow_back, onTap: onBack),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
        ],
        titleBlock,
        if (bottom != null) ...[
          const SizedBox(height: 14),
          bottom!,
        ],
      ],
    );
  }
}

/// Bouton icône circulaire translucide, à poser sur le header coloré.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.18),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }
}

/// Champ de recherche blanc prêt à poser dans le header coloré.
class HeaderSearchField extends StatelessWidget {
  const HeaderSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF9AA0B8), fontSize: 14),
        prefixIcon: const Icon(Icons.search, color: Color(0xFF9AA0B8)),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}