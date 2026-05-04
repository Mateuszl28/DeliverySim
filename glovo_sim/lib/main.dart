import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AudioService.instance.init();
  runApp(const GlovoSimApp());
}

/// Singleton wrapper around `audioplayers`. All play calls swallow exceptions —
/// missing assets are a no-op, so the game keeps running even before any audio
/// files are dropped into `assets/audio/`. See `assets/audio/README.md` for the
/// expected filenames.
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  static const _prefsKey = 'sound_on';
  static const int _sfxPoolSize = 6;

  bool _enabled = true;
  bool get enabled => _enabled;

  final List<AudioPlayer> _sfxPool = [];
  int _sfxIdx = 0;
  final Map<String, AudioPlayer> _loops = {};
  final Set<String> _missing = {};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsKey) ?? true;
    for (var i = 0; i < _sfxPoolSize; i++) {
      final p = AudioPlayer();
      try {
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
      } catch (_) {}
      _sfxPool.add(p);
    }
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, v);
    if (!v) await stopAll();
  }

  Future<void> sfx(String asset, {double volume = 1.0}) async {
    if (!_enabled || _missing.contains(asset) || _sfxPool.isEmpty) return;
    final p = _sfxPool[_sfxIdx];
    _sfxIdx = (_sfxIdx + 1) % _sfxPool.length;
    try {
      await p.stop();
      await p.setVolume(volume.clamp(0.0, 1.0));
      await p.play(AssetSource('audio/$asset'));
    } catch (_) {
      _missing.add(asset);
    }
  }

  Future<void> loop(String key, String asset, {double volume = 0.5}) async {
    if (!_enabled) {
      await stopLoop(key);
      return;
    }
    if (_missing.contains(asset)) return;
    var p = _loops[key];
    try {
      if (p == null) {
        p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.loop);
        _loops[key] = p;
      } else {
        await p.stop();
      }
      await p.setVolume(volume.clamp(0.0, 1.0));
      await p.play(AssetSource('audio/$asset'));
    } catch (_) {
      _missing.add(asset);
      await stopLoop(key);
    }
  }

  Future<void> stopLoop(String key) async {
    final p = _loops.remove(key);
    if (p == null) return;
    try {
      await p.stop();
      await p.dispose();
    } catch (_) {}
  }

  Future<void> stopAll() async {
    for (final k in _loops.keys.toList()) {
      await stopLoop(k);
    }
    for (final p in _sfxPool) {
      try { await p.stop(); } catch (_) {}
    }
  }
}

const Color glovoYellow = Color(0xFFFFC244);
const Color glovoDark = Color(0xFF13171F);
const Color glovoCard = Color(0xFF1C2230);
const Color glovoCardLight = Color(0xFF252D3F);
const Color glovoMuted = Color(0xFF8B93A7);
const Color glovoGreen = Color(0xFF2BD17E);
const Color glovoRed = Color(0xFFFF5A5F);
const Color glovoBlue = Color(0xFF4D9DFF);
const Color glovoPurple = Color(0xFF8C5BF0);

class GlovoSimApp extends StatelessWidget {
  const GlovoSimApp({super.key});
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: glovoDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    return MaterialApp(
      title: 'Glovo Courier Sim',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: glovoDark,
        colorScheme: const ColorScheme.dark(
          primary: glovoYellow,
          secondary: glovoYellow,
          surface: glovoCard,
        ),
      ),
      home: const CourierHome(),
    );
  }
}

enum Vehicle {
  bike('Rower', Icons.pedal_bike, 16, 0.0, 4.0),
  scooter('Skuter', Icons.electric_scooter, 28, 0.30, 2.5),
  car('Auto', Icons.directions_car, 35, 0.85, 2.0);

  final String label;
  final IconData icon;
  final double speedKmh;
  final double fuelPerKm;
  final double secPerKm;
  const Vehicle(
      this.label, this.icon, this.speedKmh, this.fuelPerKm, this.secPerKm);
}

enum Weather {
  sunny('Słonecznie', Icons.wb_sunny_rounded, 1.0, glovoYellow),
  cloudy('Pochmurno', Icons.cloud_rounded, 1.0, Color(0xFFBBC4D6)),
  rainy('Deszcz', Icons.umbrella_rounded, 1.25, glovoBlue),
  heavyRain('Ulewa', Icons.thunderstorm_rounded, 1.5, glovoPurple);

  final String label;
  final IconData icon;
  final double bonus;
  final Color color;
  const Weather(this.label, this.icon, this.bonus, this.color);

  bool get isRainy => this == Weather.rainy || this == Weather.heavyRain;
}

enum OrderCategory {
  food('Jedzenie', Icons.restaurant_rounded, glovoYellow),
  grocery('Zakupy', Icons.shopping_cart_rounded, glovoGreen),
  pharmacy('Apteka', Icons.local_pharmacy_rounded, glovoRed),
  anything('Anything', Icons.shopping_bag_rounded, glovoBlue);

  final String label;
  final IconData icon;
  final Color color;
  const OrderCategory(this.label, this.icon, this.color);
}

class Order {
  final OrderCategory category;
  final String partner;
  final String partnerAddress;
  final String customer;
  final String customerAddress;
  final List<String> items;
  final double distanceKm;
  final double basePay;
  final double surge;
  final Weather weatherAtPickup;
  final String pickupCode;
  final int prepSeconds;
  final bool willCancel;
  final bool isRegular;
  double tip;
  int customerStars;

  Order({
    required this.category,
    required this.partner,
    required this.partnerAddress,
    required this.customer,
    required this.customerAddress,
    required this.items,
    required this.distanceKm,
    required this.basePay,
    required this.surge,
    required this.weatherAtPickup,
    required this.pickupCode,
    required this.prepSeconds,
    required this.willCancel,
    this.isRegular = false,
  })  : tip = 0,
        customerStars = 5;

  double get adjustedPay => basePay * surge * weatherAtPickup.bonus;
  double get gross => adjustedPay + tip;
  double get bonusFromSurge => basePay * (surge - 1.0);
  double get bonusFromWeather => basePay * surge * (weatherAtPickup.bonus - 1.0);
}

class CompletedDelivery {
  final OrderCategory category;
  final String partner;
  final String customer;
  final double net;
  final double gross;
  final double tip;
  final int stars;
  final Weather weather;
  final int simHour;
  final double surge;
  final double distanceKm;
  CompletedDelivery({
    required this.category,
    required this.partner,
    required this.customer,
    required this.net,
    required this.gross,
    required this.tip,
    required this.stars,
    required this.weather,
    required this.simHour,
    required this.surge,
    required this.distanceKm,
  });
}

enum GoalKind {
  deliveries('dostaw'),
  earnings('zł netto'),
  fiveStars('ocen 5★'),
  rainDelivery('w deszczu'),
  peakDelivery('w peak'),
  category('w kategorii'),
  bigTip('napiwek 5+ zł');

  final String unit;
  const GoalKind(this.unit);
}

class Goal {
  final GoalKind kind;
  final int target;
  final double reward;
  final OrderCategory? category;
  int progress;
  bool claimed;

  Goal({
    required this.kind,
    required this.target,
    required this.reward,
    this.category,
    this.progress = 0,
    this.claimed = false,
  });

  bool get done => progress >= target;
  double get fraction => (progress / target).clamp(0.0, 1.0);

  String get title {
    switch (kind) {
      case GoalKind.deliveries:
        return 'Wykonaj $target ${target == 1 ? "dostawę" : "dostaw"}';
      case GoalKind.earnings:
        return 'Zarób $target zł netto';
      case GoalKind.fiveStars:
        return 'Zdobądź $target ocen 5★';
      case GoalKind.rainDelivery:
        return 'Dostaw $target ${target == 1 ? "raz" : "razy"} w deszczu';
      case GoalKind.peakDelivery:
        return 'Dostaw $target ${target == 1 ? "raz" : "razy"} w peak';
      case GoalKind.category:
        return 'Dostaw $target z ${category!.label}';
      case GoalKind.bigTip:
        return 'Otrzymaj $target ${target == 1 ? "duży napiwek" : "duże napiwki"} (5+ zł)';
    }
  }

  IconData get icon {
    switch (kind) {
      case GoalKind.deliveries: return Icons.local_shipping_rounded;
      case GoalKind.earnings: return Icons.payments_rounded;
      case GoalKind.fiveStars: return Icons.star_rounded;
      case GoalKind.rainDelivery: return Icons.umbrella_rounded;
      case GoalKind.peakDelivery: return Icons.local_fire_department_rounded;
      case GoalKind.category: return category!.icon;
      case GoalKind.bigTip: return Icons.savings_rounded;
    }
  }
}

enum Zone {
  centrum('Centrum', Icons.location_city_rounded, 1.0, 1.0, 1.0, 1, glovoYellow,
      'Zrównoważona strefa, dużo restauracji'),
  mokotow('Mokotów', Icons.apartment_rounded, 0.85, 1.15, 1.10, 1, glovoBlue,
      'Większe odległości, lepsze stawki'),
  praga('Praga', Icons.holiday_village_rounded, 1.30, 0.85, 0.95, 1, glovoGreen,
      'Dużo zamówień, mniejszy peak'),
  wilanow('Wilanów', Icons.villa_rounded, 0.6, 1.30, 1.30, 5, glovoPurple,
      'VIP — rzadko, ale duże napiwki'),
  lotnisko('Lotnisko', Icons.flight_takeoff_rounded, 0.4, 1.50, 1.50, 10,
      glovoOrange, 'Niska częstość, najwyższe stawki');

  final String label;
  final IconData icon;
  final double demandMul;
  final double payoutMul;
  final double tipMul;
  final int unlockLevel;
  final Color color;
  final String desc;

  const Zone(this.label, this.icon, this.demandMul, this.payoutMul,
      this.tipMul, this.unlockLevel, this.color, this.desc);
}

class GearItem {
  final String id;
  final String name;
  final IconData icon;
  final int price;
  final String desc;
  const GearItem(this.id, this.name, this.icon, this.price, this.desc);
}

const _gearCatalog = [
  GearItem('thermo', 'Termo-torba', Icons.lunch_dining_rounded, 60,
      'Klienci dają 5★ częściej (+8%)'),
  GearItem('raincoat', 'Płaszcz', Icons.umbrella_rounded, 45,
      'Dodatkowe +10% w deszczu'),
  GearItem('rack', 'Lepszy bagażnik', Icons.backpack_rounded, 80,
      '+1 zł bonusu za każdą dostawę'),
  GearItem('gps', 'GPS premium', Icons.gps_fixed_rounded, 70,
      '−15% czasu trasy'),
  GearItem('phone', 'Powerbank XL', Icons.battery_charging_full_rounded, 30,
      'Mniej korków na trasie'),
  GearItem('vip', 'Karta VIP partnerów', Icons.workspace_premium_rounded, 120,
      'Krótszy czas oczekiwania w restauracji'),
];

enum AchievementKind {
  totalDeliveries,
  totalNet,
  fiveStarCount,
  rainDeliveries,
  peakDeliveries,
  bigTipReceived,
  reachLevel,
  allCategories,
  ownAllGear,
  fiveStarStreak,
  loginStreak,
}

class Achievement {
  final String id;
  final String title;
  final String desc;
  final IconData icon;
  final double reward;
  final AchievementKind kind;
  final int threshold;

  const Achievement({
    required this.id,
    required this.title,
    required this.desc,
    required this.icon,
    required this.reward,
    required this.kind,
    required this.threshold,
  });
}

const _achievements = [
  Achievement(
      id: 'first_delivery',
      title: 'Pierwszy raz',
      desc: 'Wykonaj pierwszą dostawę',
      icon: Icons.celebration_rounded,
      reward: 5,
      kind: AchievementKind.totalDeliveries,
      threshold: 1),
  Achievement(
      id: 'ten_deliveries',
      title: 'Dziesiątka',
      desc: 'Wykonaj 10 dostaw',
      icon: Icons.looks_two_rounded,
      reward: 10,
      kind: AchievementKind.totalDeliveries,
      threshold: 10),
  Achievement(
      id: 'fifty_deliveries',
      title: 'Półsetka',
      desc: 'Wykonaj 50 dostaw',
      icon: Icons.local_shipping_rounded,
      reward: 35,
      kind: AchievementKind.totalDeliveries,
      threshold: 50),
  Achievement(
      id: 'hundred_deliveries',
      title: 'Setka',
      desc: 'Wykonaj 100 dostaw',
      icon: Icons.emoji_events_rounded,
      reward: 100,
      kind: AchievementKind.totalDeliveries,
      threshold: 100),
  Achievement(
      id: 'first_500',
      title: 'Pierwsze 500',
      desc: 'Zarób 500 zł netto łącznie',
      icon: Icons.payments_rounded,
      reward: 50,
      kind: AchievementKind.totalNet,
      threshold: 500),
  Achievement(
      id: 'first_5star',
      title: 'Idealny',
      desc: 'Pierwsza ocena 5★',
      icon: Icons.star_rounded,
      reward: 3,
      kind: AchievementKind.fiveStarCount,
      threshold: 1),
  Achievement(
      id: 'master_5star',
      title: 'Mistrz 5★',
      desc: 'Zdobądź 25 ocen 5★',
      icon: Icons.workspace_premium_rounded,
      reward: 30,
      kind: AchievementKind.fiveStarCount,
      threshold: 25),
  Achievement(
      id: 'streak_5star',
      title: 'Bezbłędny',
      desc: '5 ocen 5★ z rzędu',
      icon: Icons.auto_awesome_rounded,
      reward: 25,
      kind: AchievementKind.fiveStarStreak,
      threshold: 5),
  Achievement(
      id: 'rain_warrior',
      title: 'Mokry kurier',
      desc: '10 dostaw w deszczu',
      icon: Icons.umbrella_rounded,
      reward: 20,
      kind: AchievementKind.rainDeliveries,
      threshold: 10),
  Achievement(
      id: 'peak_hunter',
      title: 'Łowca peak',
      desc: '20 dostaw w peak',
      icon: Icons.local_fire_department_rounded,
      reward: 35,
      kind: AchievementKind.peakDeliveries,
      threshold: 20),
  Achievement(
      id: 'big_tipper',
      title: 'Hojny klient',
      desc: 'Otrzymaj napiwek 15+ zł',
      icon: Icons.savings_rounded,
      reward: 15,
      kind: AchievementKind.bigTipReceived,
      threshold: 15),
  Achievement(
      id: 'all_categories',
      title: 'Wszechstronny',
      desc: 'Dostaw z każdej kategorii',
      icon: Icons.category_rounded,
      reward: 20,
      kind: AchievementKind.allCategories,
      threshold: 4),
  Achievement(
      id: 'lvl_5',
      title: 'Doświadczony',
      desc: 'Osiągnij poziom 5',
      icon: Icons.military_tech_rounded,
      reward: 30,
      kind: AchievementKind.reachLevel,
      threshold: 5),
  Achievement(
      id: 'lvl_10',
      title: 'Weteran',
      desc: 'Osiągnij poziom 10',
      icon: Icons.shield_rounded,
      reward: 75,
      kind: AchievementKind.reachLevel,
      threshold: 10),
  Achievement(
      id: 'full_kit',
      title: 'Pełne wyposażenie',
      desc: 'Kup całe wyposażenie',
      icon: Icons.shopping_basket_rounded,
      reward: 100,
      kind: AchievementKind.ownAllGear,
      threshold: 6),
  Achievement(
      id: 'streak_7',
      title: 'Tydzień nieobecności rynkowej',
      desc: 'Loguj się przez 7 dni z rzędu',
      icon: Icons.calendar_view_week_rounded,
      reward: 35,
      kind: AchievementKind.loginStreak,
      threshold: 7),
];

class WeeklyChallenge {
  final String title;
  final IconData icon;
  final int target;
  final double reward;
  int progress;
  bool claimed;

  WeeklyChallenge({
    required this.title,
    required this.icon,
    required this.target,
    required this.reward,
    this.progress = 0,
    this.claimed = false,
  });

  bool get done => progress >= target;
  double get fraction => (progress / target).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'title': title,
        'iconCode': icon.codePoint,
        'iconFamily': icon.fontFamily,
        'target': target,
        'reward': reward,
        'progress': progress,
        'claimed': claimed,
      };

  static WeeklyChallenge fresh(Random rng) {
    final pool = [
      WeeklyChallenge(
          title: 'Wykonaj 25 dostaw',
          icon: Icons.local_shipping_rounded,
          target: 25,
          reward: 60),
      WeeklyChallenge(
          title: 'Zarób 300 zł netto',
          icon: Icons.payments_rounded,
          target: 300,
          reward: 75),
      WeeklyChallenge(
          title: 'Zdobądź 15 ocen 5★',
          icon: Icons.star_rounded,
          target: 15,
          reward: 65),
      WeeklyChallenge(
          title: 'Dostaw 5x w deszczu',
          icon: Icons.umbrella_rounded,
          target: 5,
          reward: 70),
    ];
    return pool[rng.nextInt(pool.length)];
  }
}

class LeaderboardEntry {
  final String name;
  final double weeklyNet;
  final int deliveries;
  final bool isPlayer;
  final int level;
  const LeaderboardEntry({
    required this.name,
    required this.weeklyNet,
    required this.deliveries,
    required this.level,
    this.isPlayer = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'weeklyNet': weeklyNet,
        'deliveries': deliveries,
        'level': level,
      };

  static LeaderboardEntry fromJson(Map<String, dynamic> m) =>
      LeaderboardEntry(
        name: m['name'] as String,
        weeklyNet: (m['weeklyNet'] as num).toDouble(),
        deliveries: m['deliveries'] as int,
        level: m['level'] as int,
      );
}

class Rival {
  final String id;
  final String name;
  final String emoji;
  final int level;
  final String style; // short label
  final double dailyAvg; // expected daily net
  final String taunt;
  const Rival({
    required this.id,
    required this.name,
    required this.emoji,
    required this.level,
    required this.style,
    required this.dailyAvg,
    required this.taunt,
  });
}

const _rivals = [
  Rival(
    id: 'kacper',
    name: 'Kacper "Szybki" M.',
    emoji: '🏍️',
    level: 9,
    style: 'Skuter, peak hours only',
    dailyAvg: 95,
    taunt: 'Spokojnie, zostawię ci paliwa.',
  ),
  Rival(
    id: 'natalia',
    name: 'Natalia "5★" S.',
    emoji: '⭐',
    level: 12,
    style: 'Wilanów / VIP',
    dailyAvg: 130,
    taunt: 'Klienci mnie kochają — sorry.',
  ),
  Rival(
    id: 'bartek',
    name: 'Bartek "Ciężarówa" R.',
    emoji: '🚚',
    level: 14,
    style: 'Auto, zakupy XL',
    dailyAvg: 150,
    taunt: 'Ja wiozę paczki, ty wiozesz pizzę.',
  ),
  Rival(
    id: 'oliwia',
    name: 'Oliwia "GPS" G.',
    emoji: '📍',
    level: 7,
    style: 'Centrum, optymalne trasy',
    dailyAvg: 75,
    taunt: 'Krótszą trasę niż ty znajdę.',
  ),
  Rival(
    id: 'igor',
    name: 'Igor "Rower" F.',
    emoji: '🚲',
    level: 5,
    style: 'Rower, eko-wojownik',
    dailyAvg: 55,
    taunt: 'Bez paliwa = bez kosztów. Czaisz?',
  ),
];

class DailyDuel {
  final String rivalId;
  final double targetNet;
  final String dateKey; // YYYY-MM-DD
  double progressNet;
  bool resolved;

  DailyDuel({
    required this.rivalId,
    required this.targetNet,
    required this.dateKey,
    this.progressNet = 0,
    this.resolved = false,
  });

  Map<String, dynamic> toJson() => {
        'rivalId': rivalId,
        'targetNet': targetNet,
        'dateKey': dateKey,
        'progressNet': progressNet,
        'resolved': resolved,
      };

