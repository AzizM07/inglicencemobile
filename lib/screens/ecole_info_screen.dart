// ecole_info_screen.dart — Fiche d'une école (portage mobile de /ecoles/[slug]).
//
// Ouverte depuis « Les écoles ». Affiche les infos propres à l'école :
// en-tête (sigle + nom AR), infos pratiques (adresse, email, places, filières),
// et la liste des filières avec leurs licences acceptées.
//
// Le bouton « Calculer le Score E » renvoie vers EcoleDetailScreen (l'écran
// des formules/simulateur, partagé avec Score E).
//
// On reçoit directement l'objet école (déjà chargé par EcolesScreen), donc
// aucun rechargement réseau ici. Champs attendus (cf. dataset `data`) :
//   id, sigle, nom, adresse, contact, total_places_annee1,
//   filieres[] : { code, nom, places, licences_acceptees[] }

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_header.dart';
import 'ecole_detail_screen.dart';
import 'score_e_screen.dart' show LicenceChip;

class EcoleInfoScreen extends StatelessWidget {
  const EcoleInfoScreen({super.key, required this.ecole});
  final Map<String, dynamic> ecole;

  String get _id => (ecole['id'] ?? '').toString();
  String get _sigle => (ecole['sigle'] ?? _id).toString();
  String get _nom => (ecole['nom'] ?? '').toString();
  String get _adresse => (ecole['adresse'] ?? '').toString();
  String get _contact => (ecole['contact'] ?? '').toString();

  int get _places => (ecole['total_places_annee1'] is num)
      ? (ecole['total_places_annee1'] as num).toInt()
      : 0;

  List<Map<String, dynamic>> get _filieres =>
      ((ecole['filieres'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

  @override
  Widget build(BuildContext context) {
    final fils = _filieres;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: Column(
          children: [
            AppHeader(
              onBack: () => Navigator.of(context).maybePop(),
              eyebrow: 'Répertoire · Mutation MESRS',
              title: _sigle,
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  children: [
                    _heroCard(),
                    const SizedBox(height: 14),
                    _infosPratiques(),
                    const SizedBox(height: 20),
                    Text('Filières disponibles',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink)),
                    const SizedBox(height: 4),
                    Text(
                      '${fils.length} filière${fils.length > 1 ? 's' : ''} d\'ingénieur',
                      style: const TextStyle(fontSize: 13, color: AppColors.gray),
                    ),
                    const SizedBox(height: 12),
                    if (fils.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Aucune filière renseignée pour cette école.',
                            style: TextStyle(color: AppColors.gray)),
                      )
                    else
                      for (final f in fils) ...[
                        _FiliereCard(filiere: f),
                        const SizedBox(height: 10),
                      ],
                    const SizedBox(height: 12),
                    _ctaScoreE(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── En-tête : sigle + id + nom AR ────────────────────────────────────────
  Widget _heroCard() {
    return SoftCard(
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_id, style: AppTheme.mono(size: 11, color: AppColors.blue)),
          const SizedBox(height: 4),
          Text(_sigle,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.4)),
          if (_nom.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_nom,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                    fontSize: 15, height: 1.5, color: Color(0xFF3D4266))),
          ],
          const SizedBox(height: 14),
          Container(
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEF0F7)))),
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                _kpi('$_places', 'Places 1ère année'),
                _kpi('${_filieres.length}', 'Filières'),
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
                  fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.blue)),
          const SizedBox(height: 2),
          Text(l,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, color: AppColors.gray)),
        ],
      ),
    );
  }

  // ── Infos pratiques (adresse / email) ────────────────────────────────────
  Widget _infosPratiques() {
    final rows = <Widget>[];
    if (_adresse.isNotEmpty) {
      rows.add(_infoRow(Icons.location_on_outlined, 'Adresse', _adresse, rtl: true));
    }
    if (_contact.isNotEmpty) {
      rows.add(_infoRow(Icons.mail_outline_rounded, 'Email', _contact));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return SoftCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool rtl = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FD),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10.5,
                      letterSpacing: .5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.graySoft)),
              const SizedBox(height: 3),
              Text(value,
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(
                      fontSize: 14, height: 1.4, color: AppColors.ink)),
            ],
          ),
        ),
      ],
    );
  }

  // ── CTA : renvoie vers l'écran des formules Score E ──────────────────────
  Widget _ctaScoreE(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcoleDetailScreen(ecoleId: _id)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calculate_rounded, size: 18, color: Colors.white),
            SizedBox(width: 8),
            Text('Calculer le Score E de cette école',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  CARTE FILIÈRE (code + nom AR + places + licences acceptées)
// ─────────────────────────────────────────────────────────────────────────

class _FiliereCard extends StatelessWidget {
  const _FiliereCard({required this.filiere});
  final Map<String, dynamic> filiere;

  @override
  Widget build(BuildContext context) {
    final code = (filiere['code'] ?? '').toString();
    final nom = (filiere['nom'] ?? '').toString();
    final places = (filiere['places'] is num)
        ? (filiere['places'] as num).toInt()
        : 0;
    final licences = ((filiere['licences_acceptees'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((s) => s.trim().isNotEmpty)
        .toList();

    return SoftCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (code.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.violetTint,
                  borderRadius: BorderRadius.circular(999)),
              child: Text(code, style: AppTheme.mono(size: 12, color: AppColors.blue)),
            ),
          if (nom.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(nom,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ],
          const SizedBox(height: 6),
          Text('$places place${places > 1 ? 's' : ''} disponibles',
              style: const TextStyle(fontSize: 12.5, color: AppColors.gray)),
          if (licences.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Licences acceptées',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.graySoft)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final l in licences) LicenceChip(l)],
            ),
          ],
        ],
      ),
    );
  }
}