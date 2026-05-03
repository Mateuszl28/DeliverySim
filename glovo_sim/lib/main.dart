import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const GlovoSimApp());
}

const Color glovoYellow = Color(0xFFFFC244);
const Color glovoDark = Color(0xFF13171F);
const Color glovoCard = Color(0xFF1C2230);
const Color glovoMuted = Color(0xFF8B93A7);
const Color glovoGreen = Color(0xFF2BD17E);
const Color glovoRed = Color(0xFFFF5A5F);

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
        fontFamily: 'Roboto',
      ),
      home: const CourierHome(),
    );
  }
}

enum CourierState {
  offline,
  searching,
  orderIncoming,
  toRestaurant,
  atRestaurant,
  toCustomer,
  atCustomer,
  delivered,
}

class Order {
  final String restaurant;
  final String restaurantAddress;
  final String customer;
  final String customerAddress;
  final int items;
  final double distanceKm;
  final double payout;
  final List<String> orderItems;

  Order({
    required this.restaurant,
    required this.restaurantAddress,
    required this.customer,
    required this.customerAddress,
    required this.items,
    required this.distanceKm,
    required this.payout,
    required this.orderItems,
  });
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

  Timer? _searchTimer;
  Timer? _orderTimer;
  Timer? _progressTimer;
  int _orderCountdown = 0;
  double _routeProgress = 0;

  int _completed = 0;
  int _rejected = 0;
  double _earnings = 0;
  double _rating = 4.92;
  int _onlineSeconds = 0;
  Timer? _onlineTimer;

  late final AnimationController _pulseCtrl;

  static const _restaurants = [
    ('McDonald\'s', 'ul. Marszałkowska 12'),
    ('KFC', 'ul. Świętokrzyska 30'),
    ('Sushi Wok', 'ul. Nowy Świat 44'),
    ('Pasibus', 'ul. Krucza 16'),
    ('Pizza Hut', 'ul. Złota 59'),
    ('Burger King', 'ul. Jana Pawła 21'),
    ('Berlin Döner', 'ul. Bracka 8'),
    ('Thai Wok', 'ul. Hoża 27'),
    ('North Fish', 'ul. Wilcza 50'),
    ('Bobby Burger', 'ul. Mokotowska 11'),
  ];

  static const _customers = [
    ('Anna K.', 'ul. Puławska 102 / 14'),
    ('Marek W.', 'ul. Grójecka 77 / 8'),
    ('Karolina B.', 'ul. Wolska 145 / 22'),
    ('Tomasz Z.', 'ul. Marszałkowska 88 / 5'),
    ('Ewa N.', 'ul. Belwederska 19 / 3'),
    ('Piotr S.', 'al. KEN 36 / 41'),
    ('Julia D.', 'ul. Wawelska 60 / 17'),
    ('Bartek L.', 'ul. Solec 24 / 9'),
    ('Magda R.', 'ul. Czerniakowska 178 / 12'),
  ];

  static const _foods = [
    'Big Mac',
    'McNuggets 9 szt.',
    'Coca-Cola 0.5L',
    'Cheeseburger',
    'Frytki duże',
    'Pizza Pepperoni',
    'Sushi Set 24',
    'Pad Thai',
    'Kebab XL',
    'Whopper',
    'Lody McFlurry',
    'Burrito',
    'Sałatka Cezar',
    'Tortilla',
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _searchTimer?.cancel();
    _orderTimer?.cancel();
    _progressTimer?.cancel();
    _onlineTimer?.cancel();
    super.dispose();
  }

