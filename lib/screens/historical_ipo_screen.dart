import 'dart:async';
import 'dart:math' show max;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/historical_ipo_service.dart';
import '../services/realtime_price_service.dart';
import 'historical_ipo_detail_screen.dart';

enum _Filter { hepsi, tavanlar, katilim }

class HistoricalIpoScreen extends StatefulWidget {
  const HistoricalIpoScreen({super.key});

  @override
  State<HistoricalIpoScreen> createState() => _HistoricalIpoScreenState();
}

class _HistoricalIpoScreenState extends State<HistoricalIpoScreen>
    with AutomaticKeepAliveClientMixin {
  List<HistoricalIpo> _ipos = [];
  bool _isLoading = true;
  bool _fetchingPrices = false;
  _Filter _filter = _Filter.hepsi;
  Timer? _priceRefreshTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _priceRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    // 1. Cache'ten anında yükle
    final cached = HistoricalIpoService.loadFromCache();
    if (cached.isNotEmpty) {
      setState(() {
        _ipos = cached;
        _isLoading = false;
      });
    }

    // 2. GitHub'dan güncel static JSON çek (24h cache)
    final fresh = await HistoricalIpoService.loadAll();
    if (mounted && fresh.isNotEmpty) {
      setState(() {
        _ipos = fresh;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }

    // 3. RTDB'den canlı fiyatları tek seferlik çek
    await _fetchPrices(forceRefresh: false);

    // 5. 15 dakikada bir fiyatları otomatik yenile
    _priceRefreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _fetchPrices(forceRefresh: false),
    );
  }

  Future<void> _fetchPrices({bool forceRefresh = false}) async {
    if (!forceRefresh && _fetchingPrices) return;
    if (mounted) setState(() => _fetchingPrices = true);

    final prices = await RealtimePriceService.fetchAll(
      forceRefresh: forceRefresh,
    );
    if (mounted && prices.isNotEmpty) {
      HistoricalIpoService.applyRtdbPrices(_ipos, prices);
      await HistoricalIpoService.saveToCache(_ipos);
    }
    if (mounted) setState(() => _fetchingPrices = false);
  }

  Future<void> _fullRefresh() async {
    // Tüm cache'i sıfırla ve yeniden çek
    final metaBox = Hive.box('historical_ipos_meta');
    await metaBox.delete('static_fetched_at');

    final fresh = await HistoricalIpoService.loadAll();
    if (mounted) setState(() => _ipos = fresh);

    await _fetchPrices(forceRefresh: true);
  }

  List<HistoricalIpo> get _filtered {
    switch (_filter) {
      case _Filter.hepsi:
        return _ipos;
      case _Filter.tavanlar:
        return _ipos
            .where((i) => i.tavanMi || (i.tavanGunSayisi ?? 0) > 0)
            .toList();
      case _Filter.katilim:
        return _ipos.where((i) => i.katilimEndeksi).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0E21), Color(0xFF0F1328)],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilters(),
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
                ),
              )
            else
              Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final lastFetch = RealtimePriceService.lastFetch;
    final fetchInfo = lastFetch != null
        ? '${DateTime.now().difference(lastFetch).inMinutes} dk önce'
        : 'Henüz yok';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.analytics_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Performans',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${_ipos.length} şirket · fiyat: $fetchInfo',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          if (_fetchingPrices)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF00D4AA),
                ),
              ),
            ),
          IconButton(
            onPressed: _fetchingPrices ? null : _fullRefresh,
            icon: Icon(
              Icons.refresh_rounded,
              color: _fetchingPrices ? Colors.white24 : const Color(0xFF7C3AED),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final tavanCount = _ipos
        .where((i) => i.tavanMi || (i.tavanGunSayisi ?? 0) > 0)
        .length;
    final katilimCount = _ipos.where((i) => i.katilimEndeksi).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _buildChip(
            'Tümü (${_ipos.length})',
            Icons.list_rounded,
            _Filter.hepsi,
          ),
          const SizedBox(width: 8),
          _buildChip(
            'Tavan Alan ($tavanCount)',
            Icons.rocket_launch_rounded,
            _Filter.tavanlar,
            color: const Color(0xFF00D4AA),
          ),
          const SizedBox(width: 8),
          _buildChip(
            'Katılım ($katilimCount)',
            Icons.verified_rounded,
            _Filter.katilim,
            color: const Color(0xFF3B82F6),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(
    String label,
    IconData icon,
    _Filter f, {
    Color color = const Color(0xFF7C3AED),
  }) {
    final selected = _filter == f;
    return GestureDetector(
      onTap: () => setState(() => _filter = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : const Color(0xFF1A1F38),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : const Color(0xFF2A2F4A),
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? color : Colors.white38),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? color : Colors.white54,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'Bu filtrede sonuç yok',
          style: GoogleFonts.inter(color: Colors.white38),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fullRefresh,
      color: const Color(0xFF7C3AED),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 90),
        itemCount: filtered.length,
        itemBuilder: (ctx, i) => _IpoCard(
          ipo: filtered[i],
          onTap: () => Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => HistoricalIpoDetailScreen(ipo: filtered[i]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── IPO Card ────────────────────────────────────────────────────────────────

class _IpoCard extends StatelessWidget {
  final HistoricalIpo ipo;
  final VoidCallback onTap;

  const _IpoCard({required this.ipo, required this.onTap});

  Color get _renk {
    final g = ipo.getiviYuzde;
    if (g >= 50) return const Color(0xFF00D4AA);
    if (g >= 10) return const Color(0xFF4CAF50);
    if (g >= 0) return const Color(0xFF8BC34A);
    return const Color(0xFFFF4757);
  }

  @override
  Widget build(BuildContext context) {
    final renk = _renk;
    final getiri = ipo.getiviYuzde;
    final isPos = getiri >= 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F38),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ipo.tavanMi
                ? const Color(0xFF00D4AA).withValues(alpha: 0.5)
                : renk.withValues(alpha: 0.1),
            width: ipo.tavanMi ? 1.5 : 0.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // Üst: kod · ad · badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: renk.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ipo.sirketKodu,
                      style: GoogleFonts.inter(
                        color: renk,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ipo.sirketAdi,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (ipo.tavanMi)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00D4AA), Color(0xFF00B4D8)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '🚀 TAVAN',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else if (ipo.katilimEndeksi)
                    const Icon(
                      Icons.verified,
                      color: Color(0xFF3B82F6),
                      size: 16,
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // Orta: Fiyatlar
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ipo.guncelFiyat != null
                            ? '₺${ipo.guncelFiyat!.toStringAsFixed(2)}'
                            : '₺${ipo.arzFiyati.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (ipo.guncelFiyat != null)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: renk.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${isPos ? '+' : ''}%${getiri.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  color: renk,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'arzdan getiri',
                              style: GoogleFonts.inter(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'Henüz veri yok',
                          style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (ipo.guncelFiyat != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Arz Fiyatı',
                          style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '₺${ipo.arzFiyati.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 20),

              // GRAFİK (Tam Boy)
              SizedBox(
                height: 70,
                width: double.infinity,
                child: ipo.sparkline.length >= 3
                    ? _Sparkline(prices: ipo.sparkline, color: renk)
                    : Center(
                        child: ipo.staticFetched == true
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.show_chart_rounded,
                                    color: Colors.white12,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Grafik verisi yok',
                                    style: GoogleFonts.inter(
                                      color: Colors.white24,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF7C3AED),
                                ),
                              ),
                      ),
              ),

              const SizedBox(height: 16),
              const Divider(color: Color(0xFF2A2F4A), height: 1),
              const SizedBox(height: 12),

              // Alt: istatistikler
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stat(
                    'Kişi Başı',
                    '${ipo.kisiBasiLot} lot',
                    Icons.person_outline_rounded,
                  ),
                  _stat('Toplam', _fmt(ipo.toplamLot), Icons.bar_chart_rounded),
                  _stat(
                    'Tavan',
                    ipo.tavanGunSayisi != null
                        ? '${ipo.tavanGunSayisi} gün'
                        : '—',
                    Icons.trending_up_rounded,
                    color: (ipo.tavanGunSayisi ?? 0) > 0
                        ? const Color(0xFF00D4AA)
                        : null,
                  ),
                  _stat(
                    'İşlem',
                    _date(ipo.islemTarihi),
                    Icons.calendar_today_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, size: 12, color: color ?? Colors.white24),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            color: color ?? Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white24, fontSize: 9),
        ),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }

  String _date(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year.toString().substring(2)}';
}

// ─── Sparkline ───────────────────────────────────────────────────────────────

class _Sparkline extends StatelessWidget {
  final List<double> prices;
  final Color color;

  const _Sparkline({required this.prices, required this.color});

  @override
  Widget build(BuildContext context) {
    final spots = prices
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final minY = prices.reduce((a, b) => a < b ? a : b);
    final maxY = prices.reduce((a, b) => a > b ? a : b);
    final range = (maxY - minY).abs();
    final pad = range < 0.01 ? 1.0 : range * 0.15;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (prices.length - 1).toDouble(),
        minY: minY - pad,
        maxY: maxY + pad,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.25),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
