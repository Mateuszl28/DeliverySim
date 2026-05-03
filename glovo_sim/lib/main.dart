import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const GlovoSimApp());

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
  })  : tip = 0,
        customerStars = 5;

  double get adjustedPay => basePay * surge * weatherAtPickup.bonus;
  double get gross => adjustedPay + tip;
  double get bonusFromSurge => basePay * (surge - 1.0);
  double get bonusFromWeather => basePay * surge * (weatherAtPickup.bonus - 1.0);
}

enum CourierState {
  offline,
  searching,
  orderIncoming,
  toRestaurant,
  atRestaurantWaiting,
  atRestaurantReady,
  orderCancelled,
  toCustomer,
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
    return double.parse(s.toStringAsFixed(2));
  }

  bool get _isPeak => _surgeMultiplier >= 1.4;

  int _baseDelaySec() {
    final h = _simHour;
    int base;
    if (h >= 11 && h < 14) base = 4;
    else if (h >= 18 && h < 22) base = 4;
    else if (h >= 14 && h < 17) base = 7;
    else if (h >= 22 || h < 7) base = 18;
    else if (h >= 7 && h < 11) base = 9;
    else base = 8;
    if (_weather == Weather.rainy) base = (base * 0.75).round();
    if (_weather == Weather.heavyRain) base = (base * 0.6).round();
    return max(2, base);
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
      });
    });
  }

  void _maybeChangeWeather() {
    final r = _rng.nextDouble();
    final transitions = {
      Weather.sunny: [
        (Weather.sunny, 0.5),
        (Weather.cloudy, 0.45),
        (Weather.rainy, 0.05),
      ],
      Weather.cloudy: [
        (Weather.sunny, 0.3),
        (Weather.cloudy, 0.35),
        (Weather.rainy, 0.30),
        (Weather.heavyRain, 0.05),
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
    final list = transitions[_weather]!;
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

  // ===== SHIFT MANAGEMENT =====

  void _toggleOnline() {
    if (_state == CourierState.offline) {
      _showVehiclePicker();
    } else {
      _stopShift();
    }
  }

  void _stopShift() {
    _resetTimers();
    setState(() {
      _state = CourierState.offline;
      _currentOrder = null;
      _routeProgress = 0;
    });
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
    final itemsCount = 1 + _rng.nextInt(itemCountMax);
    final items = <String>[];
    for (var i = 0; i < itemsCount; i++) {
      items.add(pool[_rng.nextInt(pool.length)]);
    }
    final dist = 0.6 + _rng.nextDouble() * 3.4;
    final basePay = 5.50 + dist * 2.10 + _rng.nextDouble() * 1.5;
    final code = (1000 + _rng.nextInt(8999)).toString();
    final prep = cat == OrderCategory.food
        ? 4 + _rng.nextInt(7)
        : cat == OrderCategory.grocery
            ? 3 + _rng.nextInt(5)
            : 2 + _rng.nextInt(4);
    final willCancel = _rng.nextDouble() < 0.06;

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
      );
      _state = CourierState.orderIncoming;
      _orderCountdown = 15;
    });

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

  void _confirmPickup() {
    setState(() {
      _state = CourierState.toCustomer;
      _routeProgress = 0;
    });
    _runRoute(onComplete: () {
      if (!mounted) return;
      setState(() => _state = CourierState.atCustomer);
    });
  }

  void _handOver() {
    final o = _currentOrder!;
    o.tip = _rollTip(o.adjustedPay);
    o.customerStars = _rollCustomerStars();
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

  double _rollTip(double base) {
    final r = _rng.nextDouble();
    if (r < 0.50) return 0;
    if (r < 0.80) return double.parse((1 + _rng.nextDouble() * 2).toStringAsFixed(2));
    if (r < 0.95) return double.parse((3 + _rng.nextDouble() * 4).toStringAsFixed(2));
    return double.parse((7 + _rng.nextDouble() * 8).toStringAsFixed(2));
  }

  int _rollCustomerStars() {
    final r = _rng.nextDouble();
    if (r < 0.78) return 5;
    if (r < 0.93) return 4;
    if (r < 0.98) return 3;
    if (r < 0.995) return 2;
    return 1;
  }

  void _finalizeDelivery() {
    final o = _currentOrder!;
    final fuel = o.distanceKm * 1.5 * _vehicle.fuelPerKm;
    setState(() {
      _completed++;
      _gross += o.gross;
      _fuelCost += fuel;
      _rating = (_rating * 0.92 + o.customerStars * 0.08);
      _state = CourierState.delivered;
    });
    Timer(const Duration(milliseconds: 3500), () {
      if (!mounted) return;
      setState(() {
        _currentOrder = null;
        _state = CourierState.searching;
        _routeProgress = 0;
      });
      _scheduleNextOrder();
    });
  }

  void _runRoute({required VoidCallback onComplete}) {
    final o = _currentOrder!;
    _progressTimer?.cancel();
    final totalSec = (o.distanceKm * _vehicle.secPerKm).clamp(2.5, 30);
    final totalSteps = (totalSec * 10).round();
    var step = 0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      step++;
      setState(() => _routeProgress = step / totalSteps);
      if (step >= totalSteps) {
        t.cancel();
        onComplete();
      }
    });
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
            _buildBottomBar(),
          ],
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
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: glovoYellow,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('M',
                      style: TextStyle(
                          color: glovoDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 20)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Mateusz',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(width: 6),
                        Icon(_vehicle.icon, size: 14, color: glovoMuted),
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
              if (online) _weatherChip(),
              const SizedBox(width: 8),
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
      case CourierState.orderCancelled:
        return _cancelledView();
      case CourierState.atCustomer:
        return _atCustomerView();
      case CourierState.ratingPending:
        return _ratingView();
      case CourierState.delivered:
        return _deliveredView();
    }
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
                    o.items.map((e) => '• $e').join('\n'),
                    style: const TextStyle(
                        color: glovoMuted, fontSize: 13, height: 1.5),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
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
    );
  }

  Widget _waitingAtRestaurantView() {
    final o = _currentOrder!;
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
                  width: 130,
                  height: 130,
                  child: CircularProgressIndicator(
                    value: 1 - (_prepCountdown / o.prepSeconds),
                    strokeWidth: 8,
                    backgroundColor: glovoCardLight,
                    valueColor:
                        const AlwaysStoppedAnimation(glovoYellow),
                  ),
                ),
                Column(
                  children: [
                    Icon(o.category.icon,
                        color: o.category.color, size: 38),
                    const SizedBox(height: 4),
                    Text('${_prepCountdown}s',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Zamówienie się przygotowuje',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(o.partner,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            Text(o.partnerAddress,
                style: const TextStyle(color: glovoMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _pickupCodeView() {
    final o = _currentOrder!;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Pokaż kod obsłudze',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${o.partner} · ${o.partnerAddress}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: glovoMuted, fontSize: 13)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: o.pickupCode.split('').map((d) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 56,
                  height: 72,
                  decoration: BoxDecoration(
                    color: glovoYellow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(d,
                      style: const TextStyle(
                          color: glovoDark,
                          fontSize: 36,
                          fontWeight: FontWeight.w900)),
                )).toList(),
          ),
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
                const Text('Sprawdź zawartość:',
                    style:
                        TextStyle(color: glovoMuted, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  o.items.map((e) => '✓ $e').join('\n'),
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
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

  Widget _atCustomerView() {
    final o = _currentOrder!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: glovoGreen.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.home_rounded,
                  size: 60, color: glovoGreen),
            ),
            const SizedBox(height: 16),
            const Text('Jesteś u klienta',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(o.customer,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            Text(o.customerAddress,
                style: const TextStyle(color: glovoMuted, fontSize: 14)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: glovoCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: glovoMuted),
                  SizedBox(width: 6),
                  Text(
                      'Zostaw zamówienie pod drzwiami i potwierdź dostawę',
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
          label: 'Potwierdzam odbiór',
          icon: Icons.shopping_bag_rounded,
          onTap: _confirmPickup,
        );
      case CourierState.orderCancelled:
        return _bigButton(
          label: 'Wracam do zamówień…',
          color: glovoCard,
          textColor: glovoOrange,
          border: true,
          onTap: null,
        );
      case CourierState.atCustomer:
        return _bigButton(
          label: 'Wręczyłem zamówienie',
          icon: Icons.done_all_rounded,
          color: glovoGreen,
          textColor: Colors.white,
          onTap: _handOver,
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
