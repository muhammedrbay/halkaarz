import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/firebase_service.dart';
import 'services/data_service.dart';
import 'services/portfolio_service.dart';
import 'screens/home_screen.dart';
import 'screens/portfolio_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive başlat
  await Hive.initFlutter();
  await DataService.init();
  await PortfolioService.init();

  // Firebase başlat (hata olursa uygulama yine çalışır)
  try {
    await FirebaseService.init();
  } catch (e) {
    debugPrint('Firebase başlatılamadı, bildirimler devre dışı: $e');
  }

  runApp(const HalkaArzApp());
}

class HalkaArzApp extends StatelessWidget {
  const HalkaArzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Halka Arz Takip',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const MainNavigationScreen(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0A0E21),
      primaryColor: const Color(0xFF00D4AA),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00D4AA),
        secondary: Color(0xFF00B4D8),
        surface: Color(0xFF1A1F38),
        error: Color(0xFFFF4757),
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1A1F38),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: const Color(0xFF00D4AA),
        unselectedLabelColor: Colors.white54,
        indicatorColor: const Color(0xFF00D4AA),
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final _screens = const [
    HomeScreen(),
    PortfolioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12162B),
          border: Border(
            top: BorderSide(color: Color(0xFF2A2F4A), width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF00D4AA),
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.trending_up_rounded),
              activeIcon: Icon(Icons.trending_up_rounded, size: 28),
              label: 'Halka Arzlar',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet_rounded, size: 28),
              label: 'Cüzdan',
            ),
          ],
        ),
      ),
    );
  }
}
