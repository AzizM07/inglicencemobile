// native_ad_manager.dart
//
// Gère un petit POOL d'annonces natives pour un écran-liste :
//  • précharge les annonces À L'AVANCE (avant que l'user scrolle jusqu'à elles) ;
//  • GARDE chaque annonce en mémoire (une par « slot ») → quand on scrolle et
//    qu'on revient, la MÊME annonce est réaffichée instantanément, sans
//    rechargement ni disparition ;
//  • ne les libère qu'UNE fois, au dispose de l'écran.
//
// Le widget InFeedNativeAd (public, réutilisable) affiche l'annonce d'un slot,
// avec wantKeepAlive pour ne jamais être détruit au scroll. Utilisé par
// Score E, Admis et Écoles.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class NativeAdManager {
  NativeAdManager({
    required this.adUnitId,
    required this.factoryId,
    this.maxAds = 3,
  });

  final String adUnitId;
  final String factoryId;
  final int maxAds;

  final Map<int, ValueNotifier<NativeAd?>> _slots = {};
  final Set<int> _loading = {};
  bool _disposed = false;

  /// Notifier du slot [index]. Lance le chargement si ce n'est pas déjà fait.
  ValueListenable<NativeAd?> slot(int index) {
    final n = _slots.putIfAbsent(index, () => ValueNotifier<NativeAd?>(null));
    if (!_disposed &&
        index < maxAds &&
        n.value == null &&
        !_loading.contains(index)) {
      _startLoad(index, n);
    }
    return n;
  }

  /// Précharge d'avance [count] slots (à appeler dès que la liste est connue).
  void preload(int count) {
    final c = count > maxAds ? maxAds : count;
    for (int i = 0; i < c; i++) {
      slot(i);
    }
  }

  void _startLoad(int index, ValueNotifier<NativeAd?> n) {
    _loading.add(index);
    late final NativeAd ad;
    ad = NativeAd(
      adUnitId: adUnitId,
      factoryId: factoryId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          _loading.remove(index);
          if (_disposed) {
            ad.dispose();
            return;
          }
          n.value = ad; // → le widget du slot s'affiche
        },
        onAdFailedToLoad: (a, error) {
          _loading.remove(index);
          a.dispose();
          // On laisse la valeur à null : le slot reste vide (pas de trou).
        },
      ),
    )..load();
  }

  /// Libère toutes les annonces et notifiers. À appeler au dispose de l'écran.
  void dispose() {
    _disposed = true;
    for (final n in _slots.values) {
      n.value?.dispose();
      n.dispose();
    }
    _slots.clear();
    _loading.clear();
  }
}

/// Affiche l'annonce native du slot [slotIndex] fournie par [manager].
///
/// • Mise en page 100 % maison (Android : ecole_native_ad.xml +
///   EcoleNativeAdFactory.kt) via le factoryId du manager.
/// • L'annonce est préchargée + mise en cache par le manager : ni rechargée ni
///   détruite au scroll (wantKeepAlive) → elle reste en place.
/// • Tant que l'annonce n'est pas prête, n'occupe aucune place.
///
/// NB iOS : sans factory iOS enregistrée, ce natif ne s'affiche pas (pas de
/// crash) tant qu'on n'a pas fait l'équivalent Swift.
class InFeedNativeAd extends StatefulWidget {
  const InFeedNativeAd({
    super.key,
    required this.manager,
    required this.slotIndex,
    this.height = 205,
  });

  final NativeAdManager manager;
  final int slotIndex;
  final double height;

  @override
  State<InFeedNativeAd> createState() => _InFeedNativeAdState();
}

class _InFeedNativeAdState extends State<InFeedNativeAd>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // requis par AutomaticKeepAliveClientMixin

    return ValueListenableBuilder<NativeAd?>(
      valueListenable: widget.manager.slot(widget.slotIndex),
      builder: (context, ad, _) {
        if (ad == null) return const SizedBox.shrink();
        return SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AdWidget(ad: ad),
        );
      },
    );
  }
}