  static DailyDuel? fromJson(Map<String, dynamic> j) {
    try {
      return DailyDuel(
        rivalId: j['rivalId'] as String,
        targetNet: (j['targetNet'] as num).toDouble(),
        dateKey: j['dateKey'] as String,
        progressNet: (j['progressNet'] as num?)?.toDouble() ?? 0,
        resolved: j['resolved'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

const _ghostNames = [
  'Kacper M.',
  'Aleksandra W.',
  'Bartłomiej R.',
  'Natalia S.',
  'Dawid P.',
  'Wiktoria L.',
  'Filip Z.',
  'Oliwia G.',
  'Mateusz K.',
  'Zuzanna B.',
  'Sebastian H.',
  'Patryk D.',
  'Igor F.',
  'Maja Ż.',
];

enum Season {
  spring('Wiosna', '🌷', Color(0xFF7BC97D)),
  summer('Lato', '☀️', Color(0xFFFFB940)),
  autumn('Jesień', '🍂', Color(0xFFD46B2A)),
  winter('Zima', '❄️', Color(0xFF6BB7E0));

  final String label;
  final String emoji;
  final Color color;
  const Season(this.label, this.emoji, this.color);

  static Season currentForDate(DateTime now) {
    final m = now.month;
    if (m >= 3 && m <= 5) return Season.spring;
    if (m >= 6 && m <= 8) return Season.summer;
    if (m >= 9 && m <= 11) return Season.autumn;
    return Season.winter;
  }
}

class ChatMessage {
  final String from; // "customer" or "courier"
  final String text;
  final int simHour;
  ChatMessage(this.from, this.text, this.simHour);
}

class CareerMission {
  final String id;
  final String chapter;
  final String title;
  final String desc;
  final IconData icon;
  final Color color;
  final double reward;
  final int xpReward;
  final String? unlockZone; // Zone.name to unlock on claim
  final int Function(_CourierHomeState s) progress;
  final int target;
  const CareerMission({
    required this.id,
    required this.chapter,
    required this.title,
    required this.desc,
    required this.icon,
    required this.color,
    required this.reward,
    this.xpReward = 0,
    this.unlockZone,
    required this.progress,
    required this.target,
  });
}

List<CareerMission> _buildCareerMissions() => [
      CareerMission(
        id: 'first_steps',
        chapter: 'Rozdział 1 · Pierwsze kroki',
        title: 'Pierwsze rozdanie',
        desc: 'Dowieź swoje pierwsze 3 zamówienia',
        icon: Icons.local_shipping_rounded,
        color: glovoYellow,
        reward: 20,
        xpReward: 30,
        progress: (s) => s._completed,
        target: 3,
      ),
      CareerMission(
        id: 'first_hundred',
        chapter: 'Rozdział 1 · Pierwsze kroki',
        title: 'Pierwsza dycha (właściwie stówa)',
        desc: 'Zarób 100 zł netto',
        icon: Icons.payments_rounded,
        color: glovoGreen,
        reward: 30,
        xpReward: 30,
        progress: (s) => (s._gross - s._fuelCost).floor().clamp(0, 100),
        target: 100,
      ),
      CareerMission(
        id: 'rookie_run',
        chapter: 'Rozdział 2 · Awans',
        title: 'Robota nogami',
        desc: 'Dowieź 10 zamówień (rozgrzewka)',
        icon: Icons.directions_run_rounded,
        color: glovoBlue,
        reward: 50,
        xpReward: 50,
        progress: (s) => s._completed,
        target: 10,
      ),
      CareerMission(
        id: 'mokotow_unlock',
        chapter: 'Rozdział 3 · Mokotów wita',
        title: 'Otwarcie Mokotów',
        desc: 'Dowieź 25 zamówień, ocena 4.85+',
        icon: Icons.apartment_rounded,
        color: glovoBlue,
        reward: 80,
        xpReward: 80,
        unlockZone: 'mokotow',
        progress: (s) => s._rating >= 4.85 ? s._completed : 0,
        target: 25,
      ),
      CareerMission(
        id: 'cash_flow',
        chapter: 'Rozdział 4 · Pieniądze nie śmierdzą',
        title: 'Pierwsza pięć stów',
        desc: 'Zarób 500 zł netto łącznie',
        icon: Icons.savings_rounded,
        color: glovoGreen,
        reward: 120,
        xpReward: 100,
        progress: (s) => (s._gross - s._fuelCost).floor().clamp(0, 500),
        target: 500,
      ),
      CareerMission(
        id: 'five_star_grind',
        chapter: 'Rozdział 5 · Klient nasz pan',
        title: 'Pięć gwiazdek',
        desc: 'Zbierz 50× ocenę 5★',
        icon: Icons.star_rounded,
        color: glovoYellow,
        reward: 150,
        xpReward: 100,
        progress: (s) => s._fiveStarTotal,
        target: 50,
      ),
      CareerMission(
        id: 'wilanow_unlock',
        chapter: 'Rozdział 6 · VIP w Wilanowie',
        title: 'Wpadka do Wilanowa',
        desc: 'Dowieź 100 zamówień, ocena 4.90+',
        icon: Icons.villa_rounded,
        color: glovoPurple,
        reward: 300,
        xpReward: 150,
        unlockZone: 'wilanow',
        progress: (s) => s._rating >= 4.90 ? s._completed : 0,
        target: 100,
      ),
      CareerMission(
        id: 'big_tipper',
        chapter: 'Rozdział 7 · Kasa w kieszeń',
        title: 'Duży napiwek',
        desc: 'Otrzymaj jeden napiwek 15 zł lub większy',
        icon: Icons.workspace_premium_rounded,
        color: glovoOrange,
        reward: 180,
        xpReward: 80,
        progress: (s) => s._maxTipReceived.floor().clamp(0, 15),
        target: 15,
      ),
      CareerMission(
        id: 'lotnisko_unlock',
        chapter: 'Rozdział 8 · Lotnisko Chopina',
        title: 'Wjazd na pas startowy',
        desc: 'Dowieź 200 zamówień, ocena 4.92+',
        icon: Icons.flight_takeoff_rounded,
        color: glovoOrange,
        reward: 500,
        xpReward: 250,
        unlockZone: 'lotnisko',
        progress: (s) => s._rating >= 4.92 ? s._completed : 0,
        target: 200,
      ),
      CareerMission(
        id: 'top_courier',
        chapter: 'Rozdział 9 · Top kurier dzielnicy',
        title: 'Tytuł Top Kuriera',
        desc: 'Dowieź 365 zamówień (rok pracy)',
        icon: Icons.emoji_events_rounded,
        color: glovoYellow,
        reward: 1000,
        xpReward: 500,
        progress: (s) => s._completed,
        target: 365,
      ),
    ];

enum CityEventKind {
  match('Mecz Legii', '⚽', Color(0xFF2BD17E), 1.55, 1.6),
  concert('Koncert na PGE', '🎤', Color(0xFF8C5BF0), 1.40, 1.45),
  parade('Parada w Centrum', '🎉', Color(0xFFFFC244), 1.30, 1.35),
  marathon('Maraton (zamknięte ulice)', '🏃', Color(0xFF4D9DFF), 1.25, 0.85),
  tradeFair('Targi w EXPO', '🛍️', Color(0xFFFF5A5F), 1.35, 1.30),
  movieShoot('Plan filmowy', '🎬', Color(0xFFE0BBFF), 1.20, 0.75);

  final String label;
  final String emoji;
  final Color color;
  final double surgeBoost; // applied to base surge if event in player's zone
  final double demandMul;  // applied to demand (>1 faster orders, <1 slower)
  const CityEventKind(this.label, this.emoji, this.color,
      this.surgeBoost, this.demandMul);
}

class CityEvent {
  final CityEventKind kind;
  final Zone zone;
  int remainingMin;
  CityEvent({required this.kind, required this.zone, required this.remainingMin});

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'zone': zone.name,
        'remainingMin': remainingMin,
      };

  static CityEvent? fromJson(Map<String, dynamic> j) {
    try {
      return CityEvent(
        kind: CityEventKind.values.firstWhere((k) => k.name == j['kind']),
        zone: Zone.values.firstWhere((z) => z.name == j['zone']),
        remainingMin: (j['remainingMin'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

const Map<String, String> _itemEmojis = {
  'Big Mac': '🍔',
  'Cheeseburger': '🍔',
  'Whopper': '🍔',
  'McNuggets 9 szt.': '🍗',
  'Frytki duże': '🍟',
  'Coca-Cola 0.5L': '🥤',
  'Coca-Cola 2L': '🥤',
  'Pizza Pepperoni': '🍕',
  'Sushi Set 24': '🍣',
  'Pad Thai': '🍜',
  'Kebab XL': '🌯',
  'Lody McFlurry': '🍦',
  'Burrito': '🌯',
  'Sałatka Cezar': '🥗',
  'Tortilla': '🌯',
  'Mleko 1L': '🥛',
  'Chleb pszenny': '🍞',
  'Jajka 10 szt.': '🥚',
  'Banany 1kg': '🍌',
  'Masło 200g': '🧈',
  'Kurczak 1kg': '🍗',
  'Pomidory 1kg': '🍅',
  'Płyn do mycia': '🧴',
  'Papier toaletowy 8 rolek': '🧻',
  'Ser żółty 500g': '🧀',
  'Jogurt 4-pak': '🥛',
  'Marchew 1kg': '🥕',
  'Cebula 1kg': '🧅',
  'Paracetamol 500mg': '💊',
  'Ibuprom MAX': '💊',
  'Witamina D3 4000': '💊',
  'Plastry 20szt': '🩹',
  'Bandaż elastyczny': '🩹',
  'Krople do oczu': '💧',
  'Maseczki FFP2 5szt': '😷',
  'Termometr elektroniczny': '🌡️',
  'Aspiryn C': '💊',
  'Syrop na kaszel': '🧪',
  'Paczka A4 (księgowa)': '📦',
  'Bukiet różowych róż': '🌹',
  'Klucze (przekazanie)': '🔑',
  'Zapomniany laptop': '💻',
  'Kostium na wieczór': '🎭',
  'Prezent niespodzianka': '🎁',
  'Dokumenty firmowe': '📄',
  'Lekarstwo babci': '💊',
  // Seasonal
  'Gorąca czekolada': '☕',
  'Pączek z różą': '🍩',
  'Grzaniec': '🍷',
  'Pierogi ruskie': '🥟',
  'Lody na patyku': '🍦',
  'Mrożona herbata': '🧊',
  'Arbuz 1kg': '🍉',
  'Lemoniada': '🍋',
};

String emojiForItem(String name) {
  return _itemEmojis[name] ?? '🍽️';
}

const _customerMessageTemplates = [
  'Cześć! Mieszkam na 3 piętrze, klatka B, numer 14',
  'Czy może Pan zostawić zamówienie pod drzwiami? Dziecko śpi.',
  'Brama jest otwarta, prosto do windy.',
  'Daleko jeszcze? :)',
  'Proszę zadzwonić domofonem 14',
  'Mam pieska, nie martw się — nie gryzie',
  'Proszę uważać, są schody',
  'Dziękuję, że jedziesz w taką pogodę!',
  'Czy mogę poprosić o dodatkowy ketchup, jeśli zostało?',
];

const _customerQuickReplies = [
  'OK, jasne 👍',
  'Już jadę, 5 min',
  'Niestety nie da rady',
];

enum CourierState {
  offline,
  searching,
  orderIncoming,
  toRestaurant,
  atRestaurantWaiting,
  atRestaurantReady,
  itemsCheck,
  customerCalling,
  takingPhoto,
  orderCancelled,
  toCustomer,
  findingApartment,
  atCustomer,
  ratingPending,
  delivered,
}

class CourierHome extends StatefulWidget {
  const CourierHome({super.key});
  @override
  State<CourierHome> createState() => _CourierHomeState();
}

class _CourierHomeState extends State<CourierHome>
    with TickerProviderStateMixin {
  final Random _rng = Random();
  CourierState _state = CourierState.offline;
  Order? _currentOrder;
  Vehicle _vehicle = Vehicle.scooter;

  Timer? _simTimer;
  Timer? _searchTimer;
  Timer? _orderTimer;
  Timer? _progressTimer;
  Timer? _prepTimer;

  int _simMinutes = 11 * 60;
  Weather _weather = Weather.sunny;
  int _weatherCheckIn = 90;

  int _orderCountdown = 0;
  int _prepCountdown = 0;
  double _routeProgress = 0;
  int _starsRevealed = 0;

  int _completed = 0;
  int _rejected = 0;
  int _cancelled = 0;
  double _gross = 0;
  double _fuelCost = 0;
  double _rating = 4.92;
  int _onlineSeconds = 0;

  int _tabIndex = 0;
  int _level = 1;
  int _xp = 0;
  static const int _xpPerLevel = 120;

  String? _name;
  Zone _zone = Zone.centrum;
  final Set<String> _ownedGear = {};
  WeeklyChallenge? _weekly;
  bool _loaded = false;
  SharedPreferences? _prefs;

  // Achievements
  final Set<String> _unlockedAchievements = {};
  int _fiveStarTotal = 0;
  int _fiveStarStreak = 0;
  int _rainDeliveries = 0;
  int _peakDeliveries = 0;
  double _maxTipReceived = 0;
  final Set<OrderCategory> _categoriesDelivered = {};

  // Daily login streak
  String? _lastLoginDate;
  int _loginStreak = 0;

  // Regular customers
  final Map<String, int> _customerVisits = {};

  // Hourly earnings histogram (0-23)
  final Map<int, double> _hourlyEarnings = {};

  // Weekly leaderboard
  List<LeaderboardEntry> _ghostBoard = [];
  String? _weekStartDate;
  double _weeklyNet = 0;
  int _weeklyDeliveries = 0;

  // Stacked orders
  Order? _stackedOrder;
  int _stackOfferCountdown = 0;
  Timer? _stackOfferTimer;
  bool _stackOfferActive = false;
  Order? _pendingStackOffer;

  // Pickup code entry
  String _enteredCode = '';
  int _wrongCodeAttempts = 0;
  bool _codeShake = false;

  // Items check
  final Set<int> _itemsChecked = {};

  // Route — speedometer + turns + traffic light
  double _currentSpeedKmh = 0;
  String? _currentTurn;
  bool _trafficLightActive = false;
  int _trafficLightSec = 0;

  // Customer arrival sub-state
  int _customerPhase = 0; // 0=knocking, 1=opened, 2=noAnswer, 3=leaveAtDoor

  // Find-apartment mini-game
  List<int> _apartmentDoors = [];
  int _correctApartment = 0;
  int _wrongApartmentTries = 0;
  int _knockCount = 0;
  Timer? _knockTimer;
  Timer? _customerCallTimer;

  // Chat
  final List<ChatMessage> _chat = [];
  bool _chatBadgeUnread = false;
  bool _chatOpen = false;
  bool _chatTriggered = false;
  Timer? _chatScheduleTimer;

  // Tutorial
  bool _tutorialSeen = false;
  int _tutorialPage = 0;

  // Season
  late Season _season;

  final List<CompletedDelivery> _history = [];
  late List<Goal> _goals;
  double _bestTip = 0;
  double _bestNet = 0;

  String? _eventBanner;
  Color _eventColor = glovoBlue;
  Timer? _eventBannerTimer;

  // City events (festyn / mecz / koncert / parada)
  CityEvent? _activeEvent;
  int _eventCheckIn = 25; // sim minutes until next spawn roll

  // Vehicle wear (km counter per vehicle name → km driven since service)
  final Map<String, double> _kmDriven = {};
  bool _breakdownActive = false;

  // Career
  late final List<CareerMission> _career;
  int _careerProgress = 0;
  final Set<String> _careerUnlockedZones = {};

  // Daily duel vs a rival
  DailyDuel? _activeDuel;
  int _duelsWon = 0;
  int _duelsLost = 0;

  // Saved route callback for resuming after a breakdown decision
  VoidCallback? _pendingRouteCallback;

  // Last shift snapshot, captured when ending a shift
  int? _lastShiftDeliveries;
  double? _lastShiftNet;
  int? _lastShiftSeconds;

  late final AnimationController _pulseCtrl;
  late final AnimationController _rainCtrl;

  static const _foodPartners = [
    ('McDonald\'s', 'Marszałkowska 12'),
    ('KFC', 'Świętokrzyska 30'),
    ('Sushi Wok', 'Nowy Świat 44'),
    ('Pasibus', 'Krucza 16'),
    ('Pizza Hut', 'Złota 59'),
    ('Burger King', 'Jana Pawła 21'),
    ('Berlin Döner', 'Bracka 8'),
    ('Thai Wok', 'Hoża 27'),
    ('North Fish', 'Wilcza 50'),
    ('Bobby Burger', 'Mokotowska 11'),
  ];
  static const _groceryPartners = [
    ('Carrefour Express', 'Mokotowska 5'),
    ('Biedronka', 'Wilcza 33'),
    ('Żabka', 'Krucza 47'),
    ('Lidl', 'Solec 36'),
    ('Frisco', 'Puławska 22'),
  ];
  static const _pharmacyPartners = [
    ('Apteka DOZ', 'Marszałkowska 56'),
    ('Apteka Gemini', 'Hoża 9'),
    ('Apteka 24h', 'Złota 88'),
  ];
  static const _anythingPartners = [
    ('Paczkomat InPost', 'Świętokrzyska 12'),
    ('Kwiaciarnia Lila', 'Krucza 6'),
    ('Pralnia 5àSec', 'Złota 44'),
    ('Klucz dorabiany', 'Hoża 18'),
  ];

  static const _customers = [
    ('Anna K.', 'Puławska 102 / 14'),
    ('Marek W.', 'Grójecka 77 / 8'),
    ('Karolina B.', 'Wolska 145 / 22'),
    ('Tomasz Z.', 'Marszałkowska 88 / 5'),
    ('Ewa N.', 'Belwederska 19 / 3'),
    ('Piotr S.', 'al. KEN 36 / 41'),
    ('Julia D.', 'Wawelska 60 / 17'),
    ('Bartek L.', 'Solec 24 / 9'),
    ('Magda R.', 'Czerniakowska 178 / 12'),
  ];

  static const _foodItems = [
    'Big Mac', 'McNuggets 9 szt.', 'Coca-Cola 0.5L', 'Cheeseburger',
    'Frytki duże', 'Pizza Pepperoni', 'Sushi Set 24', 'Pad Thai',
    'Kebab XL', 'Whopper', 'Lody McFlurry', 'Burrito', 'Sałatka Cezar',
  ];
  static const _groceryItems = [
    'Mleko 1L', 'Chleb pszenny', 'Jajka 10 szt.', 'Banany 1kg',
    'Masło 200g', 'Kurczak 1kg', 'Pomidory 1kg', 'Coca-Cola 2L',
    'Płyn do mycia', 'Papier toaletowy 8 rolek', 'Ser żółty 500g',
    'Jogurt 4-pak', 'Marchew 1kg', 'Cebula 1kg',
  ];
  static const _pharmacyItems = [
    'Paracetamol 500mg', 'Ibuprom MAX', 'Witamina D3 4000', 'Plastry 20szt',
    'Bandaż elastyczny', 'Krople do oczu', 'Maseczki FFP2 5szt',
    'Termometr elektroniczny', 'Aspiryn C', 'Syrop na kaszel',
  ];
  static const _anythingItems = [
    'Paczka A4 (księgowa)', 'Bukiet różowych róż', 'Klucze (przekazanie)',
    'Zapomniany laptop', 'Kostium na wieczór', 'Prezent niespodzianka',
    'Dokumenty firmowe', 'Lekarstwo babci',
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _rainCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
    _goals = _generateDailyGoals();
    _season = Season.currentForDate(DateTime.now());
    _career = _buildCareerMissions();
    _loadState();
  }

  CareerMission? get _currentCareerMission =>
      _careerProgress < _career.length ? _career[_careerProgress] : null;

  bool get _careerMissionReady {
    final m = _currentCareerMission;
    if (m == null) return false;
    return m.progress(this) >= m.target;
  }

  void _claimCareerMission() {
    final m = _currentCareerMission;
    if (m == null || !_careerMissionReady) return;
    setState(() {
      _gross += m.reward;
      _xp += m.xpReward;
      while (_xp >= _xpPerLevel) {
        _xp -= _xpPerLevel;
        _level++;
      }
      if (m.unlockZone != null) {
        _careerUnlockedZones.add(m.unlockZone!);
      }
      _careerProgress++;
    });
    HapticFeedback.heavyImpact();
    AudioService.instance.sfx('level_up.mp3');
    final unlockNote = m.unlockZone != null
        ? ' · odblokowano ${Zone.values.firstWhere((z) => z.name == m.unlockZone).label}'
        : '';
    _showEventBanner(
        '🎖️ ${m.title}: +${m.reward.toStringAsFixed(0)} zł$unlockNote',
        m.color);
    _checkAchievements();
    _saveState();
  }

  bool _isZoneUnlocked(Zone z) {
    return _level >= z.unlockLevel || _careerUnlockedZones.contains(z.name);
  }

  Future<void> _loadState() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    setState(() {
      _name = p.getString('name');
      _level = p.getInt('level') ?? 1;
      _xp = p.getInt('xp') ?? 0;
      _completed = p.getInt('completed') ?? 0;
      _rejected = p.getInt('rejected') ?? 0;
      _cancelled = p.getInt('cancelled') ?? 0;
      _gross = p.getDouble('gross') ?? 0;
      _fuelCost = p.getDouble('fuelCost') ?? 0;
      _bestTip = p.getDouble('bestTip') ?? 0;
      _bestNet = p.getDouble('bestNet') ?? 0;
      _rating = p.getDouble('rating') ?? 4.92;
      _onlineSeconds = p.getInt('onlineSeconds') ?? 0;
      final vehicleName = p.getString('vehicle');
      if (vehicleName != null) {
        _vehicle = Vehicle.values.firstWhere(
          (v) => v.name == vehicleName,
          orElse: () => Vehicle.scooter,
        );
      }
      final zoneName = p.getString('zone');
      if (zoneName != null) {
        _zone = Zone.values.firstWhere(
          (z) => z.name == zoneName,
          orElse: () => Zone.centrum,
        );
      }
      _ownedGear.addAll(p.getStringList('gear') ?? []);
      _unlockedAchievements.addAll(p.getStringList('achievements') ?? []);
      _fiveStarTotal = p.getInt('fiveStarTotal') ?? 0;
      _fiveStarStreak = p.getInt('fiveStarStreak') ?? 0;
      _rainDeliveries = p.getInt('rainDeliveries') ?? 0;
      _peakDeliveries = p.getInt('peakDeliveries') ?? 0;
      _maxTipReceived = p.getDouble('maxTipReceived') ?? 0;
      final cats = p.getStringList('catsDelivered') ?? [];
      for (final c in cats) {
        final cat = OrderCategory.values.firstWhere(
          (x) => x.name == c,
          orElse: () => OrderCategory.food,
        );
        _categoriesDelivered.add(cat);
      }
      _lastLoginDate = p.getString('lastLoginDate');
      _loginStreak = p.getInt('loginStreak') ?? 0;
      _tutorialSeen = p.getBool('tutorialSeen') ?? false;

      // Regular customers
      final visitsJson = p.getString('customerVisits');
      if (visitsJson != null) {
        final m = jsonDecode(visitsJson) as Map<String, dynamic>;
        m.forEach((k, v) => _customerVisits[k] = v as int);
      }

      // Hourly earnings
      final hourlyJson = p.getString('hourlyEarnings');
      if (hourlyJson != null) {
        final m = jsonDecode(hourlyJson) as Map<String, dynamic>;
        m.forEach((k, v) =>
            _hourlyEarnings[int.parse(k)] = (v as num).toDouble());
      }

      // Weekly leaderboard
      _weekStartDate = p.getString('weekStartDate');
      _weeklyNet = p.getDouble('weeklyNet') ?? 0;
      _weeklyDeliveries = p.getInt('weeklyDeliveries') ?? 0;
      final boardJson = p.getString('ghostBoard');
      if (boardJson != null) {
        final list = jsonDecode(boardJson) as List;
        _ghostBoard = list
            .map((e) =>
                LeaderboardEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      final kmJson = p.getString('kmDriven');
      if (kmJson != null) {
        final m = jsonDecode(kmJson) as Map<String, dynamic>;
        m.forEach((k, v) => _kmDriven[k] = (v as num).toDouble());
      }

      final eventJson = p.getString('activeEvent');
      if (eventJson != null) {
        _activeEvent = CityEvent.fromJson(
            jsonDecode(eventJson) as Map<String, dynamic>);
      }

      _careerProgress = p.getInt('careerProgress') ?? 0;
      _careerUnlockedZones
          .addAll(p.getStringList('careerUnlockedZones') ?? []);

      final weeklyJson = p.getString('weekly');
      if (weeklyJson != null) {
        final m = jsonDecode(weeklyJson) as Map<String, dynamic>;
        _weekly = WeeklyChallenge(
          title: m['title'] as String,
          icon: IconData(m['iconCode'] as int,
              fontFamily: m['iconFamily'] as String?),
          target: m['target'] as int,
          reward: (m['reward'] as num).toDouble(),
          progress: m['progress'] as int? ?? 0,
          claimed: m['claimed'] as bool? ?? false,
        );
      } else {
        _weekly = WeeklyChallenge.fresh(_rng);
      }

      _loaded = true;
    });
    if (_name != null) _checkDailyLogin();
    _checkWeekReset();
  }

  String _currentWeekKey() {
    final now = DateTime.now();
    // ISO week-ish: year-week (use day-of-year / 7 approximation)
    final dayOfYear =
        now.difference(DateTime(now.year, 1, 1)).inDays + 1;
    final week = (dayOfYear / 7).ceil();
    return '${now.year}-W$week';
  }

  void _checkWeekReset() {
    final current = _currentWeekKey();
    if (_weekStartDate == current && _ghostBoard.isNotEmpty) return;
    setState(() {
      _weekStartDate = current;
      _weeklyNet = 0;
      _weeklyDeliveries = 0;
      _ghostBoard = _generateGhostBoard();
    });
    _saveState();
    if (_name != null) {
      _showEventBanner('Nowy tydzień — leaderboard zresetowany', glovoBlue);
    }
  }

  List<LeaderboardEntry> _generateGhostBoard() {
    final names = List<String>.from(_ghostNames);
    names.shuffle(_rng);
    return names.take(9).map((n) {
      final earnings = 60 + _rng.nextDouble() * 280;
      final deliveries = 8 + _rng.nextInt(40);
      final lvl = 1 + _rng.nextInt(12);
      return LeaderboardEntry(
        name: n,
        weeklyNet: double.parse(earnings.toStringAsFixed(2)),
        deliveries: deliveries,
        level: lvl,
      );
    }).toList();
  }

  Future<void> _saveState() async {
    final p = _prefs;
    if (p == null) return;
    if (_name != null) await p.setString('name', _name!);
    await p.setInt('level', _level);
    await p.setInt('xp', _xp);
    await p.setInt('completed', _completed);
    await p.setInt('rejected', _rejected);
    await p.setInt('cancelled', _cancelled);
    await p.setDouble('gross', _gross);
    await p.setDouble('fuelCost', _fuelCost);
    await p.setDouble('bestTip', _bestTip);
    await p.setDouble('bestNet', _bestNet);
    await p.setDouble('rating', _rating);
    await p.setInt('onlineSeconds', _onlineSeconds);
    await p.setString('vehicle', _vehicle.name);
    await p.setString('zone', _zone.name);
    await p.setStringList('gear', _ownedGear.toList());
    await p.setStringList('achievements', _unlockedAchievements.toList());
    await p.setInt('fiveStarTotal', _fiveStarTotal);
    await p.setInt('fiveStarStreak', _fiveStarStreak);
    await p.setInt('rainDeliveries', _rainDeliveries);
    await p.setInt('peakDeliveries', _peakDeliveries);
    await p.setDouble('maxTipReceived', _maxTipReceived);
    await p.setStringList('catsDelivered',
        _categoriesDelivered.map((c) => c.name).toList());
    if (_lastLoginDate != null) {
      await p.setString('lastLoginDate', _lastLoginDate!);
    }
    await p.setInt('loginStreak', _loginStreak);
    await p.setBool('tutorialSeen', _tutorialSeen);
    await p.setString('customerVisits', jsonEncode(_customerVisits));
    await p.setString(
        'hourlyEarnings',
        jsonEncode(
            _hourlyEarnings.map((k, v) => MapEntry(k.toString(), v))));
    if (_weekStartDate != null) {
      await p.setString('weekStartDate', _weekStartDate!);
    }
    await p.setDouble('weeklyNet', _weeklyNet);
    await p.setInt('weeklyDeliveries', _weeklyDeliveries);
    if (_ghostBoard.isNotEmpty) {
      await p.setString(
          'ghostBoard', jsonEncode(_ghostBoard.map((e) => e.toJson()).toList()));
    }
    if (_weekly != null) {
      await p.setString('weekly', jsonEncode(_weekly!.toJson()));
    }
    await p.setString('kmDriven', jsonEncode(_kmDriven));
    if (_activeEvent != null) {
      await p.setString('activeEvent', jsonEncode(_activeEvent!.toJson()));
    } else {
      await p.remove('activeEvent');
    }
    await p.setInt('careerProgress', _careerProgress);
    await p.setStringList(
        'careerUnlockedZones', _careerUnlockedZones.toList());
  }

  Future<void> _resetProgress() async {
    final p = _prefs;
    if (p != null) await p.clear();
    setState(() {
      _name = null;
      _level = 1;
      _xp = 0;
      _completed = 0;
      _rejected = 0;
      _cancelled = 0;
      _gross = 0;
      _fuelCost = 0;
      _bestTip = 0;
      _bestNet = 0;
      _rating = 4.92;
      _onlineSeconds = 0;
      _ownedGear.clear();
      _unlockedAchievements.clear();
      _categoriesDelivered.clear();
      _fiveStarTotal = 0;
      _fiveStarStreak = 0;
      _rainDeliveries = 0;
      _peakDeliveries = 0;
      _maxTipReceived = 0;
      _lastLoginDate = null;
      _loginStreak = 0;
      _tutorialSeen = false;
      _customerVisits.clear();
      _hourlyEarnings.clear();
      _ghostBoard = [];
      _weekStartDate = null;
      _weeklyNet = 0;
      _weeklyDeliveries = 0;
      _kmDriven.clear();
      _activeEvent = null;
      _breakdownActive = false;
      _careerProgress = 0;
      _careerUnlockedZones.clear();
      _history.clear();
      _stackedOrder = null;
      _pendingStackOffer = null;
      _stackOfferActive = false;
      _zone = Zone.centrum;
      _vehicle = Vehicle.scooter;
      _weekly = WeeklyChallenge.fresh(_rng);
      _goals = _generateDailyGoals();
      _tabIndex = 0;
    });
  }

  List<Goal> _generateDailyGoals() {
    final pool = <Goal>[
      Goal(kind: GoalKind.deliveries, target: 3, reward: 6),
      Goal(kind: GoalKind.deliveries, target: 5, reward: 10),
      Goal(kind: GoalKind.earnings, target: 30, reward: 5),
      Goal(kind: GoalKind.earnings, target: 75, reward: 12),
      Goal(kind: GoalKind.fiveStars, target: 3, reward: 5),
      Goal(kind: GoalKind.rainDelivery, target: 1, reward: 4),
      Goal(kind: GoalKind.peakDelivery, target: 2, reward: 6),
      Goal(kind: GoalKind.bigTip, target: 1, reward: 5),
      Goal(kind: GoalKind.category, target: 2, reward: 5,
          category: OrderCategory.grocery),
      Goal(kind: GoalKind.category, target: 1, reward: 4,
          category: OrderCategory.pharmacy),
    ];
    pool.shuffle(_rng);
    return pool.take(3).toList();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rainCtrl.dispose();
    _simTimer?.cancel();
    _searchTimer?.cancel();
    _orderTimer?.cancel();
    _progressTimer?.cancel();
    _prepTimer?.cancel();
    _eventBannerTimer?.cancel();
    _stackOfferTimer?.cancel();
    _knockTimer?.cancel();
    _customerCallTimer?.cancel();
    _chatScheduleTimer?.cancel();
    AudioService.instance.stopAll();
    super.dispose();
  }

  // ===== SIM TIME / WEATHER / SURGE =====

  int get _simHour => (_simMinutes ~/ 60) % 24;

  String get _simClock {
    final h = _simHour;
    final m = _simMinutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  double get _surgeMultiplier {
    final h = _simHour;
    double s = 1.0;
    if (h >= 11 && h < 14) s = 1.5;
    else if (h >= 18 && h < 22) s = 1.6;
    else if (h >= 14 && h < 17) s = 1.1;
    else if (h >= 22 || h < 7) s = 0.9;
    if (_weather == Weather.heavyRain) s += 0.3;
    else if (_weather == Weather.rainy) s += 0.15;
    final ev = _activeEvent;
    if (ev != null && ev.zone == _zone) s *= ev.kind.surgeBoost;
    return double.parse(s.toStringAsFixed(2));
  }

  bool get _isPeak => _surgeMultiplier >= 1.4;

  int _baseDelaySec() {
    final h = _simHour;
    double base;
    if (h >= 11 && h < 14) base = 4;
    else if (h >= 18 && h < 22) base = 4;
    else if (h >= 14 && h < 17) base = 7;
    else if (h >= 22 || h < 7) base = 18;
    else if (h >= 7 && h < 11) base = 9;
    else base = 8;
    if (_weather == Weather.rainy) base *= 0.75;
    if (_weather == Weather.heavyRain) base *= 0.6;
    base /= _zone.demandMul;
    final ev = _activeEvent;
    if (ev != null && ev.zone == _zone) base /= ev.kind.demandMul;
    return max(2, base.round());
  }

  void _startSimClock() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {
        _simMinutes = (_simMinutes + 1) % 1440;
        _onlineSeconds++;
        _weatherCheckIn--;
        if (_weatherCheckIn <= 0) {
          _maybeChangeWeather();
          _weatherCheckIn = 60 + _rng.nextInt(120);
        }
        _tickCityEvent();
      });
    });
  }

  // ===== CITY EVENTS =====
  void _tickCityEvent() {
    final ev = _activeEvent;
    if (ev != null) {
      ev.remainingMin--;
      if (ev.remainingMin <= 0) {
        final endedZone = ev.zone;
        _activeEvent = null;
        _eventCheckIn = 30 + _rng.nextInt(90);
        _showEventBanner(
            'Wydarzenie się skończyło (${endedZone.label})', glovoMuted);
        _saveState();
      }
      return;
    }
    _eventCheckIn--;
    if (_eventCheckIn > 0) return;
    _eventCheckIn = 60 + _rng.nextInt(180);
    if (_rng.nextDouble() > 0.45) return; // 45% to actually fire
    _spawnCityEvent();
  }

  void _spawnCityEvent() {
    final kinds = CityEventKind.values;
    final kind = kinds[_rng.nextInt(kinds.length)];
    // 60% in player's zone, 40% somewhere else
    final useOwn = _rng.nextDouble() < 0.6;
    final pool = useOwn
        ? <Zone>[_zone]
        : Zone.values.where((z) => z != _zone).toList();
    final zone = pool[_rng.nextInt(pool.length)];
    final dur = 60 + _rng.nextInt(120); // 60-180 sim min
    _activeEvent = CityEvent(kind: kind, zone: zone, remainingMin: dur);
    final inMyZone = zone == _zone;
    final boostStr = '${((kind.surgeBoost - 1) * 100).round()}%';
    final demandStr = kind.demandMul >= 1
        ? '+${((kind.demandMul - 1) * 100).round()}% zamówień'
        : '−${((1 - kind.demandMul) * 100).round()}% zamówień';
    final msg = inMyZone
        ? '${kind.emoji} ${kind.label} — surge +$boostStr, $demandStr'
        : '${kind.emoji} ${kind.label} w ${zone.label} — przejedź się!';
    _showEventBanner(msg, kind.color);
    AudioService.instance.sfx('chat_ding.mp3', volume: 0.5);
    _saveState();
  }

  void _maybeChangeWeather() {
    final r = _rng.nextDouble();
    Map<Weather, List<(Weather, double)>> base;
    switch (_season) {
      case Season.summer:
        base = {
          Weather.sunny: [
            (Weather.sunny, 0.7),
            (Weather.cloudy, 0.27),
            (Weather.rainy, 0.03),
          ],
          Weather.cloudy: [
            (Weather.sunny, 0.55),
            (Weather.cloudy, 0.35),
            (Weather.rainy, 0.10),
          ],
          Weather.rainy: [
            (Weather.cloudy, 0.55),
            (Weather.sunny, 0.30),
            (Weather.rainy, 0.15),
          ],
          Weather.heavyRain: [
            (Weather.rainy, 0.55),
            (Weather.cloudy, 0.40),
            (Weather.heavyRain, 0.05),
          ],
        };
      case Season.winter:
        base = {
          Weather.sunny: [
            (Weather.cloudy, 0.5),
            (Weather.sunny, 0.35),
            (Weather.rainy, 0.15),
          ],
          Weather.cloudy: [
            (Weather.sunny, 0.15),
            (Weather.cloudy, 0.35),
            (Weather.rainy, 0.40),
            (Weather.heavyRain, 0.10),
          ],
          Weather.rainy: [
            (Weather.cloudy, 0.30),
            (Weather.rainy, 0.40),
            (Weather.heavyRain, 0.30),
          ],
          Weather.heavyRain: [
            (Weather.rainy, 0.50),
            (Weather.heavyRain, 0.30),
            (Weather.cloudy, 0.20),
          ],
        };
      case Season.autumn:
        base = {
          Weather.sunny: [
            (Weather.sunny, 0.30),
            (Weather.cloudy, 0.55),
            (Weather.rainy, 0.15),
          ],
          Weather.cloudy: [
            (Weather.sunny, 0.20),
            (Weather.cloudy, 0.40),
            (Weather.rainy, 0.35),
            (Weather.heavyRain, 0.05),
          ],
          Weather.rainy: [
            (Weather.cloudy, 0.50),
            (Weather.rainy, 0.30),
            (Weather.heavyRain, 0.15),
            (Weather.sunny, 0.05),
          ],
          Weather.heavyRain: [
            (Weather.rainy, 0.6),
            (Weather.cloudy, 0.3),
            (Weather.heavyRain, 0.1),
          ],
        };
      case Season.spring:
        base = {
          Weather.sunny: [
            (Weather.sunny, 0.5),
            (Weather.cloudy, 0.40),
            (Weather.rainy, 0.10),
          ],
          Weather.cloudy: [
            (Weather.sunny, 0.4),
            (Weather.cloudy, 0.35),
            (Weather.rainy, 0.25),
          ],
          Weather.rainy: [
            (Weather.cloudy, 0.5),
            (Weather.rainy, 0.3),
            (Weather.heavyRain, 0.15),
            (Weather.sunny, 0.05),
          ],
          Weather.heavyRain: [
            (Weather.rainy, 0.6),
            (Weather.cloudy, 0.3),
            (Weather.heavyRain, 0.1),
          ],
        };
    }
    final list = base[_weather]!;
    double acc = 0;
    for (final (w, p) in list) {
      acc += p;
      if (r <= acc) {
        if (w != _weather) {
          _toast('Zmiana pogody: ${w.label}', w.color);
        }
        _weather = w;
        return;
      }
    }
  }

  List<String> _seasonalItemsFor(OrderCategory cat) {
    switch (cat) {
      case OrderCategory.food:
        switch (_season) {
          case Season.winter:
            return ['Gorąca czekolada', 'Pierogi ruskie', 'Grzaniec'];
          case Season.summer:
            return ['Lody na patyku', 'Mrożona herbata', 'Lemoniada'];
          case Season.autumn:
            return ['Pączek z różą', 'Gorąca czekolada'];
          case Season.spring:
            return ['Lemoniada', 'Pączek z różą'];
        }
      case OrderCategory.grocery:
        if (_season == Season.summer) return ['Arbuz 1kg', 'Lemoniada'];
        return [];
      default:
        return [];
    }
  }

  // ===== SHIFT MANAGEMENT =====

  void _toggleOnline() {
    if (_state == CourierState.offline) {
      _showVehiclePicker();
    } else {
      _stopShift();
    }
  }

  void _stopShift() {
    final shiftDeliveries = _completed - (_lastShiftDeliveries ?? 0);
    final shiftNet = (_gross - _fuelCost) -
        ((_lastShiftNet ?? 0));
    final shiftSeconds = _onlineSeconds - (_lastShiftSeconds ?? 0);
    _lastShiftDeliveries = _completed;
    _lastShiftNet = _gross - _fuelCost;
    _lastShiftSeconds = _onlineSeconds;
    _resetTimers();
    AudioService.instance.stopAll();
    setState(() {
      _state = CourierState.offline;
      _currentOrder = null;
      _routeProgress = 0;
    });
    if (shiftDeliveries > 0) {
      _showShiftSummary(shiftDeliveries, shiftNet, shiftSeconds);
    }
    _saveState();
  }

  void _resetTimers() {
    _simTimer?.cancel();
    _searchTimer?.cancel();
    _orderTimer?.cancel();
    _progressTimer?.cancel();
    _prepTimer?.cancel();
  }

  void _showVehiclePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: glovoCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: glovoMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Wybierz pojazd na zmianę',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Wpływa na czas dostawy i koszt paliwa',
                style: TextStyle(color: glovoMuted, fontSize: 12)),
            const SizedBox(height: 20),
            ...Vehicle.values.map((v) => _vehicleCard(v, ctx)),
          ],
        ),
      ),
    );
  }

  Widget _vehicleCard(Vehicle v, BuildContext ctx) {
    final selected = v == _vehicle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.pop(ctx);
          setState(() {
            _vehicle = v;
            _state = CourierState.searching;
          });
          AudioService.instance.loop('ambient', 'ambient_city.mp3', volume: 0.18);
          _startSimClock();
          _scheduleNextOrder();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: glovoCardLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? glovoYellow : Colors.transparent, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: glovoYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(v.icon, color: glovoYellow, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                        '${v.speedKmh.toInt()} km/h · ${v.fuelPerKm == 0 ? 'bez paliwa' : '${v.fuelPerKm.toStringAsFixed(2)} zł/km'}',
                        style: const TextStyle(
                            color: glovoMuted, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: glovoMuted),
            ],
          ),
        ),
      ),
    );
  }

  // ===== ORDER LIFECYCLE =====

  void _scheduleNextOrder() {
    _searchTimer?.cancel();
    final base = _baseDelaySec();
    final delay = max(2, base + _rng.nextInt(4) - 1);
    _searchTimer = Timer(Duration(seconds: delay), () {
      if (!mounted) return;
      if (_state != CourierState.searching) return;
      _spawnOrder();
    });
  }

  void _spawnOrder() {
    final categories = [
      OrderCategory.food, OrderCategory.food, OrderCategory.food,
      OrderCategory.grocery, OrderCategory.grocery,
      OrderCategory.pharmacy, OrderCategory.anything,
    ];
    final cat = categories[_rng.nextInt(categories.length)];

    late (String, String) partner;
    late List<String> pool;
    int itemCountMax;
    switch (cat) {
      case OrderCategory.food:
        partner = _foodPartners[_rng.nextInt(_foodPartners.length)];
        pool = _foodItems;
        itemCountMax = 4;
      case OrderCategory.grocery:
        partner = _groceryPartners[_rng.nextInt(_groceryPartners.length)];
        pool = _groceryItems;
        itemCountMax = 8;
      case OrderCategory.pharmacy:
        partner = _pharmacyPartners[_rng.nextInt(_pharmacyPartners.length)];
        pool = _pharmacyItems;
        itemCountMax = 3;
      case OrderCategory.anything:
        partner = _anythingPartners[_rng.nextInt(_anythingPartners.length)];
        pool = _anythingItems;
        itemCountMax = 1;
    }
    final c = _customers[_rng.nextInt(_customers.length)];
    final isRegular = (_customerVisits[c.$1] ?? 0) >= 3;
    final itemsCount = 1 + _rng.nextInt(itemCountMax);
    final seasonalPool = _seasonalItemsFor(cat);
    final fullPool = [...pool, ...seasonalPool, ...seasonalPool]; // boost seasonal weight
    final items = <String>[];
    for (var i = 0; i < itemsCount; i++) {
      items.add(fullPool[_rng.nextInt(fullPool.length)]);
    }
    final dist = 0.6 + _rng.nextDouble() * 3.4;
    var basePay = 5.50 + dist * 2.10 + _rng.nextDouble() * 1.5;
    basePay *= _zone.payoutMul;
    if (_ownedGear.contains('rack')) basePay += 1.0;
    if (_weather.isRainy && _ownedGear.contains('raincoat')) {
      basePay *= 1.10;
    }
    final code = (1000 + _rng.nextInt(8999)).toString();
    var prep = cat == OrderCategory.food
        ? 4 + _rng.nextInt(7)
        : cat == OrderCategory.grocery
            ? 3 + _rng.nextInt(5)
            : 2 + _rng.nextInt(4);
    if (_ownedGear.contains('vip')) prep = (prep * 0.7).ceil();
    final willCancel = !isRegular && _rng.nextDouble() < 0.06;

    setState(() {
      _currentOrder = Order(
        category: cat,
        partner: partner.$1,
        partnerAddress: 'ul. ${partner.$2}',
        customer: c.$1,
        customerAddress: 'ul. ${c.$2}',
        items: items,
        distanceKm: double.parse(dist.toStringAsFixed(1)),
        basePay: double.parse(basePay.toStringAsFixed(2)),
        surge: _surgeMultiplier,
        weatherAtPickup: _weather,
        pickupCode: code,
        prepSeconds: prep,
        willCancel: willCancel,
        isRegular: isRegular,
      );
      _state = CourierState.orderIncoming;
      _orderCountdown = 15;
    });
    HapticFeedback.heavyImpact();
    AudioService.instance.sfx('order_incoming.mp3');

    _orderTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_state != CourierState.orderIncoming) {
        t.cancel();
        return;
      }
      setState(() => _orderCountdown--);
      if (_orderCountdown <= 0) {
        t.cancel();
        _rejectOrder(timedOut: true);
      }
    });
  }

  void _acceptOrder() {
    _orderTimer?.cancel();
    HapticFeedback.mediumImpact();
    AudioService.instance.sfx('button_tap.mp3', volume: 0.6);
    setState(() {
      _state = CourierState.toRestaurant;
      _routeProgress = 0;
    });
    _runRoute(onComplete: _onArriveAtRestaurant);
  }

  void _rejectOrder({bool timedOut = false}) {
    _orderTimer?.cancel();
    setState(() {
      _rejected++;
      _rating = max(4.20, _rating - (timedOut ? 0.05 : 0.02));
      _currentOrder = null;
      _state = CourierState.searching;
    });
    if (timedOut) _toast('Zamówienie wygasło — ocena spada', glovoRed);
    _scheduleNextOrder();
  }

  void _onArriveAtRestaurant() {
    if (!mounted) return;
    final o = _currentOrder!;
    setState(() {
      _state = CourierState.atRestaurantWaiting;
      _prepCountdown = o.prepSeconds;
    });
    _prepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_state != CourierState.atRestaurantWaiting) {
        t.cancel();
        return;
      }
      setState(() => _prepCountdown--);
      if (_prepCountdown <= 0) {
        t.cancel();
        if (o.willCancel) {
          _onRestaurantCancel();
        } else {
          setState(() => _state = CourierState.atRestaurantReady);
        }
      }
    });
  }

  void _onRestaurantCancel() {
    if (!mounted) return;
    const compensation = 5.0;
    setState(() {
      _cancelled++;
      _gross += compensation;
      _state = CourierState.orderCancelled;
    });
    _toast('Restauracja anulowała — rekompensata +5 zł', glovoOrange);
    Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() {
        _currentOrder = null;
        _state = CourierState.searching;
      });
      _scheduleNextOrder();
    });
  }

  // ===== KEYPAD =====
  void _typeKey(String d) {
    if (_enteredCode.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() => _enteredCode += d);
    if (_enteredCode.length == 4) {
      final correct = _currentOrder?.pickupCode == _enteredCode;
      if (correct) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.click);
        Timer(const Duration(milliseconds: 350), () {
          if (!mounted) return;
          setState(() {
            _state = CourierState.itemsCheck;
            _enteredCode = '';
            _wrongCodeAttempts = 0;
            _itemsChecked.clear();
          });
        });
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _codeShake = true;
          _wrongCodeAttempts++;
        });
        Timer(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          setState(() {
            _enteredCode = '';
            _codeShake = false;
          });
        });
        _toast('Niepoprawny kod', glovoRed);
      }
    }
  }

  void _backspaceKey() {
    if (_enteredCode.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() =>
        _enteredCode = _enteredCode.substring(0, _enteredCode.length - 1));
  }

  // ===== ITEMS CHECK =====
  void _toggleItem(int idx) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_itemsChecked.contains(idx)) {
        _itemsChecked.remove(idx);
      } else {
        _itemsChecked.add(idx);
      }
    });
  }

  void _confirmItemsAndDrive() {
    HapticFeedback.mediumImpact();
    AudioService.instance.sfx('button_tap.mp3', volume: 0.6);
    setState(() {
      _state = CourierState.toCustomer;
      _routeProgress = 0;
      _itemsChecked.clear();
      _chat.clear();
      _chatTriggered = false;
      _chatBadgeUnread = false;
      _chatOpen = false;
    });
    _runRoute(onComplete: _onArriveAtCustomer);
  }

  void _customerSendsMessage() {
    final msg = _customerMessageTemplates[
        _rng.nextInt(_customerMessageTemplates.length)];
    setState(() {
      _chat.add(ChatMessage('customer', msg, _simHour));
      if (!_chatOpen) _chatBadgeUnread = true;
    });
    HapticFeedback.mediumImpact();
    AudioService.instance.sfx('chat_ding.mp3', volume: 0.7);
    if (!_chatOpen) {
      _showEventBanner('${_currentOrder?.customer ?? "Klient"}: nowa wiadomość',
          glovoBlue);
    }
  }

  void _courierReply(String text) {
    setState(() {
      _chat.add(ChatMessage('courier', text, _simHour));
    });
    HapticFeedback.lightImpact();
  }

  void _toggleChat() {
    setState(() {
      _chatOpen = !_chatOpen;
      if (_chatOpen) _chatBadgeUnread = false;
    });
  }

  // ===== CUSTOMER ARRIVAL =====
  void _onArriveAtCustomer() {
    if (!mounted) return;
    // Mini-game: find the right apartment
    final correct = 1 + _rng.nextInt(48);
    final doors = <int>{correct};
    while (doors.length < 8) {
      var n = (correct + _rng.nextInt(20) - 10).clamp(1, 60);
      // ensure variety, never duplicate
      if (n == correct && doors.length < 7) n = (n + 1).clamp(1, 60);
      doors.add(n);
    }
    final shuffled = doors.toList()..shuffle(_rng);
    setState(() {
      _state = CourierState.findingApartment;
      _apartmentDoors = shuffled;
      _correctApartment = correct;
      _wrongApartmentTries = 0;
    });
    HapticFeedback.mediumImpact();
  }

  void _pickApartment(int n) {
    if (n == _correctApartment) {
      AudioService.instance.sfx('button_tap.mp3', volume: 0.5);
      HapticFeedback.lightImpact();
      _enterCustomerKnocking();
    } else {
      setState(() => _wrongApartmentTries++);
      HapticFeedback.heavyImpact();
      AudioService.instance.sfx('phone_ring.mp3', volume: 0.4);
      if (_wrongApartmentTries >= 3) {
        // Player gives up — slight rating penalty for poor service
        setState(() => _rating = max(4.20, _rating - 0.03));
        _showEventBanner('Tracisz czas — klient niezadowolony', glovoOrange);
        _enterCustomerKnocking();
      } else {
        _showEventBanner('Złe drzwi (${3 - _wrongApartmentTries} próby)',
            glovoRed);
      }
    }
  }

  void _enterCustomerKnocking() {
    setState(() {
      _state = CourierState.atCustomer;
      _customerPhase = 0;
      _knockCount = 0;
    });
    HapticFeedback.mediumImpact();
    _knockTimer?.cancel();
    // 3 knocks, then resolve outcome
    _knockTimer = Timer.periodic(const Duration(milliseconds: 700), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_state != CourierState.atCustomer || _customerPhase != 0) {
        t.cancel();
        return;
      }
      setState(() => _knockCount++);
      HapticFeedback.lightImpact();
      AudioService.instance.sfx('knock.mp3');
      if (_knockCount >= 3) {
        t.cancel();
        _resolveCustomerOutcome();
      }
    });
  }

  void _resolveCustomerOutcome() {
    final r = _rng.nextDouble();
    int outcome;
    final o = _currentOrder!;
    if (o.isRegular) {
      // Regular customers always answer
      outcome = 1;
    } else if (r < 0.70) {
      outcome = 1; // opens
    } else if (r < 0.90) {
      outcome = 2; // no answer → call
    } else {
      outcome = 3; // leave at door
    }
    if (outcome == 2) {
      // Phone call
      setState(() {
        _state = CourierState.customerCalling;
      });
      HapticFeedback.mediumImpact();
      AudioService.instance.sfx('phone_ring.mp3', volume: 0.8);
      _customerCallTimer = Timer(const Duration(milliseconds: 3500), () {
        if (!mounted) return;
        // 50% answers after call, 50% asks to leave at door
        final answered = _rng.nextDouble() < 0.5;
        setState(() {
          _state = CourierState.atCustomer;
          _customerPhase = answered ? 1 : 3;
        });
        if (!answered) {
          _showEventBanner('${_currentOrder?.customer ?? "Klient"}: '
              '"Zostaw pod drzwiami, dziękuję!"', glovoBlue);
        }
      });
    } else {
      setState(() {
        _customerPhase = outcome;
      });
      if (outcome == 3) {
        _showEventBanner('Instrukcja: zostaw zamówienie pod drzwiami', glovoBlue);
      }
    }
  }

  void _handOver() {
    HapticFeedback.mediumImpact();
    setState(() => _state = CourierState.takingPhoto);
  }

  void _confirmPhoto() {
    final o = _currentOrder!;
    o.tip = _rollTip(o);
    o.customerStars = _rollCustomerStars(o);
    HapticFeedback.heavyImpact();
    AudioService.instance.sfx('camera_shutter.mp3');
    setState(() {
      _state = CourierState.ratingPending;
      _starsRevealed = 0;
    });
    Timer.periodic(const Duration(milliseconds: 350), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_starsRevealed >= o.customerStars) {
        t.cancel();
        Timer(const Duration(milliseconds: 700), () {
          if (!mounted) return;
          _finalizeDelivery();
        });
        return;
      }
      setState(() => _starsRevealed++);
    });
  }

  double _rollTip(Order o) {
    final r = _rng.nextDouble();
    double tip;
    if (r < 0.50) tip = 0;
    else if (r < 0.80) tip = 1 + _rng.nextDouble() * 2;
    else if (r < 0.95) tip = 3 + _rng.nextDouble() * 4;
    else tip = 7 + _rng.nextDouble() * 8;
    tip *= _zone.tipMul;
    if (o.isRegular) tip *= 1.5;
    return double.parse(tip.toStringAsFixed(2));
  }

  int _rollCustomerStars(Order o) {
    var boost = _ownedGear.contains('thermo') ? 0.08 : 0.0;
    if (o.isRegular) boost += 0.12;
    final r = _rng.nextDouble() - boost;
    if (r < 0.78) return 5;
    if (r < 0.93) return 4;
    if (r < 0.98) return 3;
    if (r < 0.995) return 2;
    return 1;
  }

  void _finalizeDelivery() {
    final o = _currentOrder!;
    final fuel = o.distanceKm * 1.5 * _vehicle.fuelPerKm;
    final net = o.gross - fuel;
    final delivery = CompletedDelivery(
      category: o.category,
      partner: o.partner,
      customer: o.customer,
      net: net,
      gross: o.gross,
      tip: o.tip,
      stars: o.customerStars,
      weather: o.weatherAtPickup,
      simHour: _simHour,
      surge: o.surge,
      distanceKm: o.distanceKm,
    );

    final int xpGain = 10 +
        max<int>(0, (o.customerStars - 3) * 3) +
        (o.tip / 2).round() +
        (o.surge >= 1.4 ? 5 : 0);

    final levelBefore = _level;

    setState(() {
      _completed++;
      _gross += o.gross;
      _fuelCost += fuel;
      _rating = _rating * 0.92 + o.customerStars * 0.08;
      _state = CourierState.delivered;
      _history.insert(0, delivery);
      if (_history.length > 50) _history.removeLast();
      if (o.tip > _bestTip) _bestTip = o.tip;
      if (net > _bestNet) _bestNet = net;
      if (o.tip > _maxTipReceived) _maxTipReceived = o.tip;
      if (o.weatherAtPickup.isRainy) _rainDeliveries++;
      if (o.surge >= 1.4) _peakDeliveries++;
      _categoriesDelivered.add(o.category);
      if (o.customerStars == 5) {
        _fiveStarTotal++;
        _fiveStarStreak++;
      } else {
        _fiveStarStreak = 0;
      }
      _customerVisits[o.customer] = (_customerVisits[o.customer] ?? 0) + 1;
      final newCount = _customerVisits[o.customer]!;
      if (newCount == 3) {
        _showEventBanner('${o.customer} jest teraz stałym klientem!',
            glovoPurple);
      }
      _hourlyEarnings[_simHour] = (_hourlyEarnings[_simHour] ?? 0) + net;
      _weeklyNet += net;
      _weeklyDeliveries++;
      _xp += xpGain;
      while (_xp >= _xpPerLevel) {
        _xp -= _xpPerLevel;
        _level++;
      }
      _updateGoals(delivery);
    });

    if (_level > levelBefore) {
      _showEventBanner('Awans! Poziom $_level', glovoYellow);
      HapticFeedback.heavyImpact();
      AudioService.instance.sfx('level_up.mp3');
    } else {
      AudioService.instance.sfx('cash.mp3');
    }
    HapticFeedback.heavyImpact();
    _checkAchievements();
    _saveState();

    Timer(const Duration(milliseconds: 3500), () {
      if (!mounted) return;
      // If a stacked order was accepted, continue with it
      if (_stackedOrder != null) {
        final stacked = _stackedOrder!;
        setState(() {
          _currentOrder = stacked;
          _stackedOrder = null;
          _state = CourierState.toRestaurant;
          _routeProgress = 0;
        });
        _showEventBanner('Następna dostawa: ${stacked.partner}', glovoOrange);
        _runRoute(onComplete: _onArriveAtRestaurant);
        return;
      }
      setState(() {
        _currentOrder = null;
        _state = CourierState.searching;
        _routeProgress = 0;
      });
      _scheduleNextOrder();
    });
  }

  void _updateGoals(CompletedDelivery d) {
    for (final g in _goals) {
      if (g.claimed) continue;
      switch (g.kind) {
        case GoalKind.deliveries:
          g.progress++;
        case GoalKind.earnings:
          g.progress = (g.progress + d.net.round()).clamp(0, g.target);
        case GoalKind.fiveStars:
          if (d.stars == 5) g.progress++;
        case GoalKind.rainDelivery:
          if (d.weather.isRainy) g.progress++;
        case GoalKind.peakDelivery:
          if (d.surge >= 1.4) g.progress++;
        case GoalKind.category:
          if (d.category == g.category) g.progress++;
        case GoalKind.bigTip:
          if (d.tip >= 5.0) g.progress++;
      }
    }
    final w = _weekly;
    if (w != null && !w.claimed) {
      if (w.title.contains('dostaw')) {
        w.progress++;
      } else if (w.title.contains('netto')) {
        w.progress = (w.progress + d.net.round()).clamp(0, w.target);
      } else if (w.title.contains('5★')) {
        if (d.stars == 5) w.progress++;
      } else if (w.title.contains('deszczu')) {
        if (d.weather.isRainy) w.progress++;
      }
    }
  }

  void _claimWeekly() {
    final w = _weekly;
    if (w == null || !w.done || w.claimed) return;
    setState(() {
      w.claimed = true;
      _gross += w.reward;
    });
    _showEventBanner(
        'Weekly ukończone! +${w.reward.toStringAsFixed(2)} zł', glovoYellow);
    HapticFeedback.heavyImpact();
    _checkAchievements();
    Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _weekly = WeeklyChallenge.fresh(_rng));
      _saveState();
    });
    _saveState();
  }

  void _buyGear(GearItem item) {
    if (_ownedGear.contains(item.id)) return;
    final net = _gross - _fuelCost;
    if (net < item.price) {
      _toast('Brak środków — potrzebujesz ${item.price} zł netto', glovoRed);
      return;
    }
    setState(() {
      _ownedGear.add(item.id);
      _gross -= item.price.toDouble();
    });
    _showEventBanner('Zakupiono: ${item.name}', glovoGreen);
    HapticFeedback.mediumImpact();
    _checkAchievements();
    _saveState();
  }

  void _switchZone(Zone z) {
    if (z.unlockLevel > _level) return;
    if (_state != CourierState.offline) {
      _toast('Zmień strefę gdy jesteś offline', glovoOrange);
      return;
    }
    setState(() => _zone = z);
    _showEventBanner('Strefa: ${z.label}', z.color);
    _saveState();
  }

  // ===== DAILY LOGIN STREAK =====
  void _checkDailyLogin() {
    final now = DateTime.now();
    final today = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    if (_lastLoginDate == today) return;

    int newStreak;
    if (_lastLoginDate == null) {
      newStreak = 1;
    } else {
      try {
        final prev = DateTime.parse(_lastLoginDate!);
        final daysDiff =
            DateTime(now.year, now.month, now.day).difference(
                    DateTime(prev.year, prev.month, prev.day))
                .inDays;
        if (daysDiff == 1) {
          newStreak = _loginStreak + 1;
        } else {
          newStreak = 1;
        }
      } catch (_) {
        newStreak = 1;
      }
    }

    final bonus = (5.0 * newStreak).clamp(5.0, 50.0).toDouble();
    setState(() {
      _loginStreak = newStreak;
      _lastLoginDate = today;
      _gross += bonus;
    });
    _saveState();
    _checkAchievements();

    Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _showLoginBonusDialog(newStreak, bonus);
    });

    _resolveAndSpawnDuel(today);
  }

  // ===== DAILY RIVAL DUEL =====
  Rival _rivalById(String id) =>
      _rivals.firstWhere((r) => r.id == id, orElse: () => _rivals.first);

  void _resolveAndSpawnDuel(String today) {
    // Resolve previous duel if any
    final prev = _activeDuel;
    if (prev != null && !prev.resolved && prev.dateKey != today) {
      final won = prev.progressNet >= prev.targetNet;
      final reward = won ? double.parse(
          (prev.targetNet * 0.15 + 20).toStringAsFixed(2)) : 0.0;
      setState(() {
        prev.resolved = true;
        if (won) {
          _duelsWon++;
          _gross += reward;
        } else {
          _duelsLost++;
        }
      });
      Timer(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        _showDuelResultDialog(prev, won, reward);
      });
    }

    // Spawn new duel for today (if none yet matching today)
    if (_activeDuel == null || _activeDuel!.dateKey != today) {
      final rival = _rivals[_rng.nextInt(_rivals.length)];
      // Target = rival's daily avg, scaled by player's level (so it stays relevant)
      final levelScale = 0.6 + (_level * 0.06).clamp(0.0, 0.7);
      final variance = 0.85 + _rng.nextDouble() * 0.30;
      final target = double.parse(
          (rival.dailyAvg * levelScale * variance).toStringAsFixed(2));
      setState(() {
        _activeDuel = DailyDuel(
          rivalId: rival.id,
          targetNet: target,
          dateKey: today,
        );
      });
      _saveState();
    }
  }

  void _showDuelResultDialog(DailyDuel d, bool won, double reward) {
    final r = _rivalById(d.rivalId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: glovoCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Text(r.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(won ? 'Pokonałeś rywala!' : 'Rywal Cię ograł',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.name,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Cel: ${d.targetNet.toStringAsFixed(2)} zł',
                style: const TextStyle(color: glovoMuted, fontSize: 12)),
            Text('Twój wynik: ${d.progressNet.toStringAsFixed(2)} zł',
                style: TextStyle(
                    color: won ? glovoGreen : glovoRed,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: glovoCardLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('"${r.taunt}"',
                  style: const TextStyle(
                      color: glovoMuted, fontStyle: FontStyle.italic)),
            ),
            if (won) ...[
              const SizedBox(height: 12),
              Text('Nagroda: +${reward.toStringAsFixed(2)} zł',
                  style: const TextStyle(
                      color: glovoGreen, fontWeight: FontWeight.w800)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(
                    color: glovoYellow, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showLoginBonusDialog(int streak, double bonus) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: glovoCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_fire_department_rounded,
                  color: glovoOrange, size: 60),
              const SizedBox(height: 8),
              Text('$streak ${streak == 1 ? "dzień" : "dni"} z rzędu',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('+ ${bonus.toStringAsFixed(2)} zł bonusu',
                  style: const TextStyle(
                      color: glovoGreen,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Zaglądaj codziennie po większy bonus!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: glovoMuted, fontSize: 12)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: glovoYellow,
                    foregroundColor: glovoDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Świetnie!',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    HapticFeedback.heavyImpact();
  }

  // ===== ACHIEVEMENTS =====
  void _checkAchievements() {
    for (final a in _achievements) {
      if (_unlockedAchievements.contains(a.id)) continue;
      bool unlocked = false;
      switch (a.kind) {
        case AchievementKind.totalDeliveries:
          unlocked = _completed >= a.threshold;
        case AchievementKind.totalNet:
          unlocked = (_gross - _fuelCost) >= a.threshold;
        case AchievementKind.fiveStarCount:
          unlocked = _fiveStarTotal >= a.threshold;
        case AchievementKind.rainDeliveries:
          unlocked = _rainDeliveries >= a.threshold;
        case AchievementKind.peakDeliveries:
          unlocked = _peakDeliveries >= a.threshold;
        case AchievementKind.bigTipReceived:
          unlocked = _maxTipReceived >= a.threshold;
        case AchievementKind.reachLevel:
          unlocked = _level >= a.threshold;
        case AchievementKind.allCategories:
          unlocked = _categoriesDelivered.length >= a.threshold;
        case AchievementKind.ownAllGear:
          unlocked = _ownedGear.length >= a.threshold;
        case AchievementKind.fiveStarStreak:
          unlocked = _fiveStarStreak >= a.threshold;
        case AchievementKind.loginStreak:
          unlocked = _loginStreak >= a.threshold;
      }
      if (unlocked) _unlockAchievement(a);
    }
  }

  void _unlockAchievement(Achievement a) {
    setState(() {
      _unlockedAchievements.add(a.id);
      _gross += a.reward;
    });
    _showEventBanner('🏆 ${a.title}: +${a.reward.toStringAsFixed(0)} zł',
        glovoYellow);
    HapticFeedback.heavyImpact();
    AudioService.instance.sfx('achievement.mp3');
    _saveState();
  }

  // ===== STACKED ORDERS =====
  Order _generateOrderForStack() {
    final categories = [
      OrderCategory.food, OrderCategory.food, OrderCategory.food,
      OrderCategory.grocery, OrderCategory.grocery,
      OrderCategory.pharmacy, OrderCategory.anything,
    ];
    final cat = categories[_rng.nextInt(categories.length)];
    late (String, String) partner;
    late List<String> pool;
    int itemCountMax;
    switch (cat) {
      case OrderCategory.food:
        partner = _foodPartners[_rng.nextInt(_foodPartners.length)];
        pool = _foodItems;
        itemCountMax = 3;
      case OrderCategory.grocery:
        partner = _groceryPartners[_rng.nextInt(_groceryPartners.length)];
        pool = _groceryItems;
        itemCountMax = 5;
      case OrderCategory.pharmacy:
        partner = _pharmacyPartners[_rng.nextInt(_pharmacyPartners.length)];
        pool = _pharmacyItems;
        itemCountMax = 2;
      case OrderCategory.anything:
        partner = _anythingPartners[_rng.nextInt(_anythingPartners.length)];
        pool = _anythingItems;
        itemCountMax = 1;
    }
    final c = _customers[_rng.nextInt(_customers.length)];
    final isRegular = (_customerVisits[c.$1] ?? 0) >= 3;
    final itemsCount = 1 + _rng.nextInt(itemCountMax);
    final items = <String>[];
    for (var i = 0; i < itemsCount; i++) {
      items.add(pool[_rng.nextInt(pool.length)]);
    }
    final dist = 0.5 + _rng.nextDouble() * 2.0; // shorter, stacked nearby
    var basePay = 4.0 + dist * 2.10 + _rng.nextDouble() * 1.5;
    basePay *= 1.20; // stacked bonus
    basePay *= _zone.payoutMul;
    if (_ownedGear.contains('rack')) basePay += 1.0;
    if (_weather.isRainy && _ownedGear.contains('raincoat')) {
      basePay *= 1.10;
    }
    final code = (1000 + _rng.nextInt(8999)).toString();
    var prep = cat == OrderCategory.food
        ? 3 + _rng.nextInt(5)
        : cat == OrderCategory.grocery
            ? 2 + _rng.nextInt(4)
            : 2 + _rng.nextInt(3);
    if (_ownedGear.contains('vip')) prep = (prep * 0.7).ceil();

    return Order(
      category: cat,
      partner: partner.$1,
      partnerAddress: 'ul. ${partner.$2}',
      customer: c.$1,
      customerAddress: 'ul. ${c.$2}',
      items: items,
      distanceKm: double.parse(dist.toStringAsFixed(1)),
      basePay: double.parse(basePay.toStringAsFixed(2)),
      surge: _surgeMultiplier,
      weatherAtPickup: _weather,
      pickupCode: code,
      prepSeconds: prep,
      willCancel: false,
      isRegular: isRegular,
    );
  }

  void _maybeOfferStack() {
    if (_pendingStackOffer != null) return;
    if (_stackedOrder != null) return;
    if (_state != CourierState.toCustomer) return;
    if (_completed < 1) return; // first delivery: no stack
    if (_rng.nextDouble() > 0.22) return;

    final stackOrder = _generateOrderForStack();
    setState(() {
      _pendingStackOffer = stackOrder;
      _stackOfferActive = true;
      _stackOfferCountdown = 8;
    });
    HapticFeedback.mediumImpact();
    _stackOfferTimer?.cancel();
    _stackOfferTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _stackOfferCountdown--);
      if (_stackOfferCountdown <= 0) {
        t.cancel();
        _declineStack();
      }
    });
  }

  void _acceptStack() {
    final o = _pendingStackOffer;
    if (o == null) return;
    _stackOfferTimer?.cancel();
    setState(() {
      _stackedOrder = o;
      _pendingStackOffer = null;
      _stackOfferActive = false;
    });
    _showEventBanner(
        'Stackuje: ${o.partner} → ${o.customer} (+${o.basePay.toStringAsFixed(2)} zł)',
        glovoOrange);
    HapticFeedback.mediumImpact();
  }

  void _declineStack() {
    _stackOfferTimer?.cancel();
    setState(() {
      _pendingStackOffer = null;
      _stackOfferActive = false;
    });
  }

  void _claimGoal(Goal g) {
    if (!g.done || g.claimed) return;
    setState(() {
      g.claimed = true;
      _gross += g.reward;
    });
    _showEventBanner('Cel ukończony! +${g.reward.toStringAsFixed(2)} zł',
        glovoGreen);
    HapticFeedback.mediumImpact();
    _checkAchievements();
    _saveState();
    if (_goals.every((x) => x.claimed)) {
      Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        setState(() => _goals = _generateDailyGoals());
        _showEventBanner('Nowe cele dzienne dostępne!', glovoBlue);
      });
    }
  }

  void _showEventBanner(String text, Color color) {
    _eventBannerTimer?.cancel();
    setState(() {
      _eventBanner = text;
      _eventColor = color;
    });
    _eventBannerTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _eventBanner = null);
    });
  }

  void _runRoute({required VoidCallback onComplete}) {
    final o = _currentOrder!;
    _progressTimer?.cancel();

    // Maybe trigger a breakdown before we start the route
    if (_maybeTriggerBreakdown(onComplete)) return;

    var secPerKm = _vehicle.secPerKm;
    if (_ownedGear.contains('gps')) secPerKm *= 0.85;
    final baseSec = (o.distanceKm * secPerKm).clamp(2.5, 30);
    var totalSteps = (baseSec * 10).round();
    final trafficChance = _ownedGear.contains('phone') ? 0.005 : 0.012;
    final trafficLightChance = 0.008;
    var step = 0;
    var slowdownStepsLeft = 0;
    var trafficTriggered = false;
    var trafficLightUsed = false;
    var phoneTriggered = false;
    final routeKm = o.distanceKm;
    var kmCounted = false;

    // Initial speed
    setState(() {
      _currentSpeedKmh = _vehicle.speedKmh.toDouble();
      _trafficLightActive = false;
      _currentTurn = _turnAt(0, goingTo: _state == CourierState.toRestaurant
          ? o.partnerAddress
          : o.customerAddress);
    });
    AudioService.instance
        .loop('engine', 'engine_${_vehicle.name}.mp3', volume: 0.45);

    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }

      // Traffic light tick
      if (_trafficLightActive) {
        if (step % 10 == 0) {
          setState(() {
            _trafficLightSec--;
            _currentSpeedKmh = 0;
          });
          if (_trafficLightSec <= 0) {
            setState(() => _trafficLightActive = false);
            HapticFeedback.lightImpact();
            _showEventBanner('Zielone — jedziesz', glovoGreen);
          }
        }
        return; // freeze progress
      }

      // Stacked-order offer chance (only on toCustomer leg)
      if (_state == CourierState.toCustomer &&
          step > totalSteps * 0.20 &&
          step < totalSteps * 0.85 &&
          step % 10 == 0) {
        _maybeOfferStack();
      }
      // Customer chat: trigger once between 25-60% of toCustomer route
      if (_state == CourierState.toCustomer &&
          !_chatTriggered &&
          step > totalSteps * 0.25 &&
          step < totalSteps * 0.60 &&
          _rng.nextDouble() < 0.06) {
        _chatTriggered = true;
        _customerSendsMessage();
      }
      // Random events during route
      if (!trafficTriggered &&
          step > totalSteps * 0.25 &&
          step < totalSteps * 0.75 &&
          _rng.nextDouble() < trafficChance) {
        trafficTriggered = true;
        slowdownStepsLeft = 25 + _rng.nextInt(20);
        totalSteps += slowdownStepsLeft ~/ 2;
        _showEventBanner('Korek na trasie — opóźnienie', glovoOrange);
        HapticFeedback.lightImpact();
      }
      if (!trafficLightUsed &&
          step > totalSteps * 0.30 &&
          step < totalSteps * 0.70 &&
          _rng.nextDouble() < trafficLightChance) {
        trafficLightUsed = true;
        setState(() {
          _trafficLightActive = true;
          _trafficLightSec = 3 + _rng.nextInt(4);
        });
        HapticFeedback.mediumImpact();
        AudioService.instance.sfx('traffic_light.mp3', volume: 0.7);
        return;
      }
      if (!phoneTriggered &&
          _state == CourierState.toCustomer &&
          step > totalSteps * 0.4 &&
          _rng.nextDouble() < 0.008) {
        phoneTriggered = true;
        _showEventBanner('${o.customer}: "Czy mogę dostać dodatkowe sztućce?"',
            glovoBlue);
      }

      // Slowdown: every 2nd tick during slowdown skips progress
      if (slowdownStepsLeft > 0) {
        slowdownStepsLeft--;
        if (slowdownStepsLeft.isOdd) {
          return;
        }
      }
      step++;
      // Update speed (varies slightly)
      var speed = _vehicle.speedKmh.toDouble();
      if (slowdownStepsLeft > 0) speed *= 0.4;
      if (_weather == Weather.rainy) speed *= 0.85;
      if (_weather == Weather.heavyRain) speed *= 0.65;
      speed += _rng.nextDouble() * 4 - 2;
      // Update turn instruction at 25%/50%/75%/95%
      final progress = step / totalSteps;
      final turn = _turnAt(progress,
          goingTo: _state == CourierState.toRestaurant
              ? o.partnerAddress
              : o.customerAddress);
      setState(() {
        _routeProgress = progress.clamp(0.0, 1.0);
        _currentSpeedKmh = speed.clamp(0, 60);
        _currentTurn = turn;
      });
      if (step >= totalSteps) {
        t.cancel();
        AudioService.instance.stopLoop('engine');
        if (!kmCounted && _vehicle != Vehicle.bike) {
          _kmDriven[_vehicle.name] =
              (_kmDriven[_vehicle.name] ?? 0) + routeKm;
          kmCounted = true;
        }
        setState(() {
          _currentSpeedKmh = 0;
          _currentTurn = null;
        });
        onComplete();
      }
    });
  }

  // ===== VEHICLE BREAKDOWN =====
  double _serviceCost() {
    final v = _vehicle;
    if (v == Vehicle.bike) return 0;
    final km = _kmDriven[v.name] ?? 0;
    final base = v == Vehicle.scooter ? 25.0 : 45.0;
    return double.parse((base + km * 0.15).toStringAsFixed(2));
  }

  double _breakdownChance() {
    final v = _vehicle;
    if (v == Vehicle.bike) return 0;
    final km = _kmDriven[v.name] ?? 0;
    final threshold = v == Vehicle.scooter ? 60.0 : 120.0;
    if (km <= threshold) return 0;
    return ((km - threshold) / 250).clamp(0.0, 0.45);
  }

  bool _maybeTriggerBreakdown(VoidCallback onComplete) {
    if (_breakdownActive) return false;
    final p = _breakdownChance();
    if (p <= 0 || _rng.nextDouble() > p) return false;
    _breakdownActive = true;
    _pendingRouteCallback = onComplete;
    AudioService.instance.stopLoop('engine');
    HapticFeedback.heavyImpact();
    AudioService.instance.sfx('phone_ring.mp3', volume: 0.7);
    setState(() {
      _currentSpeedKmh = 0;
      _currentTurn = null;
    });
    _showBreakdownDialog();
    return true;
  }

  void _showBreakdownDialog() {
    final cost = _serviceCost();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: glovoCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.build_circle_rounded, color: glovoRed, size: 28),
            SizedBox(width: 8),
            Text('Awaria pojazdu!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Twój ${_vehicle.label.toLowerCase()} odmawia posłuszeństwa. Co robisz?',
                style: const TextStyle(color: glovoMuted, fontSize: 13)),
            const SizedBox(height: 14),
            _breakdownOption(
              icon: Icons.handyman_rounded,
              color: glovoYellow,
              title: 'Wezwij serwis',
              subtitle: '−${cost.toStringAsFixed(2)} zł, pojazd jak nowy',
              onTap: () {
                Navigator.pop(ctx);
                _payService();
              },
            ),
            const SizedBox(height: 8),
            _breakdownOption(
              icon: Icons.warning_amber_rounded,
              color: glovoOrange,
              title: 'Zaryzykuj',
              subtitle: '70% szansy że dojedziesz, 30% że trzeba odpuścić',
              onTap: () {
                Navigator.pop(ctx);
                _riskBreakdown();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _breakdownOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: glovoMuted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: glovoMuted),
          ],
        ),
      ),
    );
  }

  void _payService() {
    final cost = _serviceCost();
    setState(() {
      _fuelCost += cost; // bookkeep as overhead, not consumed fuel — but it's a real expense
      _kmDriven[_vehicle.name] = 0;
      _breakdownActive = false;
    });
    AudioService.instance.sfx('cash.mp3', volume: 0.7);
    _showEventBanner(
        'Serwis: −${cost.toStringAsFixed(2)} zł — jedziemy dalej',
        glovoYellow);
    _saveState();
    final cb = _pendingRouteCallback;
    _pendingRouteCallback = null;
    if (cb != null) _runRoute(onComplete: cb);
  }

  void _riskBreakdown() {
    final win = _rng.nextDouble() < 0.7;
    setState(() {
      _breakdownActive = false;
    });
    final cb = _pendingRouteCallback;
    _pendingRouteCallback = null;
    if (win) {
      _showEventBanner('Ryzyk-fizyk się opłacił — jedziemy', glovoGreen);
      if (cb != null) _runRoute(onComplete: cb);
    } else {
      // Ride aborts: cancel the order, hit rating
      const compensation = 0.0;
      setState(() {
        _cancelled++;
        _gross += compensation;
        _rating = max(4.20, _rating - 0.08);
        _state = CourierState.searching;
        _currentOrder = null;
        _routeProgress = 0;
        _kmDriven[_vehicle.name] = 0; // forced service after breakdown
      });
      AudioService.instance.sfx('phone_ring.mp3', volume: 0.5);
      _showEventBanner(
          'Pojazd padł — zamówienie anulowane, ocena spadła', glovoRed);
      _saveState();
      _scheduleNextOrder();
    }
  }

  String _turnAt(double progress, {required String goingTo}) {
    if (progress < 0.20) {
      return 'Jedź prosto';
    } else if (progress < 0.45) {
      return 'Skręć w prawo w al. Niepodległości';
    } else if (progress < 0.70) {
      return 'Jedź prosto przez rondo';
    } else if (progress < 0.90) {
      return 'Skręć w lewo w $goingTo';
    } else {
      return 'Cel jest po prawej';
    }
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ));
  }

  String _formatTime(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  // ===== BUILD =====

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: glovoYellow),
        ),
      );
    }
    if (!_tutorialSeen) {
      return Scaffold(body: SafeArea(child: _tutorialView()));
    }
    if (_name == null) {
      return Scaffold(body: SafeArea(child: _onboardingView()));
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_eventBanner != null) _eventBannerWidget(),
            Expanded(child: _buildTabContent()),
            if (_tabIndex == 0) _buildBottomBar(),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _tutorialView() {
    final pages = [
      (
        '🛵',
        'Witaj w Glovo Sim',
        'Wciel się w rolę kuriera. Akceptuj zamówienia, jedź do restauracji, dostarczaj klientom i zarabiaj.',
      ),
      (
        '🔥',
        'Peak hours i pogoda',
        'W godziny szczytu (lunch 11–14, kolacja 18–22) jest więcej zamówień i wyższe stawki. Deszcz dodaje bonus pieniężny.',
      ),
      (
        '🛒',
        'Wyposażenie i awanse',
        'Kupuj wyposażenie z zarobionych pieniędzy: termo-torba, GPS, płaszcz przeciwdeszczowy. Każda dostawa daje XP i awanse.',
      ),
      (
        '🏆',
        'Cele i odznaki',
        'Wykonuj cele dzienne i tygodniowe wyzwanie. Zdobywaj odznaki za kamienie milowe. Konkuruj z innymi kurierami w leaderboardzie.',
      ),
    ];
    final isLast = _tutorialPage == pages.length - 1;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                setState(() => _tutorialSeen = true);
                await _saveState();
              },
              child: const Text('Pomiń',
                  style:
                      TextStyle(color: glovoMuted, fontSize: 13)),
            ),
          ),
          Expanded(
            child: PageView.builder(
              itemCount: pages.length,
              controller: PageController(initialPage: _tutorialPage),
              onPageChanged: (i) => setState(() => _tutorialPage = i),
              itemBuilder: (_, i) {
                final p = pages[i];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          color:
                              glovoYellow.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(p.$1,
                            style: const TextStyle(fontSize: 70)),
                      ),
                      const SizedBox(height: 28),
                      Text(p.$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 14),
                      Text(p.$3,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: glovoMuted,
                              fontSize: 14,
                              height: 1.5)),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pages.length, (i) {
                final active = i == _tutorialPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? glovoYellow : glovoCardLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                if (isLast) {
                  setState(() => _tutorialSeen = true);
                  await _saveState();
                } else {
                  setState(() => _tutorialPage++);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: glovoYellow,
                foregroundColor: glovoDark,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(isLast ? 'Zaczynam!' : 'Dalej',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _onboardingView() {
    final ctrl = TextEditingController();
    Vehicle pickedVehicle = Vehicle.scooter;
    Zone pickedZone = Zone.centrum;
    return StatefulBuilder(
      builder: (ctx, setLocal) => Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: glovoYellow,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delivery_dining_rounded,
                    color: glovoDark, size: 44),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text('Glovo Courier Sim',
                  style:
                      TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            ),
            const Center(
              child: Text('Załóż konto kuriera',
                  style: TextStyle(color: glovoMuted, fontSize: 14)),
            ),
            const SizedBox(height: 28),
            const Text('Imię',
                style:
                    TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              maxLength: 20,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              cursorColor: glovoYellow,
              decoration: InputDecoration(
                filled: true,
                fillColor: glovoCard,
                hintText: 'np. Mateusz',
                hintStyle: const TextStyle(color: glovoMuted),
                counterText: '',
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(14),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Pojazd',
                style:
                    TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: Vehicle.values.map((v) {
                final selected = v == pickedVehicle;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () =>
                          setLocal(() => pickedVehicle = v),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: selected
                              ? glovoYellow.withValues(alpha: 0.18)
                              : glovoCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? glovoYellow
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(v.icon,
                                color: selected
                                    ? glovoYellow
                                    : Colors.white,
                                size: 28),
                            const SizedBox(height: 6),
                            Text(v.label,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: selected
                                        ? glovoYellow
                                        : Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            const Text('Strefa pracy',
                style:
                    TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 8),
            ...Zone.values
                .where((z) => z.unlockLevel <= 1)
                .map((z) => _zonePickerCard(z, pickedZone == z,
                    () => setLocal(() => pickedZone = z))),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final name = ctrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Wpisz swoje imię'),
                    backgroundColor: glovoRed,
                  ));
                  return;
                }
                setState(() {
                  _name = name;
                  _vehicle = pickedVehicle;
                  _zone = pickedZone;
                });
                await _saveState();
                _checkDailyLogin();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: glovoYellow,
                foregroundColor: glovoDark,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Zaczynam pracę',
                  style:
                      TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _zonePickerCard(Zone z, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? z.color.withValues(alpha: 0.15)
                : glovoCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? z.color : Colors.transparent, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: z.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(z.icon, color: z.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(z.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(z.desc,
                        style: const TextStyle(
                            color: glovoMuted, fontSize: 11)),
                    Text(
                        'Demand ×${z.demandMul.toStringAsFixed(2)} · Payout ×${z.payoutMul.toStringAsFixed(2)} · Tip ×${z.tipMul.toStringAsFixed(2)}',
                        style: TextStyle(color: z.color, fontSize: 10)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: z.color, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventBannerWidget() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: _eventColor.withValues(alpha: 0.18),
      child: Row(
        children: [
          Icon(Icons.notifications_active_rounded,
              color: _eventColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_eventBanner!,
                style: TextStyle(
                    color: _eventColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabIndex) {
      case 1:
        return _buildStatsTab();
      case 2:
        return _buildGoalsTab();
      case 3:
        return _buildProfileTab();
      default:
        return _buildBody();
    }
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: glovoCard,
        border: Border(top: BorderSide(color: glovoDark, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            _navItem(0, Icons.work_rounded, 'Zlecenia'),
            _navItem(1, Icons.bar_chart_rounded, 'Statystyki'),
            _navItem(2, Icons.flag_rounded, 'Cele'),
            _navItem(3, Icons.person_rounded, 'Profil'),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int idx, IconData icon, String label) {
    final selected = _tabIndex == idx;
    final pendingClaim = idx == 2 &&
        _goals.any((g) => g.done && !g.claimed);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _tabIndex = idx),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon,
                      color: selected ? glovoYellow : glovoMuted, size: 24),
                  if (pendingClaim)
                    Positioned(
                      right: -3,
                      top: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: glovoRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: selected ? glovoYellow : glovoMuted,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final online = _state != CourierState.offline;
    final net = _gross - _fuelCost;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: glovoCard,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      value: _xp / _xpPerLevel,
                      strokeWidth: 3,
                      backgroundColor: glovoCardLight,
                      valueColor:
                          const AlwaysStoppedAnimation(glovoYellow),
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: glovoYellow,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('$_level',
                          style: const TextStyle(
                              color: glovoDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 16)),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_name ?? 'Kurier',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(width: 6),
                        Icon(_vehicle.icon, size: 14, color: glovoMuted),
                        const SizedBox(width: 6),
                        Icon(_zone.icon, size: 14, color: _zone.color),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 14, color: glovoYellow),
                        const SizedBox(width: 2),
                        Text(_rating.toStringAsFixed(2),
                            style: const TextStyle(
                                color: glovoMuted, fontSize: 12)),
                        const SizedBox(width: 8),
                        Icon(Icons.circle,
                            size: 7, color: online ? glovoGreen : glovoMuted),
                        const SizedBox(width: 3),
                        Text(online ? 'Online' : 'Offline',
                            style: TextStyle(
                                color: online ? glovoGreen : glovoMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              _seasonChip(),
              const SizedBox(width: 6),
              if (online) _weatherChip(),
              const SizedBox(width: 6),
              if (online) _clockChip(),
            ],
          ),
          const SizedBox(height: 10),
          if (online && _isPeak)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [glovoOrange, glovoRed]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_fire_department_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                      'Peak ${_surgeMultiplier.toStringAsFixed(2)}× — wyższe stawki',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12)),
                ],
              ),
            ),
          if (online && _activeEvent != null) _eventChip(),
          Row(
            children: [
              _statTile(Icons.payments_rounded,
                  '${net.toStringAsFixed(2)} zł', 'Netto'),
              _statTile(
                  Icons.local_shipping_rounded, '$_completed', 'Dostawy'),
              _statTile(Icons.timer_outlined,
                  _formatTime(_onlineSeconds), 'Czas'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seasonChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: _season.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_season.emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 3),
          Text(_season.label,
              style: TextStyle(
                  color: _season.color,
                  fontWeight: FontWeight.w700,
                  fontSize: 10)),
        ],
      ),
    );
  }

  Widget _weatherChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _weather.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_weather.icon, color: _weather.color, size: 16),
          const SizedBox(width: 4),
          Text(_weather.label,
              style: TextStyle(
                  color: _weather.color,
                  fontWeight: FontWeight.w700,
                  fontSize: 11)),
        ],
      ),
    );
  }

  Widget _eventChip() {
    final ev = _activeEvent!;
    final inMyZone = ev.zone == _zone;
    final h = ev.remainingMin ~/ 60;
    final m = ev.remainingMin % 60;
    final timeStr = h > 0 ? '${h}h ${m}min' : '${m}min';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ev.kind.color.withValues(alpha: inMyZone ? 0.30 : 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ev.kind.color.withValues(alpha: inMyZone ? 0.7 : 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ev.kind.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              inMyZone
                  ? '${ev.kind.label} · $timeStr'
                  : '${ev.kind.label} w ${ev.zone.label} · $timeStr',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: ev.kind.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clockChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: glovoCardLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time_rounded,
              color: glovoMuted, size: 14),
          const SizedBox(width: 4),
          Text(_simClock,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _statTile(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: glovoDark,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: glovoYellow, size: 16),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13)),
            Text(label,
                style: const TextStyle(color: glovoMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case CourierState.offline:
        return _offlineView();
      case CourierState.searching:
        return _searchingView();
      case CourierState.orderIncoming:
        return _incomingOrderView();
      case CourierState.toRestaurant:
      case CourierState.toCustomer:
        return _routeView();
      case CourierState.atRestaurantWaiting:
        return _waitingAtRestaurantView();
      case CourierState.atRestaurantReady:
        return _pickupCodeView();
      case CourierState.itemsCheck:
        return _itemsCheckView();
      case CourierState.orderCancelled:
        return _cancelledView();
      case CourierState.findingApartment:
        return _findApartmentView();
      case CourierState.atCustomer:
        return _atCustomerView();
      case CourierState.customerCalling:
        return _customerCallingView();
      case CourierState.takingPhoto:
        return _photoView();
      case CourierState.ratingPending:
        return _ratingView();
      case CourierState.delivered:
        return _deliveredView();
    }
  }

  Widget _photoView() {
    final o = _currentOrder!;
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.photo_camera_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Text('Photo proof',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
                const Spacer(),
                Text(o.customer,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101218),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, _) => CustomPaint(
                        painter:
                            _DoorPainter(time: _pulseCtrl.value),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.white70, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: const [
                          Positioned(
                              top: -2,
                              left: -2,
                              child: _Corner(top: true, left: true)),
                          Positioned(
                              top: -2,
                              right: -2,
                              child: _Corner(top: true, left: false)),
                          Positioned(
                              bottom: -2,
                              left: -2,
                              child: _Corner(top: false, left: true)),
                          Positioned(
                              bottom: -2,
                              right: -2,
                              child: _Corner(top: false, left: false)),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 18,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              'Sfotografuj zamówienie pod drzwiami klienta',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ===== STATS TAB =====
  Widget _buildStatsTab() {
    final net = _gross - _fuelCost;
    final acceptance = _completed + _rejected + _cancelled == 0
        ? 0.0
        : _completed / (_completed + _rejected + _cancelled);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Statystyki ogólne',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(
          children: [
            _bigStatCard('Brutto', '${_gross.toStringAsFixed(2)} zł',
                Icons.payments_rounded, glovoYellow),
            const SizedBox(width: 8),
            _bigStatCard('Netto', '${net.toStringAsFixed(2)} zł',
                Icons.account_balance_wallet_rounded, glovoGreen),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _bigStatCard('Paliwo', '-${_fuelCost.toStringAsFixed(2)} zł',
                Icons.local_gas_station_rounded, glovoRed),
            const SizedBox(width: 8),
            _bigStatCard('Akceptacja',
                '${(acceptance * 100).toStringAsFixed(0)}%',
                Icons.check_circle_rounded, glovoBlue),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _bigStatCard('Najlepszy napiwek',
                '${_bestTip.toStringAsFixed(2)} zł',
                Icons.savings_rounded, glovoGreen),
            const SizedBox(width: 8),
            _bigStatCard('Top dostawa',
                '${_bestNet.toStringAsFixed(2)} zł',
                Icons.emoji_events_rounded, glovoYellow),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _bigStatCard('Odrzucone', '$_rejected',
                Icons.cancel_outlined, glovoMuted),
            const SizedBox(width: 8),
            _bigStatCard('Anulowane', '$_cancelled',
                Icons.report_gmailerrorred_rounded, glovoOrange),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.bar_chart_rounded,
                color: glovoYellow, size: 18),
            const SizedBox(width: 6),
            const Text('Zarobki wg godziny',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        _buildHourlyHistogram(),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.history_rounded, color: glovoYellow, size: 18),
            const SizedBox(width: 6),
            Text('Historia dostaw (${_history.length})',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: glovoCard,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('Brak ukończonych dostaw',
                  style: TextStyle(color: glovoMuted)),
            ),
          )
        else
          ..._history.map(_historyTile),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _bigStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: glovoCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16)),
            Text(label,
                style: const TextStyle(color: glovoMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildHourlyHistogram() {
    if (_hourlyEarnings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: glovoCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Wykonaj kilka dostaw, by zobaczyć rozkład zarobków',
              style: TextStyle(color: glovoMuted, fontSize: 12)),
        ),
      );
    }
    final maxVal = _hourlyEarnings.values.reduce(max);
    final bestHour =
        _hourlyEarnings.entries.reduce((a, b) => a.value > b.value ? a : b);
    final totalSum = _hourlyEarnings.values.reduce((a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: glovoCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rate_rounded,
                  color: glovoYellow, size: 14),
              const SizedBox(width: 4),
              Text(
                  'Najlepsza godzina: ${bestHour.key.toString().padLeft(2, '0')}:00 — ${bestHour.value.toStringAsFixed(2)} zł',
                  style: const TextStyle(fontSize: 12)),
              const Spacer(),
              Text('Łącznie: ${totalSum.toStringAsFixed(0)} zł',
                  style: const TextStyle(
                      color: glovoMuted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (h) {
                final v = _hourlyEarnings[h] ?? 0;
                final barHeight = maxVal == 0 ? 0.0 : (v / maxVal) * 90;
                final isPeak = (h >= 11 && h < 14) ||
                    (h >= 18 && h < 22);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                isPeak ? glovoOrange : glovoYellow,
                                isPeak
                                    ? glovoRed
                                    : glovoYellow.withValues(alpha: 0.6),
                              ],
                            ),
                            borderRadius:
                                BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (h % 4 == 0)
                          Text(h.toString().padLeft(2, '0'),
                              style: const TextStyle(
                                  color: glovoMuted, fontSize: 8))
                        else
                          const SizedBox(height: 9),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(CompletedDelivery d) {
    final hourStr = '${d.simHour.toString().padLeft(2, '0')}:00';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: glovoCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: d.category.color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(d.category.icon, color: d.category.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.partner,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                Text('→ ${d.customer}',
                    style: const TextStyle(
                        color: glovoMuted, fontSize: 11)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    ...List.generate(
                        5,
                        (i) => Icon(
                              i < d.stars
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color:
                                  i < d.stars ? glovoYellow : glovoMuted,
                              size: 11,
                            )),
                    const SizedBox(width: 6),
                    Icon(d.weather.icon, color: d.weather.color, size: 11),
                    const SizedBox(width: 4),
                    Text(hourStr,
                        style: const TextStyle(
                            color: glovoMuted, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${d.net.toStringAsFixed(2)} zł',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: glovoGreen,
                      fontSize: 14)),
              if (d.tip > 0)
                Text('+${d.tip.toStringAsFixed(2)} tip',
                    style: const TextStyle(
                        color: glovoMuted, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  // ===== GOALS TAB =====
  Widget _buildGoalsTab() {
    final claimed = _goals.where((g) => g.claimed).length;
    final totalReward = _goals.fold<double>(0, (s, g) => s + g.reward);
    final claimedReward = _goals
        .where((g) => g.claimed)
        .fold<double>(0, (s, g) => s + g.reward);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Cele dzienne',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Postęp: $claimed/${_goals.length} · Pula: ${claimedReward.toStringAsFixed(2)}/${totalReward.toStringAsFixed(2)} zł',
            style: const TextStyle(color: glovoMuted, fontSize: 12)),
        const SizedBox(height: 12),
        ..._goals.map(_goalTile),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: glovoCard,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.military_tech_rounded,
                      color: glovoYellow, size: 18),
                  const SizedBox(width: 6),
                  const Text('Poziom kuriera',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                      color: glovoYellow,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('$_level',
                          style: const TextStyle(
                              color: glovoDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Poziom $_level',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _xp / _xpPerLevel,
                            minHeight: 8,
                            backgroundColor: glovoCardLight,
                            valueColor:
                                const AlwaysStoppedAnimation(glovoYellow),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('$_xp / $_xpPerLevel XP',
                            style: const TextStyle(
                                color: glovoMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_lastShiftDeliveries != null && _lastShiftDeliveries! > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: glovoCard,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history_toggle_off_rounded,
                        color: glovoBlue, size: 18),
                    SizedBox(width: 6),
                    Text('Ostatnia zmiana',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                    'Dostaw: $_lastShiftDeliveries · Czas: ${_formatTime(_lastShiftSeconds ?? 0)}',
                    style: const TextStyle(color: glovoMuted, fontSize: 13)),
                Text('Netto: ${(_lastShiftNet ?? 0).toStringAsFixed(2)} zł',
                    style: const TextStyle(
                        color: glovoGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _goalTile(Goal g) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: glovoCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: g.claimed
              ? glovoGreen.withValues(alpha: 0.6)
              : g.done
                  ? glovoYellow
                  : Colors.transparent,
          width: g.claimed || g.done ? 1.5 : 0,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: glovoYellow.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(g.icon, color: glovoYellow, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(
                        'Postęp: ${g.progress}/${g.target} · Nagroda: ${g.reward.toStringAsFixed(2)} zł',
                        style: const TextStyle(
                            color: glovoMuted, fontSize: 11)),
                  ],
                ),
              ),
              if (g.claimed)
                const Icon(Icons.check_circle_rounded,
                    color: glovoGreen, size: 24)
              else if (g.done)
                ElevatedButton(
                  onPressed: () => _claimGoal(g),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: glovoYellow,
                    foregroundColor: glovoDark,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    minimumSize: const Size(0, 0),
                    elevation: 0,
                  ),
                  child: const Text('Odbierz',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: g.fraction,
              minHeight: 6,
              backgroundColor: glovoCardLight,
              valueColor: AlwaysStoppedAnimation(
                  g.claimed ? glovoGreen : glovoYellow),
            ),
          ),
        ],
      ),
    );
  }

  // ===== PROFILE TAB =====
  Widget _buildProfileTab() {
    final net = _gross - _fuelCost;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: glovoCard,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 70,
                    height: 70,
                    child: CircularProgressIndicator(
                      value: _xp / _xpPerLevel,
                      strokeWidth: 4,
                      backgroundColor: glovoCardLight,
                      valueColor:
                          const AlwaysStoppedAnimation(glovoYellow),
                    ),
                  ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: glovoYellow,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('$_level',
                          style: const TextStyle(
                              color: glovoDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 22)),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name ?? 'Kurier',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: glovoYellow, size: 14),
                        const SizedBox(width: 2),
                        Text(_rating.toStringAsFixed(2),
                            style: const TextStyle(
                                color: glovoMuted, fontSize: 12)),
                        const SizedBox(width: 8),
                        const Icon(Icons.local_shipping_rounded,
                            color: glovoMuted, size: 12),
                        const SizedBox(width: 2),
                        Text('$_completed dostaw',
                            style: const TextStyle(
                                color: glovoMuted, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Saldo netto: ${net.toStringAsFixed(2)} zł',
                        style: const TextStyle(
                            color: glovoGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // ===== Career =====
        Row(
          children: [
            const Icon(Icons.workspace_premium_rounded,
                color: glovoYellow, size: 18),
            const SizedBox(width: 6),
            const Text('Kariera',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('$_careerProgress/${_career.length}',
                style: const TextStyle(color: glovoMuted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        _careerCard(),
        const SizedBox(height: 18),

        // ===== Login Streak =====
        if (_loginStreak > 0) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  glovoOrange.withValues(alpha: 0.25),
                  glovoCard,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: glovoOrange.withValues(alpha: 0.4), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department_rounded,
                    color: glovoOrange, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_loginStreak ${_loginStreak == 1 ? "dzień" : "dni"} z rzędu',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      const Text('Zaglądaj codziennie po większy bonus',
                          style: TextStyle(
                              color: glovoMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],

        // ===== Achievements =====
        Row(
          children: [
            const Icon(Icons.emoji_events_rounded,
                color: glovoYellow, size: 18),
            const SizedBox(width: 6),
            Text(
                'Odznaki (${_unlockedAchievements.length}/${_achievements.length})',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _achievements.map(_achievementBadge).toList(),
        ),
        const SizedBox(height: 18),

        // ===== Weekly Challenge =====
        if (_weekly != null) ...[
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded,
                  color: glovoPurple, size: 18),
              const SizedBox(width: 6),
              const Text('Wyzwanie tygodniowe',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          _weeklyCard(_weekly!),
          const SizedBox(height: 18),
        ],

        // ===== Leaderboard =====
        Row(
          children: [
            const Icon(Icons.leaderboard_rounded,
                color: glovoBlue, size: 18),
            const SizedBox(width: 6),
            const Text('Leaderboard tygodniowy',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        _buildLeaderboard(),
        const SizedBox(height: 18),

        // ===== Regular customers =====
        if (_customerVisits.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.favorite_rounded,
                  color: glovoPurple, size: 18),
              const SizedBox(width: 6),
              Text(
                  'Stali klienci (${_customerVisits.values.where((v) => v >= 3).length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          _buildRegulars(),
          const SizedBox(height: 18),
        ],

        // ===== Zones =====
        Row(
          children: [
            const Icon(Icons.map_rounded, color: glovoBlue, size: 18),
            const SizedBox(width: 6),
            const Text('Strefa pracy',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        ...Zone.values.map(_zoneRow),
        const SizedBox(height: 18),

        // ===== Gear Shop =====
        Row(
          children: [
            const Icon(Icons.shopping_basket_rounded,
                color: glovoYellow, size: 18),
            const SizedBox(width: 6),
            const Text('Sklep wyposażenia',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('Saldo: ${net.toStringAsFixed(2)} zł',
                style: const TextStyle(color: glovoGreen, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        ..._gearCatalog.map(_gearRow),
        const SizedBox(height: 18),

        // ===== Vehicle Service =====
        Row(
          children: [
            const Icon(Icons.build_rounded,
                color: glovoOrange, size: 18),
            const SizedBox(width: 6),
            const Text('Stan pojazdów',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: glovoCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: Vehicle.values
                .where((v) => v != Vehicle.bike)
                .map(_vehicleServiceRow)
                .toList(),
          ),
        ),
        const SizedBox(height: 18),

        // ===== Settings =====
        Row(
          children: [
            const Icon(Icons.settings_rounded,
                color: glovoMuted, size: 18),
            const SizedBox(width: 6),
            const Text('Ustawienia',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: glovoCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SwitchListTile(
            title: const Text('Dźwięk',
                style:
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: const Text(
                'Silnik, dzwonek, klakson, kasa',
                style: TextStyle(color: glovoMuted, fontSize: 11)),
            secondary: Icon(
              AudioService.instance.enabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              color: AudioService.instance.enabled
                  ? glovoYellow
                  : glovoMuted,
            ),
            value: AudioService.instance.enabled,
            activeThumbColor: glovoYellow,
            onChanged: (v) async {
              await AudioService.instance.setEnabled(v);
              if (!mounted) return;
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 18),

        // ===== Reset =====
        TextButton.icon(
          onPressed: () => _confirmReset(),
          icon: const Icon(Icons.refresh_rounded,
              color: glovoRed, size: 16),
          label: const Text('Resetuj cały postęp',
              style: TextStyle(color: glovoRed, fontSize: 12)),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildLeaderboard() {
    final playerEntry = LeaderboardEntry(
      name: _name ?? 'Ty',
      weeklyNet: _weeklyNet,
      deliveries: _weeklyDeliveries,
      level: _level,
      isPlayer: true,
    );
    final all = [..._ghostBoard, playerEntry];
    all.sort((a, b) => b.weeklyNet.compareTo(a.weeklyNet));
    final myRank = all.indexWhere((e) => e.isPlayer) + 1;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: glovoBlue.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.emoji_events_rounded,
                  color: glovoBlue, size: 16),
              const SizedBox(width: 6),
              Text('Twoje miejsce: #$myRank z ${all.length}',
                  style: const TextStyle(
                      color: glovoBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        ...List.generate(all.length, (i) {
          final e = all[i];
          final rank = i + 1;
          final isPodium = rank <= 3;
          final medal = rank == 1
              ? '🥇'
              : rank == 2
                  ? '🥈'
                  : rank == 3
                      ? '🥉'
                      : '';
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: e.isPlayer
                  ? glovoYellow.withValues(alpha: 0.15)
                  : glovoCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: e.isPlayer ? glovoYellow : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: isPodium
                      ? Text(medal,
                          style: const TextStyle(fontSize: 18),
                          textAlign: TextAlign.center)
                      : Text('$rank',
                          style: const TextStyle(
                              color: glovoMuted,
                              fontWeight: FontWeight.w800,
                              fontSize: 13),
                          textAlign: TextAlign.center),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color:
                        e.isPlayer ? glovoYellow : glovoCardLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${e.level}',
                        style: TextStyle(
                            color: e.isPlayer
                                ? glovoDark
                                : glovoMuted,
                            fontWeight: FontWeight.w900,
                            fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: e.isPlayer
                              ? glovoYellow
                              : Colors.white)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${e.weeklyNet.toStringAsFixed(2)} zł',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: glovoGreen,
                            fontSize: 13)),
                    Text('${e.deliveries} dostaw',
                        style: const TextStyle(
                            color: glovoMuted, fontSize: 10)),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRegulars() {
    final regulars = _customerVisits.entries
        .where((e) => e.value >= 3)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (regulars.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: glovoCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
            'Obsłuż klienta 3 razy, by stał się stałym klientem (+50% napiwek, +12% szansy 5★)',
            style: TextStyle(color: glovoMuted, fontSize: 12)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: glovoCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: regulars.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: glovoPurple.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite_rounded,
                      color: glovoPurple, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e.key,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                Text('${e.value}× zamówień',
                    style: const TextStyle(
                        color: glovoMuted, fontSize: 12)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _achievementBadge(Achievement a) {
    final unlocked = _unlockedAchievements.contains(a.id);
    return GestureDetector(
      onTap: () => _showAchievementInfo(a, unlocked),
      child: Container(
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: unlocked
              ? glovoYellow.withValues(alpha: 0.18)
              : glovoCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: unlocked ? glovoYellow : glovoCardLight,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(a.icon,
                color: unlocked ? glovoYellow : glovoMuted, size: 28),
            const SizedBox(height: 4),
            Text(
              a.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: unlocked ? Colors.white : glovoMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.1),
            ),
          ],
        ),
      ),
    );
  }

  void _showAchievementInfo(Achievement a, bool unlocked) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: glovoCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: unlocked
                    ? glovoYellow.withValues(alpha: 0.2)
                    : glovoCardLight,
                shape: BoxShape.circle,
              ),
              child: Icon(a.icon,
                  color: unlocked ? glovoYellow : glovoMuted, size: 44),
            ),
            const SizedBox(height: 14),
            Text(a.title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 6),
            Text(a.desc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: glovoMuted, fontSize: 13)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: glovoGreen.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('+${a.reward.toStringAsFixed(0)} zł',
                  style: const TextStyle(
                      color: glovoGreen,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ),
            const SizedBox(height: 8),
            Text(unlocked ? 'Odblokowane ✓' : 'Zablokowane',
                style: TextStyle(
                    color: unlocked ? glovoGreen : glovoMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _careerCard() {
    final m = _currentCareerMission;
    if (m == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [glovoYellow.withValues(alpha: 0.25), glovoCard],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: glovoYellow, width: 1.5),
        ),
        child: const Row(
          children: [
            Icon(Icons.emoji_events_rounded,
                color: glovoYellow, size: 32),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top Kurier Dzielnicy',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  Text('Wszystkie misje ukończone — szacun!',
                      style:
                          TextStyle(color: glovoMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final cur = m.progress(this);
    final ratio = (cur / m.target).clamp(0.0, 1.0);
    final ready = _careerMissionReady;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [m.color.withValues(alpha: 0.22), glovoCard],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ready ? m.color : m.color.withValues(alpha: 0.4),
          width: ready ? 1.8 : 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(m.chapter,
              style: TextStyle(
                  color: m.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.4)),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: m.color.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(m.icon, color: m.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(m.desc,
                        style: const TextStyle(
                            color: glovoMuted, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: glovoCardLight,
              valueColor: AlwaysStoppedAnimation(m.color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('$cur/${m.target}',
                  style: TextStyle(
                      color: m.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
              const Spacer(),
              Text(
                  '+${m.reward.toStringAsFixed(0)} zł'
                  '${m.xpReward > 0 ? " · +${m.xpReward} XP" : ""}'
                  '${m.unlockZone != null ? " · 🔓 ${Zone.values.firstWhere((z) => z.name == m.unlockZone).label}" : ""}',
                  style: const TextStyle(
                      color: glovoGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 11)),
            ],
          ),
          if (ready) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _claimCareerMission,
                style: ElevatedButton.styleFrom(
                  backgroundColor: m.color,
                  foregroundColor: glovoDark,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Odbierz nagrodę',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 14)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _weeklyCard(WeeklyChallenge w) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [glovoPurple.withValues(alpha: 0.25), glovoCard],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: w.claimed
              ? glovoGreen
              : (w.done ? glovoYellow : glovoPurple.withValues(alpha: 0.5)),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: glovoPurple.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(w.icon, color: glovoPurple, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    Text(
                        'Postęp: ${w.progress}/${w.target} · Nagroda: ${w.reward.toStringAsFixed(0)} zł',
                        style: const TextStyle(
                            color: glovoMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (w.claimed)
                const Icon(Icons.check_circle_rounded,
                    color: glovoGreen, size: 26)
              else if (w.done)
                ElevatedButton(
                  onPressed: _claimWeekly,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: glovoYellow,
                    foregroundColor: glovoDark,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    minimumSize: const Size(0, 0),
                    elevation: 0,
                  ),
                  child: const Text('Odbierz',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: w.fraction,
              minHeight: 8,
              backgroundColor: glovoCardLight,
              valueColor:
                  AlwaysStoppedAnimation(w.claimed ? glovoGreen : glovoPurple),
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoneRow(Zone z) {
    final selected = _zone == z;
    final locked = !_isZoneUnlocked(z);
    final careerHint = _career
        .where((m) => m.unlockZone == z.name)
        .map((m) => m.title)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: locked ? null : () => _switchZone(z),
        child: Opacity(
          opacity: locked ? 0.5 : 1,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? z.color.withValues(alpha: 0.15) : glovoCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? z.color : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: z.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(z.icon, color: z.color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(z.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                      Text(z.desc,
                          style: const TextStyle(
                              color: glovoMuted, fontSize: 11)),
                      Text(
                          'Demand ×${z.demandMul.toStringAsFixed(2)} · Payout ×${z.payoutMul.toStringAsFixed(2)} · Tip ×${z.tipMul.toStringAsFixed(2)}',
                          style: TextStyle(color: z.color, fontSize: 10)),
                    ],
                  ),
                ),
                if (locked)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Icon(Icons.lock_rounded,
                          color: glovoMuted, size: 16),
                      Text(
                          careerHint != null
                              ? 'misja'
                              : 'lvl ${z.unlockLevel}',
                          style: const TextStyle(
                              color: glovoMuted, fontSize: 10)),
                    ],
                  )
                else if (selected)
                  Icon(Icons.check_circle_rounded, color: z.color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _vehicleServiceRow(Vehicle v) {
    final km = _kmDriven[v.name] ?? 0;
    final threshold = v == Vehicle.scooter ? 60.0 : 120.0;
    final wear = (km / (threshold * 2)).clamp(0.0, 1.0);
    final base = v == Vehicle.scooter ? 25.0 : 45.0;
    final cost = base + km * 0.15;
    final net = _gross - _fuelCost;
    final canAfford = net >= cost;
    final wearColor = wear < 0.4
        ? glovoGreen
        : wear < 0.75
            ? glovoOrange
            : glovoRed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: glovoCardLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(v.icon, color: glovoYellow, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(v.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 6),
                    Text('${km.toStringAsFixed(1)} km',
                        style: const TextStyle(
                            color: glovoMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: wear,
                    minHeight: 5,
                    backgroundColor: glovoCardLight,
                    valueColor: AlwaysStoppedAnimation(wearColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: km < 1 || !canAfford
                ? null
                : () => _confirmManualService(v, cost),
            style: ElevatedButton.styleFrom(
              backgroundColor: glovoYellow,
              foregroundColor: glovoDark,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              km < 1 ? 'OK' : '${cost.toStringAsFixed(0)} zł',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmManualService(Vehicle v, double cost) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: glovoCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Serwis ${v.label.toLowerCase()}',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Text(
            'Zapłacić ${cost.toStringAsFixed(2)} zł i wyzerować zużycie pojazdu?',
            style: const TextStyle(color: glovoMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj',
                style: TextStyle(color: glovoMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _fuelCost += cost;
                _kmDriven[v.name] = 0;
              });
              AudioService.instance.sfx('cash.mp3', volume: 0.7);
              _showEventBanner(
                  '${v.label}: zserwisowany za ${cost.toStringAsFixed(2)} zł',
                  glovoGreen);
              _saveState();
            },
            child: const Text('Zapłać',
                style: TextStyle(
                    color: glovoYellow, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _gearRow(GearItem g) {
    final owned = _ownedGear.contains(g.id);
    final net = _gross - _fuelCost;
    final canAfford = net >= g.price;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: glovoCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: owned ? glovoGreen : Colors.transparent, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: glovoYellow.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(g.icon, color: glovoYellow, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  Text(g.desc,
                      style: const TextStyle(
                          color: glovoMuted, fontSize: 11)),
                ],
              ),
            ),
            if (owned)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.check_circle_rounded,
                    color: glovoGreen, size: 24),
              )
            else
              ElevatedButton(
                onPressed: canAfford ? () => _buyGear(g) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canAfford ? glovoYellow : glovoCardLight,
                  foregroundColor:
                      canAfford ? glovoDark : glovoMuted,
                  disabledBackgroundColor: glovoCardLight,
                  disabledForegroundColor: glovoMuted,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 0),
                  elevation: 0,
                ),
                child: Text('${g.price} zł',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: glovoCard,
        title: const Text('Reset całego postępu?'),
        content: const Text(
            'Stracisz poziom, kasę, wyposażenie i wszystkie statystyki. Tej akcji nie można cofnąć.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Anuluj',
                style: TextStyle(color: glovoMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _resetProgress();
            },
            child: const Text('Resetuj',
                style: TextStyle(
                    color: glovoRed, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ===== SHIFT SUMMARY MODAL =====
  void _showShiftSummary(int deliveries, double net, int seconds) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: glovoCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: glovoYellow.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emoji_events_rounded,
                    color: glovoYellow, size: 38),
              ),
              const SizedBox(height: 14),
              const Text('Koniec zmiany',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              _summaryRow('Dostaw wykonanych', '$deliveries'),
              _summaryRow('Czas zmiany', _formatTime(seconds)),
              _summaryRow('Średnia / godzinę',
                  seconds > 0
                      ? '${(net / (seconds / 3600)).toStringAsFixed(2)} zł/h'
                      : '—'),
              const Divider(color: glovoCardLight),
              _summaryRow('Netto', '${net.toStringAsFixed(2)} zł',
                  highlight: true),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: glovoYellow,
                    foregroundColor: glovoDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Do widzenia',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: highlight ? Colors.white : glovoMuted,
                    fontSize: highlight ? 16 : 13,
                    fontWeight:
                        highlight ? FontWeight.w800 : FontWeight.w500)),
          ),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: highlight ? 20 : 14,
                  color: highlight ? glovoYellow : Colors.white)),
        ],
      ),
    );
  }

  Widget _offlineView() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.power_settings_new_rounded,
                size: 88, color: glovoMuted),
            SizedBox(height: 16),
            Text('Jesteś offline',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text(
              'Włącz tryb online, żeby otrzymywać zamówienia.\nNajpierw wybierz pojazd.',
              textAlign: TextAlign.center,
              style: TextStyle(color: glovoMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, _) {
                return SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _ring(_pulseCtrl.value),
                      _ring((_pulseCtrl.value + 0.33) % 1),
                      _ring((_pulseCtrl.value + 0.66) % 1),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: const BoxDecoration(
                          color: glovoYellow,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_vehicle.icon,
                            color: glovoDark, size: 40),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('Szukamy zamówień…',
                style:
                    TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Pora: $_simClock · ${_weather.label}',
                style: const TextStyle(color: glovoMuted)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: glovoCard,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                  'Stawka × ${_surgeMultiplier.toStringAsFixed(2)} (peak + pogoda)',
                  style: const TextStyle(
                      color: glovoYellow,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
            if (_rejected > 0 || _cancelled > 0) ...[
              const SizedBox(height: 12),
              Text(
                  'Odrzucone: $_rejected · Anulowane: $_cancelled',
                  style: const TextStyle(color: glovoMuted, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ring(double t) {
    return Opacity(
      opacity: 1 - t,
      child: Container(
        width: 60 + 140 * t,
        height: 60 + 140 * t,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: glovoYellow.withValues(alpha: 0.6), width: 2),
        ),
      ),
    );
  }

  Widget _incomingOrderView() {
    final o = _currentOrder!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: o.category.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(o.category.icon,
                        color: o.category.color, size: 14),
                    const SizedBox(width: 4),
                    Text(o.category.label,
                        style: TextStyle(
                            color: o.category.color,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ],
                ),
              ),
              if (o.isRegular) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: glovoPurple.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite_rounded,
                          color: glovoPurple, size: 14),
                      const SizedBox(width: 4),
                      const Text('Stały klient',
                          style: TextStyle(
                              color: glovoPurple,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: _orderCountdown / 15,
                  strokeWidth: 6,
                  backgroundColor: glovoCardLight,
                  valueColor: AlwaysStoppedAnimation(
                    _orderCountdown > 5 ? glovoYellow : glovoRed,
                  ),
                ),
              ),
              Column(
                children: [
                  Text('$_orderCountdown',
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w900)),
                  const Text('sek.',
                      style: TextStyle(color: glovoMuted, fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Nowe zamówienie!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: glovoCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _badge(Icons.straighten_rounded,
                        '${o.distanceKm.toStringAsFixed(1)} km'),
                    _badge(Icons.shopping_bag_rounded,
                        '${o.items.length} szt.'),
                    _badge(Icons.payments_rounded,
                        '${o.adjustedPay.toStringAsFixed(2)} zł',
                        highlight: true),
                  ],
                ),
                if (o.surge > 1.0 || o.weatherAtPickup.bonus > 1.0) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (o.surge > 1.0)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: glovoOrange.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                              '× ${o.surge.toStringAsFixed(2)} peak',
                              style: const TextStyle(
                                  color: glovoOrange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      if (o.weatherAtPickup.bonus > 1.0)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: o.weatherAtPickup.color
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                              '+${((o.weatherAtPickup.bonus - 1) * 100).round()}% pogoda',
                              style: TextStyle(
                                  color: o.weatherAtPickup.color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                _routePoint(o.category.icon, o.category.color, o.partner,
                    o.partnerAddress),
                Padding(
                  padding: const EdgeInsets.only(left: 19),
                  child: Container(width: 2, height: 22, color: glovoMuted),
                ),
                _routePoint(Icons.home_rounded, glovoGreen, o.customer,
                    o.customerAddress),
                const Divider(height: 22, color: glovoDark),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    o.items.map((e) => '${emojiForItem(e)}  $e').join('\n'),
                    style: const TextStyle(
                        color: glovoMuted, fontSize: 13, height: 1.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, String text, {bool highlight = false}) {
    return Column(
      children: [
        Icon(icon, color: highlight ? glovoYellow : Colors.white, size: 22),
        const SizedBox(height: 4),
        Text(text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: highlight ? glovoYellow : Colors.white,
              fontSize: 14,
            )),
      ],
    );
  }

  Widget _routePoint(
      IconData icon, Color color, String title, String addr) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(addr,
                  style: const TextStyle(color: glovoMuted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _routeView() {
    final o = _currentOrder!;
    final goingToRestaurant = _state == CourierState.toRestaurant;
    final destinationName = goingToRestaurant ? o.partner : o.customer;
    final destinationAddr =
        goingToRestaurant ? o.partnerAddress : o.customerAddress;
    final remainingKm = o.distanceKm * (1 - _routeProgress);
    final etaMin = (remainingKm * 60 / _vehicle.speedKmh).ceil();
    return Stack(
      children: [
        Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedBuilder(
                    animation: _rainCtrl,
                    builder: (_, _) => CustomPaint(
                      painter: _MapPainter(
                        progress: _routeProgress,
                        pinColor:
                            goingToRestaurant ? o.category.color : glovoGreen,
                        weather: _weather,
                        rainPhase: _rainCtrl.value,
                        vehicleIcon: _vehicle.icon,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                if (_currentTurn != null)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.directions_rounded,
                              color: glovoYellow, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_currentTurn!,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: _speedometer(),
                ),
                if (_state == CourierState.toCustomer && _chat.isNotEmpty)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: _chatBubbleButton(),
                  ),
                if (_trafficLightActive) _trafficLightOverlay(),
                if (_chatOpen) _chatOverlay(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: glovoCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      goingToRestaurant
                          ? o.category.icon
                          : Icons.home_rounded,
                      color: goingToRestaurant
                          ? o.category.color
                          : glovoGreen,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goingToRestaurant
                                ? 'Jedziesz do ${o.category == OrderCategory.food ? "restauracji" : o.category == OrderCategory.grocery ? "sklepu" : o.category == OrderCategory.pharmacy ? "apteki" : "punktu"}'
                                : 'Jedziesz do klienta',
                            style: const TextStyle(
                                color: glovoMuted, fontSize: 11),
                          ),
                          Text(destinationName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                          Text(destinationAddr,
                              style: const TextStyle(
                                  color: glovoMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('~$etaMin min',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('${remainingKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                                color: glovoMuted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _routeProgress,
                    minHeight: 8,
                    backgroundColor: glovoDark,
                    valueColor: AlwaysStoppedAnimation(
                      goingToRestaurant ? o.category.color : glovoGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
        if (_stackOfferActive && _pendingStackOffer != null)
          _buildStackOfferOverlay(_pendingStackOffer!),
      ],
    );
  }

  Widget _chatBubbleButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleChat,
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: glovoBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: glovoBlue.withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Icon(Icons.chat_bubble_rounded,
                  color: Colors.white, size: 22),
            ),
            if (_chatBadgeUnread)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: glovoRed,
                    shape: BoxShape.circle,
                    border: Border.all(color: glovoDark, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chatOverlay() {
    final o = _currentOrder;
    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleChat,
        child: Container(
          color: Colors.black54,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: glovoCard,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: glovoPurple.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text((o?.customer ?? '?')[0],
                              style: const TextStyle(
                                  color: glovoPurple,
                                  fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(o?.customer ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              const Text('online',
                                  style: TextStyle(
                                      color: glovoGreen,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: glovoMuted),
                          onPressed: _toggleChat,
                        ),
                      ],
                    ),
                    const Divider(color: glovoCardLight, height: 16),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            vertical: 4),
                        itemCount: _chat.length,
                        itemBuilder: (_, idx) {
                          final m = _chat[_chat.length - 1 - idx];
                          final isCustomer = m.from == 'customer';
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4),
                            child: Row(
                              mainAxisAlignment: isCustomer
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isCustomer
                                          ? glovoCardLight
                                          : glovoYellow,
                                      borderRadius: BorderRadius.only(
                                        topLeft:
                                            const Radius.circular(14),
                                        topRight:
                                            const Radius.circular(14),
                                        bottomLeft: Radius.circular(
                                            isCustomer ? 4 : 14),
                                        bottomRight: Radius.circular(
                                            isCustomer ? 14 : 4),
                                      ),
                                    ),
                                    child: Text(m.text,
                                        style: TextStyle(
                                          color: isCustomer
                                              ? Colors.white
                                              : glovoDark,
                                          fontSize: 13,
                                        )),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(color: glovoCardLight, height: 12),
                    Wrap(
                      spacing: 8,
                      children: _customerQuickReplies
                          .map((r) => InkWell(
                                onTap: () => _courierReply(r),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: glovoCardLight,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: glovoMuted
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(r,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _speedometer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed_rounded, color: glovoYellow, size: 18),
          const SizedBox(width: 6),
          Text(_currentSpeedKmh.round().toString(),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
          const SizedBox(width: 3),
          const Text('km/h',
              style: TextStyle(color: glovoMuted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _trafficLightOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: glovoRed.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: glovoRed,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: glovoRed,
                          blurRadius: 16,
                          spreadRadius: 2),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Czerwone światło',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800)),
                Text('${_trafficLightSec}s',
                    style: const TextStyle(
                        color: glovoYellow, fontSize: 14)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _runRedLight,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: glovoOrange,
                    foregroundColor: glovoDark,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.warning_amber_rounded, size: 16),
                  label: const Text('Przejedź',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12)),
                ),
                const SizedBox(height: 4),
                const Text('25% szansy mandatu',
                    style: TextStyle(color: glovoMuted, fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _runRedLight() {
    if (!_trafficLightActive) return;
    HapticFeedback.heavyImpact();
    AudioService.instance.sfx('button_tap.mp3', volume: 0.7);
    final caught = _rng.nextDouble() < 0.25;
    setState(() {
      _trafficLightActive = false;
      _trafficLightSec = 0;
    });
    if (caught) {
      const fine = 50.0;
      setState(() {
        _fuelCost += fine;
        _rating = max(4.20, _rating - 0.10);
      });
      AudioService.instance.sfx('phone_ring.mp3', volume: 0.6);
      _showEventBanner(
          'Mandat za czerwone: −${fine.toStringAsFixed(0)} zł, ocena spada',
          glovoRed);
    } else {
      AudioService.instance.sfx('cash.mp3', volume: 0.4);
      _showEventBanner('Przejechałeś — czysto', glovoGreen);
    }
  }

  Widget _buildStackOfferOverlay(Order o) {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [glovoOrange, glovoRed],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: glovoOrange.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  const Text('Stackuj kolejne zamówienie!',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${_stackOfferCountdown}s',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(o.category.icon, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${o.partner} → ${o.customer}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12)),
                  ),
                  Text(
                      '+${o.basePay.toStringAsFixed(2)} zł',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _declineStack,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white70),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Odrzuć',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _acceptStack,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: glovoRed,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Stackuj',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waitingAtRestaurantView() {
    final o = _currentOrder!;
    final fraction = 1 - (_prepCountdown / o.prepSeconds);
    final phaseStr = _prepPhaseLabel(fraction);
    final queuePos = _prepQueuePos(fraction);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CircularProgressIndicator(
                    value: fraction,
                    strokeWidth: 9,
                    backgroundColor: glovoCardLight,
                    valueColor:
                        const AlwaysStoppedAnimation(glovoYellow),
                  ),
                ),
                Column(
                  children: [
                    Icon(o.category.icon,
                        color: o.category.color, size: 40),
                    const SizedBox(height: 4),
                    Text('${_prepCountdown}s',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: glovoYellow.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.update_rounded,
                      color: glovoYellow, size: 16),
                  const SizedBox(width: 6),
                  Text(phaseStr,
                      style: const TextStyle(
                          color: glovoYellow,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(o.partner,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            Text(o.partnerAddress,
                style: const TextStyle(color: glovoMuted, fontSize: 13)),
            if (queuePos > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: glovoCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline_rounded,
                        color: glovoMuted, size: 14),
                    const SizedBox(width: 4),
                    Text('W kolejce: $queuePos przed Tobą',
                        style: const TextStyle(
                            color: glovoMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Mini progress timeline
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final reached = (fraction * 4).floor() > i;
                final current = (fraction * 4).floor() == i;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 50,
                  height: 6,
                  decoration: BoxDecoration(
                    color: reached
                        ? glovoYellow
                        : current
                            ? glovoYellow.withValues(alpha: 0.4)
                            : glovoCardLight,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  String _prepPhaseLabel(double fraction) {
    if (fraction < 0.25) return 'W kolejce';
    if (fraction < 0.50) return 'Przyjęte przez restaurację';
    if (fraction < 0.75) return 'Gotowanie zamówienia';
    if (fraction < 1.0) return 'Pakowanie';
    return 'Gotowe do odbioru';
  }

  int _prepQueuePos(double fraction) {
    if (fraction >= 0.25) return 0;
    return 3 - (fraction * 12).floor().clamp(0, 3);
  }

  Widget _pickupCodeView() {
    final o = _currentOrder!;
    final shakeOffset = _codeShake ? (_rng.nextInt(8) - 4).toDouble() : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Wpisz kod podany przez obsługę',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('${o.partner} · ${o.partnerAddress}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: glovoMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: glovoCardLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    color: glovoMuted, size: 14),
                const SizedBox(width: 4),
                Text('Kod od restauracji: ${o.pickupCode}',
                    style: const TextStyle(
                        color: glovoMuted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Transform.translate(
            offset: Offset(shakeOffset, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _enteredCode.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 56,
                  height: 70,
                  decoration: BoxDecoration(
                    color: _codeShake
                        ? glovoRed
                        : filled
                            ? glovoYellow
                            : glovoCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _codeShake
                          ? glovoRed
                          : filled
                              ? glovoYellow
                              : glovoCardLight,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                      filled ? _enteredCode[i] : '',
                      style: TextStyle(
                          color: _codeShake
                              ? Colors.white
                              : filled
                                  ? glovoDark
                                  : glovoMuted,
                          fontSize: 32,
                          fontWeight: FontWeight.w900)),
                );
              }),
            ),
          ),
          if (_wrongCodeAttempts > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: Text('Niepoprawnie ($_wrongCodeAttempts)',
                    style: const TextStyle(
                        color: glovoRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          const SizedBox(height: 14),
          Expanded(child: _buildKeypad()),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    Widget key(String label, {VoidCallback? onTap, IconData? icon, Color? color}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                color: color ?? glovoCard,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: icon != null
                  ? Icon(icon, color: glovoMuted, size: 26)
                  : Text(label,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      );
    }

    Widget row(List<Widget> children) =>
        Expanded(child: Row(children: children));

    return Column(
      children: [
        row([
          key('1', onTap: () => _typeKey('1')),
          key('2', onTap: () => _typeKey('2')),
          key('3', onTap: () => _typeKey('3')),
        ]),
        row([
          key('4', onTap: () => _typeKey('4')),
          key('5', onTap: () => _typeKey('5')),
          key('6', onTap: () => _typeKey('6')),
        ]),
        row([
          key('7', onTap: () => _typeKey('7')),
          key('8', onTap: () => _typeKey('8')),
          key('9', onTap: () => _typeKey('9')),
        ]),
        row([
          key('', onTap: null, color: Colors.transparent),
          key('0', onTap: () => _typeKey('0')),
          key('',
              icon: Icons.backspace_outlined, onTap: _backspaceKey),
        ]),
      ],
    );
  }

  Widget _itemsCheckView() {
    final o = _currentOrder!;
    final allChecked = _itemsChecked.length == o.items.length;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Sprawdź i odznacz każdy produkt',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${o.partner}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: glovoMuted, fontSize: 12)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: glovoYellow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: glovoYellow, size: 16),
                const SizedBox(width: 6),
                Text(
                    'Sprawdzono ${_itemsChecked.length}/${o.items.length}',
                    style: const TextStyle(
                        color: glovoYellow,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: o.items.length,
              itemBuilder: (_, idx) {
                final item = o.items[idx];
                final checked = _itemsChecked.contains(idx);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => _toggleItem(idx),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: checked
                            ? glovoGreen.withValues(alpha: 0.15)
                            : glovoCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: checked
                              ? glovoGreen
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: checked
                                  ? glovoGreen
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: checked
                                    ? glovoGreen
                                    : glovoMuted,
                                width: 2,
                              ),
                            ),
                            child: checked
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 18)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: glovoCardLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(emojiForItem(item),
                                style: const TextStyle(fontSize: 24)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(item,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    decoration: checked
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: checked
                                        ? glovoMuted
                                        : Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (allChecked)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: glovoGreen.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_offer_rounded,
                      color: glovoGreen, size: 14),
                  SizedBox(width: 6),
                  Text('Torba zapieczętowana — gotowe do dostawy',
                      style: TextStyle(
                          color: glovoGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cancelledView() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel_rounded, color: glovoOrange, size: 100),
            SizedBox(height: 16),
            Text('Restauracja anulowała zamówienie',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text('Otrzymujesz rekompensatę 5,00 zł',
                style: TextStyle(color: glovoOrange, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _findApartmentView() {
    final o = _currentOrder!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: glovoCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: glovoYellow.withValues(alpha: 0.4), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: glovoYellow.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.apartment_rounded,
                      color: glovoYellow, size: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.customerAddress,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                          'Znajdź mieszkanie $_correctApartment (klatka)',
                          style: const TextStyle(
                              color: glovoMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: glovoYellow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
                'Mieszkanie $_correctApartment'
                '${_wrongApartmentTries > 0 ? " · pomyłki: $_wrongApartmentTries/3" : ""}',
                style: const TextStyle(
                    color: glovoYellow,
                    fontWeight: FontWeight.w800,
                    fontSize: 13)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 0.85,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _apartmentDoors.length,
              itemBuilder: (ctx, i) {
                final n = _apartmentDoors[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _pickApartment(n),
                  child: Container(
                    decoration: BoxDecoration(
                      color: glovoCardLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: glovoMuted.withValues(alpha: 0.3),
                          width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.door_front_door_rounded,
                            color: glovoYellow, size: 30),
                        const SizedBox(height: 4),
                        Text('$n',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _atCustomerView() {
    final o = _currentOrder!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Door icon with knocking animation
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, _) {
                final knocking = _customerPhase == 0;
                final scale = knocking
                    ? (1.0 + 0.05 * sin(_pulseCtrl.value * 6.28 * 4))
                    : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: _customerPhase == 1
                          ? glovoGreen.withValues(alpha: 0.18)
                          : _customerPhase == 3
                              ? glovoBlue.withValues(alpha: 0.18)
                              : glovoYellow.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                        _customerPhase == 1
                            ? Icons.sentiment_very_satisfied_rounded
                            : _customerPhase == 3
                                ? Icons.door_front_door_outlined
                                : Icons.front_hand_rounded,
                        size: 70,
                        color: _customerPhase == 1
                            ? glovoGreen
                            : _customerPhase == 3
                                ? glovoBlue
                                : glovoYellow),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              _customerPhase == 0
                  ? 'Pukam do drzwi…'
                  : _customerPhase == 1
                      ? 'Klient otworzył'
                      : 'Zostaw pod drzwiami',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(o.customer,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            Text(o.customerAddress,
                style: const TextStyle(color: glovoMuted, fontSize: 14)),
            const SizedBox(height: 14),
            if (_customerPhase == 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  3,
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: i < _knockCount
                            ? glovoYellow
                            : glovoCardLight,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('puk-puk-puk',
                  style: TextStyle(color: glovoMuted, fontSize: 12)),
            ],
            if (_customerPhase == 1) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: glovoGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.handshake_rounded,
                        color: glovoGreen, size: 16),
                    SizedBox(width: 6),
                    Text('Wręcz zamówienie do ręki',
                        style: TextStyle(
                            color: glovoGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
            if (_customerPhase == 3) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: glovoBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: glovoBlue),
                    SizedBox(width: 6),
                    Text('Klient prosi o pozostawienie pod drzwiami',
                        style: TextStyle(color: glovoBlue, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _customerCallingView() {
    final o = _currentOrder!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, _) {
                final t = _pulseCtrl.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Opacity(
                        opacity: (1 - ((t + i / 3) % 1.0)).clamp(0.0, 1.0),
                        child: Container(
                          width: 80 + 100 * ((t + i / 3) % 1.0),
                          height: 80 + 100 * ((t + i / 3) % 1.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: glovoBlue.withValues(alpha: 0.6),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: glovoBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.phone_in_talk_rounded,
                          color: Colors.white, size: 40),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('Dzwonię do klienta…',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(o.customer,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: glovoMuted)),
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: glovoCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time_rounded,
                      color: glovoMuted, size: 14),
                  SizedBox(width: 6),
                  Text('Oczekiwanie na odpowiedź…',
                      style: TextStyle(color: glovoMuted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratingView() {
    final o = _currentOrder!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: glovoCard,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('M',
                    style: TextStyle(
                        color: glovoYellow,
                        fontSize: 38,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 16),
            Text('${o.customer} ocenia dostawę',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < _starsRevealed;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    filled
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: filled ? glovoYellow : glovoMuted,
                    size: 44,
                  ),
                );
              }),
            ),
            if (_starsRevealed >= o.customerStars && o.tip > 0) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: glovoGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                    '+ napiwek ${o.tip.toStringAsFixed(2)} zł',
                    style: const TextStyle(
                        color: glovoGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _deliveredView() {
    final o = _currentOrder!;
    final fuel = o.distanceKm * 1.5 * _vehicle.fuelPerKm;
    final net = o.gross - fuel;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: const BoxDecoration(
              color: glovoGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                size: 78, color: Colors.white),
          ),
          const SizedBox(height: 14),
          const Text('Dostarczono!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: glovoCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _payRow('Stawka bazowa', o.basePay),
                if (o.bonusFromSurge > 0.005)
                  _payRow(
                      'Bonus peak (×${o.surge.toStringAsFixed(2)})',
                      o.bonusFromSurge,
                      color: glovoOrange),
                if (o.bonusFromWeather > 0.005)
                  _payRow(
                      'Bonus pogoda (${o.weatherAtPickup.label})',
                      o.bonusFromWeather,
                      color: o.weatherAtPickup.color),
                if (o.tip > 0)
                  _payRow('Napiwek (${o.customerStars}★)', o.tip,
                      color: glovoGreen),
                if (fuel > 0.005)
                  _payRow('Paliwo (${_vehicle.label})', -fuel,
                      color: glovoRed),
                const Divider(height: 18, color: glovoCardLight),
                _payRow('Netto', net, bold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _payRow(String label, double value,
      {Color? color, bool bold = false}) {
    final sign = value >= 0 ? '+' : '−';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: color ?? Colors.white,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                    fontSize: bold ? 16 : 14)),
          ),
          Text('$sign${value.abs().toStringAsFixed(2)} zł',
              style: TextStyle(
                  color: color ?? (bold ? glovoYellow : Colors.white),
                  fontWeight: FontWeight.w800,
                  fontSize: bold ? 18 : 14)),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: glovoCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: _bottomActions(),
    );
  }

  Widget _bottomActions() {
    switch (_state) {
      case CourierState.offline:
        return _bigButton(
          label: 'Rozpocznij zmianę',
          icon: Icons.play_arrow_rounded,
          onTap: _toggleOnline,
        );
      case CourierState.searching:
        return _bigButton(
          label: 'Zakończ zmianę',
          icon: Icons.stop_rounded,
          color: glovoCard,
          textColor: Colors.white,
          border: true,
          onTap: _toggleOnline,
        );
      case CourierState.orderIncoming:
        return Row(
          children: [
            Expanded(
              child: _bigButton(
                label: 'Odrzuć',
                color: glovoCard,
                textColor: glovoRed,
                border: true,
                onTap: () => _rejectOrder(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _bigButton(
                label: 'Akceptuj',
                icon: Icons.check_rounded,
                onTap: _acceptOrder,
              ),
            ),
          ],
        );
      case CourierState.toRestaurant:
      case CourierState.toCustomer:
        return _bigButton(
          label: 'W drodze…',
          color: glovoCard,
          textColor: glovoMuted,
          border: true,
          onTap: null,
        );
      case CourierState.atRestaurantWaiting:
        return _bigButton(
          label: 'Czekam na przygotowanie…',
          color: glovoCard,
          textColor: glovoMuted,
          border: true,
          onTap: null,
        );
      case CourierState.atRestaurantReady:
        return _bigButton(
          label: 'Wpisz kod żeby potwierdzić odbiór',
          color: glovoCard,
          textColor: glovoMuted,
          border: true,
          onTap: null,
        );
      case CourierState.itemsCheck:
        final o = _currentOrder;
        final all = o == null
            ? false
            : _itemsChecked.length == o.items.length;
        return _bigButton(
          label: all
              ? 'Zapieczętuj torbę i ruszaj'
              : 'Sprawdź wszystkie produkty',
          icon: all ? Icons.local_shipping_rounded : null,
          color: all ? glovoYellow : glovoCard,
          textColor: all ? glovoDark : glovoMuted,
          border: !all,
          onTap: all ? _confirmItemsAndDrive : null,
        );
      case CourierState.orderCancelled:
        return _bigButton(
          label: 'Wracam do zamówień…',
          color: glovoCard,
          textColor: glovoOrange,
          border: true,
          onTap: null,
        );
      case CourierState.findingApartment:
        return _bigButton(
          label: 'Znajdź właściwe drzwi',
          color: glovoCard,
          textColor: glovoMuted,
          border: true,
          onTap: null,
        );
      case CourierState.atCustomer:
        if (_customerPhase == 0) {
          return _bigButton(
            label: 'Pukam…',
            color: glovoCard,
            textColor: glovoMuted,
            border: true,
            onTap: null,
          );
        }
        if (_customerPhase == 1) {
          return _bigButton(
            label: 'Wręczyłem zamówienie',
            icon: Icons.handshake_rounded,
            color: glovoGreen,
            textColor: Colors.white,
            onTap: _handOver,
          );
        }
        // phase 3: leave at door — skip handover, go straight to photo
        return _bigButton(
          label: 'Zostawiłem pod drzwiami',
          icon: Icons.door_front_door_outlined,
          color: glovoBlue,
          textColor: Colors.white,
          onTap: _handOver,
        );
      case CourierState.customerCalling:
        return _bigButton(
          label: 'Połączenie w toku…',
          color: glovoCard,
          textColor: glovoBlue,
          border: true,
          onTap: null,
        );
      case CourierState.takingPhoto:
        return _bigButton(
          label: 'Zrób zdjęcie',
          icon: Icons.camera_alt_rounded,
          color: Colors.white,
          textColor: glovoDark,
          onTap: _confirmPhoto,
        );
      case CourierState.ratingPending:
        return _bigButton(
          label: 'Klient ocenia…',
          color: glovoCard,
          textColor: glovoMuted,
          border: true,
          onTap: null,
        );
      case CourierState.delivered:
        return _bigButton(
          label: 'Świetna robota!',
          color: glovoCard,
          textColor: glovoGreen,
          border: true,
          onTap: null,
        );
    }
  }

  Widget _bigButton({
    required String label,
    IconData? icon,
    Color color = glovoYellow,
    Color textColor = glovoDark,
    bool border = false,
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color,
          foregroundColor: textColor,
          disabledForegroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: border
                ? const BorderSide(color: glovoMuted, width: 1)
                : BorderSide.none,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

const Color glovoOrange = Color(0xFFFF8C42);

class _MapPainter extends CustomPainter {
  final double progress;
  final Color pinColor;
  final Weather weather;
  final double rainPhase;
  final IconData vehicleIcon;

  _MapPainter({
    required this.progress,
    required this.pinColor,
    required this.weather,
    required this.rainPhase,
    required this.vehicleIcon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgColor = weather.isRainy
        ? const Color(0xFF1B2030)
        : const Color(0xFF222A3A);
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);

    final grid = Paint()
      ..color = const Color(0xFF2C3447)
      ..strokeWidth = 1;
    const spacing = 28.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final road = Paint()
      ..color = const Color(0xFF3A4763)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final roadPath = Path()
      ..moveTo(size.width * 0.1, size.height * 0.85)
      ..lineTo(size.width * 0.32, size.height * 0.85)
      ..lineTo(size.width * 0.32, size.height * 0.55)
      ..lineTo(size.width * 0.55, size.height * 0.55)
      ..lineTo(size.width * 0.55, size.height * 0.32)
      ..lineTo(size.width * 0.78, size.height * 0.32)
      ..lineTo(size.width * 0.78, size.height * 0.15)
      ..lineTo(size.width * 0.92, size.height * 0.15);
    canvas.drawPath(roadPath, road);

    final traveled = Paint()
      ..color = pinColor
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final metrics = roadPath.computeMetrics().first;
    final segment = metrics.extractPath(0, metrics.length * progress);
    canvas.drawPath(segment, traveled);

    final endPos = metrics.getTangentForOffset(metrics.length)?.position;
    if (endPos != null) {
      canvas.drawCircle(endPos, 11, Paint()..color = pinColor);
      canvas.drawCircle(endPos, 5, Paint()..color = Colors.white);
    }

    final courierPos =
        metrics.getTangentForOffset(metrics.length * progress)?.position;
    if (courierPos != null) {
      canvas.drawCircle(courierPos, 16, Paint()..color = glovoYellow);
      canvas.drawCircle(courierPos, 13, Paint()..color = glovoDark);
      final iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(vehicleIcon.codePoint),
          style: TextStyle(
            fontSize: 16,
            color: glovoYellow,
            fontFamily: vehicleIcon.fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      iconPainter.paint(
        canvas,
        courierPos.translate(
            -iconPainter.width / 2, -iconPainter.height / 2),
      );
    }

    if (weather.isRainy) {
      final drops = weather == Weather.heavyRain ? 60 : 30;
      final dropPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1.5;
      final r = Random(42);
      for (var i = 0; i < drops; i++) {
        final baseX = r.nextDouble() * size.width;
        final phase = (rainPhase + r.nextDouble()) % 1.0;
        final y = phase * size.height;
        canvas.drawLine(
          Offset(baseX, y),
          Offset(baseX - 4, y + 10),
          dropPaint,
        );
      }
    }

  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.progress != progress ||
      old.pinColor != pinColor ||
      old.weather != weather ||
      old.rainPhase != rainPhase;
}

class _Corner extends StatelessWidget {
  final bool top;
  final bool left;
  const _Corner({required this.top, required this.left});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _CornerPainter(top: top, left: left),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool top;
  final bool left;
  _CornerPainter({required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = glovoYellow
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final hStart =
        left ? const Offset(0, 0) : Offset(size.width, 0);
    final hEnd = left
        ? Offset(size.width * 0.6, 0)
        : Offset(size.width * 0.4, 0);
    final hStart2 = top ? hStart : Offset(hStart.dx, size.height);
    final hEnd2 = top ? hEnd : Offset(hEnd.dx, size.height);
    canvas.drawLine(hStart2, hEnd2, p);

    final vStart = top ? hStart2 : Offset(hStart2.dx, size.height);
    final vEnd =
        top ? Offset(hStart2.dx, size.height * 0.6) : Offset(hStart2.dx, size.height * 0.4);
    canvas.drawLine(vStart, vEnd, p);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) => false;
}

class _DoorPainter extends CustomPainter {
  final double time;
  _DoorPainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF1A1F2A);
    canvas.drawRect(Offset.zero & size, bg);

    // Floor line
    final floorY = size.height * 0.78;
    canvas.drawRect(
        Rect.fromLTWH(0, floorY, size.width, size.height - floorY),
        Paint()..color = const Color(0xFF20262F));

    // Door
    final doorW = size.width * 0.42;
    final doorH = size.height * 0.65;
    final doorX = (size.width - doorW) / 2;
    final doorY = floorY - doorH;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(doorX, doorY, doorW, doorH),
          const Radius.circular(6)),
      Paint()..color = const Color(0xFF3A2D1E),
    );
    // Door panels
    final panelPaint = Paint()
      ..color = const Color(0xFF2C2218)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final inset = 12.0;
    canvas.drawRect(
      Rect.fromLTWH(doorX + inset, doorY + inset,
          doorW - inset * 2, doorH * 0.35),
      panelPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
          doorX + inset,
          doorY + doorH * 0.45 + inset,
          doorW - inset * 2,
          doorH * 0.45),
      panelPaint,
    );
    // Knob
    canvas.drawCircle(
      Offset(doorX + doorW - 14, doorY + doorH * 0.5),
      4,
      Paint()..color = const Color(0xFFC9A36A),
    );

    // Doormat
    canvas.drawRect(
      Rect.fromLTWH(doorX - 18, floorY - 10, doorW + 36, 12),
      Paint()..color = const Color(0xFF4A3F35),
    );

    // Bag (the order)
    final bagX = size.width / 2 - 28;
    final bagY = floorY - 50;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(bagX, bagY, 56, 50),
          const Radius.circular(8)),
      Paint()..color = glovoYellow,
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'glovo',
        style: TextStyle(
          color: glovoDark,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(bagX + 28 - tp.width / 2, bagY + 18));

    // Bag handle
    canvas.drawArc(
      Rect.fromLTWH(bagX + 14, bagY - 14, 28, 18),
      3.14,
      3.14,
      false,
      Paint()
        ..color = glovoYellow
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _DoorPainter old) => old.time != time;
}