  void _toggleOnline() {
    if (_state == CourierState.offline) {
      setState(() => _state = CourierState.searching);
      _onlineTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _onlineSeconds++);
      });
      _scheduleNextOrder();
    } else {
      _resetEverything();
      setState(() => _state = CourierState.offline);
    }
  }

  void _resetEverything() {
    _searchTimer?.cancel();
    _orderTimer?.cancel();
    _progressTimer?.cancel();
    _onlineTimer?.cancel();
    _currentOrder = null;
    _routeProgress = 0;
  }

  void _scheduleNextOrder() {
    _searchTimer?.cancel();
    final delay = 3 + _rng.nextInt(6);
    _searchTimer = Timer(Duration(seconds: delay), () {
      if (!mounted) return;
      if (_state != CourierState.searching) return;
      _spawnOrder();
    });
  }

  void _spawnOrder() {
    final r = _restaurants[_rng.nextInt(_restaurants.length)];
    final c = _customers[_rng.nextInt(_customers.length)];
    final itemsCount = 1 + _rng.nextInt(4);
    final foods = <String>[];
    for (var i = 0; i < itemsCount; i++) {
      foods.add(_foods[_rng.nextInt(_foods.length)]);
    }
    final dist = 0.6 + _rng.nextDouble() * 3.4;
    final payout = 6.50 + dist * 2.30 + _rng.nextDouble() * 2;

    setState(() {
      _currentOrder = Order(
        restaurant: r.$1,
        restaurantAddress: r.$2,
        customer: c.$1,
        customerAddress: c.$2,
        items: itemsCount,
        distanceKm: double.parse(dist.toStringAsFixed(1)),
        payout: double.parse(payout.toStringAsFixed(2)),
        orderItems: foods,
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
    _runRoute(onComplete: () {
      if (!mounted) return;
      setState(() => _state = CourierState.atRestaurant);
    });
  }

  void _rejectOrder({bool timedOut = false}) {
    _orderTimer?.cancel();
    setState(() {
      _rejected++;
      _rating = max(4.20, _rating - (timedOut ? 0.04 : 0.02));
      _currentOrder = null;
      _state = CourierState.searching;
    });
    if (timedOut) {
      _toast('Zamówienie wygasło — kolejka spada', glovoRed);
    }
    _scheduleNextOrder();
  }

  void _pickedUp() {
    setState(() {
      _state = CourierState.toCustomer;
      _routeProgress = 0;
    });
    _runRoute(onComplete: () {
      if (!mounted) return;
      setState(() => _state = CourierState.atCustomer);
    });
  }

  void _completeDelivery() {
    final o = _currentOrder!;
    setState(() {
      _state = CourierState.delivered;
      _completed++;
      _earnings += o.payout;
      _rating = min(5.0, _rating + 0.01);
    });
    _toast('+ ${o.payout.toStringAsFixed(2)} zł', glovoGreen);
    Timer(const Duration(milliseconds: 1800), () {
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
    _progressTimer?.cancel();
    final totalSteps = 50 + _rng.nextInt(30);
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
        duration: const Duration(milliseconds: 1500),
      ));
  }

  String _formatTime(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        color: glovoCard,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: glovoYellow,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('M',
                      style: TextStyle(
                          color: glovoDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 22)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mateusz · Kurier',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 16, color: glovoYellow),
                        const SizedBox(width: 4),
                        Text(_rating.toStringAsFixed(2),
                            style: const TextStyle(
                                color: glovoMuted, fontSize: 13)),
                        const SizedBox(width: 12),
                        Icon(Icons.circle,
                            size: 8,
                            color: online ? glovoGreen : glovoMuted),
                        const SizedBox(width: 4),
                        Text(online ? 'Online' : 'Offline',
                            style: TextStyle(
                                color: online ? glovoGreen : glovoMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              Switch(
                value: online,
                activeThumbColor: glovoDark,
                activeTrackColor: glovoYellow,
                onChanged: (_) => _toggleOnline(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statTile(Icons.payments_rounded,
                  '${_earnings.toStringAsFixed(2)} zł', 'Zarobki'),
              _statTile(Icons.local_shipping_rounded, '$_completed', 'Dostawy'),
              _statTile(
                  Icons.timer_outlined, _formatTime(_onlineSeconds), 'Czas'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: glovoDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: glovoYellow, size: 18),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14)),
            Text(label,
                style: const TextStyle(color: glovoMuted, fontSize: 11)),
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
      case CourierState.atRestaurant:
        return _atLocationView(
          icon: Icons.restaurant_rounded,
          title: 'Jesteś w restauracji',
          subtitle: _currentOrder!.restaurant,
          address: _currentOrder!.restaurantAddress,
        );
      case CourierState.atCustomer:
        return _atLocationView(
          icon: Icons.home_rounded,
          title: 'Jesteś u klienta',
          subtitle: _currentOrder!.customer,
          address: _currentOrder!.customerAddress,
        );
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
              'Włącz tryb online, żeby otrzymywać zamówienia.',
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
              builder: (_, __) {
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
                        child: const Icon(Icons.search_rounded,
                            color: glovoDark, size: 36),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('Szukamy zamówień…',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Pozostań w pobliżu restauracji w centrum',
                style: TextStyle(color: glovoMuted)),
            if (_rejected > 0) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: glovoCard,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Odrzucone dziś: $_rejected',
                    style: const TextStyle(color: glovoMuted)),
              ),
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
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: CircularProgressIndicator(
                  value: _orderCountdown / 15,
                  strokeWidth: 7,
                  backgroundColor: glovoCard,
                  valueColor: AlwaysStoppedAnimation(
                    _orderCountdown > 5 ? glovoYellow : glovoRed,
                  ),
                ),
              ),
              Column(
                children: [
                  Text('$_orderCountdown',
                      style: const TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w900)),
                  const Text('sekund',
                      style: TextStyle(color: glovoMuted, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Nowe zamówienie!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
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
                    _badge(Icons.shopping_bag_rounded, '${o.items} szt.'),
                    _badge(Icons.payments_rounded,
                        '${o.payout.toStringAsFixed(2)} zł',
                        highlight: true),
                  ],
                ),
                const SizedBox(height: 16),
                _routePoint(Icons.restaurant_rounded, glovoYellow,
                    o.restaurant, o.restaurantAddress),
                Padding(
                  padding: const EdgeInsets.only(left: 19),
                  child: Container(width: 2, height: 24, color: glovoMuted),
                ),
                _routePoint(Icons.home_rounded, glovoGreen, o.customer,
                    o.customerAddress),
                const Divider(height: 28, color: glovoDark),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    o.orderItems.map((e) => '• $e').join('\n'),
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
        const SizedBox(height: 6),
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
    final destinationName = goingToRestaurant ? o.restaurant : o.customer;
    final destinationAddr =
        goingToRestaurant ? o.restaurantAddress : o.customerAddress;
    final eta = ((1 - _routeProgress) * o.distanceKm * 3).ceil();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: glovoCard,
                borderRadius: BorderRadius.circular(20),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CustomPaint(
                  painter: _MapPainter(
                    progress: _routeProgress,
                    pinColor: goingToRestaurant ? glovoYellow : glovoGreen,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
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
                          ? Icons.restaurant_rounded
                          : Icons.home_rounded,
                      color: goingToRestaurant ? glovoYellow : glovoGreen,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goingToRestaurant
                                ? 'Jedziesz do restauracji'
                                : 'Jedziesz do klienta',
                            style: const TextStyle(
                                color: glovoMuted, fontSize: 12),
                          ),
                          Text(destinationName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          Text(destinationAddr,
                              style: const TextStyle(
                                  color: glovoMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('~$eta min',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(
                            '${(o.distanceKm * (1 - _routeProgress)).toStringAsFixed(1)} km',
                            style: const TextStyle(
                                color: glovoMuted, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _routeProgress,
                    minHeight: 8,
                    backgroundColor: glovoDark,
                    valueColor: AlwaysStoppedAnimation(
                      goingToRestaurant ? glovoYellow : glovoGreen,
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

  Widget _atLocationView({
    required IconData icon,
    required String title,
    required String subtitle,
    required String address,
  }) {
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
                color: glovoYellow.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 60, color: glovoYellow),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(address,
                style: const TextStyle(color: glovoMuted, fontSize: 14)),
            if (_state == CourierState.atRestaurant) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: glovoCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sprawdź zamówienie:',
                        style: TextStyle(color: glovoMuted, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(
                      _currentOrder!.orderItems
                          .map((e) => '✓ $e')
                          .join('\n'),
                      style: const TextStyle(fontSize: 14, height: 1.6),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _deliveredView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 130,
              height: 130,
              decoration: const BoxDecoration(
                color: glovoGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  size: 90, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text('Dostarczono!',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              '+ ${_currentOrder!.payout.toStringAsFixed(2)} zł',
              style: const TextStyle(
                  fontSize: 22,
                  color: glovoGreen,
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
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
      case CourierState.atRestaurant:
        return _bigButton(
          label: 'Odebrałem zamówienie',
          icon: Icons.shopping_bag_rounded,
          onTap: _pickedUp,
        );
      case CourierState.atCustomer:
        return _bigButton(
          label: 'Zakończ dostawę',
          icon: Icons.done_all_rounded,
          color: glovoGreen,
          textColor: Colors.white,
          onTap: _completeDelivery,
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

class _MapPainter extends CustomPainter {
  final double progress;
  final Color pinColor;

  _MapPainter({required this.progress, required this.pinColor});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF222A3A);
    canvas.drawRect(Offset.zero & size, bg);

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
      ..lineTo(size.width * 0.35, size.height * 0.85)
      ..lineTo(size.width * 0.35, size.height * 0.45)
      ..lineTo(size.width * 0.7, size.height * 0.45)
      ..lineTo(size.width * 0.7, size.height * 0.18)
      ..lineTo(size.width * 0.9, size.height * 0.18);
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
      canvas.drawCircle(endPos, 10, Paint()..color = pinColor);
      canvas.drawCircle(endPos, 5, Paint()..color = Colors.white);
    }

    final courierPos =
        metrics.getTangentForOffset(metrics.length * progress)?.position;
    if (courierPos != null) {
      canvas.drawCircle(courierPos, 14, Paint()..color = glovoYellow);
      canvas.drawCircle(courierPos, 8, Paint()..color = glovoDark);
      final tp = TextPainter(
        text: const TextSpan(
            text: '🛵', style: TextStyle(fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, courierPos.translate(-tp.width / 2, -tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.progress != progress || old.pinColor != pinColor;
}
