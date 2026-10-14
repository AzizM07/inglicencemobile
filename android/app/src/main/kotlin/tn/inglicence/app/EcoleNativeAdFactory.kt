// Destination :
//   android/app/src/main/kotlin/tn/inglicence/app/EcoleNativeAdFactory.kt
package tn.inglicence.app

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.ImageView
import android.widget.RatingBar
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

/// Construit une carte native au style des _EcoleCard à partir du layout
/// res/layout/ecole_native_ad.xml. Le contenu reste celui de l'annonceur ;
/// seule la MISE EN PAGE est la tienne.
class EcoleNativeAdFactory(private val context: Context) :
    GoogleMobileAdsPlugin.NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.ecole_native_ad, null) as NativeAdView

        // Titre (asset obligatoire).
        val headline = adView.findViewById<TextView>(R.id.ad_headline)
        headline.text = nativeAd.headline
        adView.headlineView = headline

        // Description.
        val body = adView.findViewById<TextView>(R.id.ad_body)
        if (nativeAd.body.isNullOrEmpty()) {
            body.visibility = View.GONE
        } else {
            body.visibility = View.VISIBLE
            body.text = nativeAd.body
        }
        adView.bodyView = body

        // Bouton d'action.
        val cta = adView.findViewById<TextView>(R.id.ad_call_to_action)
        if (nativeAd.callToAction.isNullOrEmpty()) {
            cta.visibility = View.GONE
        } else {
            cta.visibility = View.VISIBLE
            cta.text = nativeAd.callToAction
        }
        adView.callToActionView = cta

        // Icône.
        val icon = adView.findViewById<ImageView>(R.id.ad_icon)
        val ic = nativeAd.icon
        if (ic == null) {
            icon.visibility = View.GONE
        } else {
            icon.setImageDrawable(ic.drawable)
            icon.visibility = View.VISIBLE
        }
        adView.iconView = icon

        // Étoiles (souvent nulles hors apps du Play Store).
        val stars = adView.findViewById<RatingBar>(R.id.ad_stars)
        val rating = nativeAd.starRating
        if (rating == null || rating == 0.0) {
            stars.visibility = View.GONE
        } else {
            stars.rating = rating.toFloat()
            stars.visibility = View.VISIBLE
        }
        adView.starRatingView = stars

        // Enregistre l'annonce sur la vue (rend les assets cliquables + AdChoices).
        adView.setNativeAd(nativeAd)
        return adView
    }
}