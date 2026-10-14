/// ============================================================
///  CALCUL DU SCORE A — portage fidèle de assets/js/score-a.js
/// ============================================================
library;

class ScoreAInput {
  final int? anneeNaissance;
  final double moyBac;
  final double moyL1, moyL2;
  final int rangL1, effL1, rangL2, effL2;
  final double frL1, frL2, enL1, enL2;

  const ScoreAInput({
    required this.anneeNaissance,
    this.moyBac = 0,
    this.moyL1 = 0,
    this.moyL2 = 0,
    this.rangL1 = 1,
    this.effL1 = 1,
    this.rangL2 = 1,
    this.effL2 = 1,
    this.frL1 = 0,
    this.frL2 = 0,
    this.enL1 = 0,
    this.enL2 = 0,
  });
}

class ScoreAResult {
  final double m; // Moyennes  (/100)
  final double r; // Rang      (/100)
  final double ml; // Langues  (/20)
  final int bonus; // B1 + B2
  final double total; // Score A

  const ScoreAResult({
    required this.m,
    required this.r,
    required this.ml,
    required this.bonus,
    required this.total,
  });
}

class ScoreACalculator {
  /// Année du concours utilisée pour le bonus d'âge (fixée à 2026 comme dans le JS).
  static const int anneeConcours = 2026;

  static ScoreAResult compute(ScoreAInput i) {
    // [M] performance des deux années
    final mg = (i.moyL1 + i.moyL2) / 2;
    double m;
    if (mg >= 15) {
      m = 100;
    } else if (mg > 10 && mg < 15) {
      m = 20 * (mg - 10);
    } else {
      m = 0;
    }

    // [R] classement (seuil 30 %)
    final ri1 = (i.rangL1 - 1) / i.effL1;
    final ri2 = (i.rangL2 - 1) / i.effL2;
    final ri1s = (ri1 <= 0.3) ? (100 - (700 * ri1) / 3) : 0.0;
    final ri2s = (ri2 <= 0.3) ? (100 - (700 * ri2) / 3) : 0.0;
    final r = (ri1s + ri2s) / 2;

    // [B1] âge
    final b1 = (i.anneeNaissance != null &&
            i.anneeNaissance! >= (anneeConcours - 22))
        ? 5
        : 0;

    // [B2] mention bac
    int b2;
    if (i.moyBac >= 16) {
      b2 = 20;
    } else if (i.moyBac >= 14) {
      b2 = 15;
    } else if (i.moyBac >= 12) {
      b2 = 10;
    } else if (i.moyBac >= 11) {
      b2 = 5;
    } else {
      b2 = 0;
    }

    // [ML] langues
    final ml = (i.frL1 + i.frL2 + i.enL1 + i.enL2) / 4;

    // Formule officielle
    final total =
        (0.2 * m) + ((1.4 / 3) * r) + ((5 / 6) * ml) + ((2 / 3) * (b1 + b2));

    return ScoreAResult(m: m, r: r, ml: ml, bonus: b1 + b2, total: total);
  }
}