// notification_service.dart — Notifications push (Firebase Cloud Messaging).
//
// But : pouvoir envoyer une notif à TOUS les utilisateurs depuis la console
// Firebase (gratuit, sans serveur), grâce à un abonnement au topic « all ».
//
// PRÉREQUIS (voir les instructions fournies avec ce fichier) :
//   1) flutterfire configure   → génère firebase_options.dart + google-services.json
//   2) pubspec.yaml            → firebase_core, firebase_messaging,
//                                flutter_local_notifications
//   3) main.dart               → Firebase.initializeApp(...) puis
//                                FirebaseMessaging.onBackgroundMessage(...) puis
//                                NotificationService.init()
//   4) AndroidManifest.xml     → permission POST_NOTIFICATIONS + canal par défaut
//
// Rappel : une notif arrive uniquement aux users qui ont installé l'app,
// l'ont ouverte au moins une fois (pour s'abonner) et ont accepté la permission.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handler exécuté quand un message arrive alors que l'app est EN ARRIÈRE-PLAN
/// ou FERMÉE. DOIT être une fonction top-level annotée (isolate séparé).
/// Pour une simple notif « notification » (titre + texte), Android l'affiche
/// automatiquement dans la barre système : rien à faire ici.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // Laisse vide : Android affiche déjà la notif système.
  // (Si un jour tu envoies des messages « data » à traiter, c'est ici.)
}

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// Canal Android (obligatoire depuis Android 8) pour afficher les notifs
  /// quand l'app est au premier plan.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel', // ← DOIT correspondre au manifest (default channel)
    'Notifications importantes',
    description: 'Annonces et rappels de Ing-Licence',
    importance: Importance.high,
  );

  /// À appeler une fois au démarrage (après Firebase.initializeApp).
  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    // 1) Permission (obligatoire sur Android 13+ et iOS).
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // 2) Init du plugin local + création du canal Android.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      settings: const InitializationSettings(android: androidInit),
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // 3) Abonnement au topic « all » → tu envoies à TOUT LE MONDE d'un coup
    //    depuis la console Firebase, en ciblant ce topic.
    await messaging.subscribeToTopic('all');

    // 4) App AU PREMIER PLAN : Android n'affiche pas la notif tout seul,
    //    on la réaffiche nous-mêmes avec le plugin local.
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      _local.show(
        id: n.hashCode,
        title: n.title,
        body: n.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    });
  }
}