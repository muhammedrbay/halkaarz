import 'dart:math' show max;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/historical_ipo_service.dart';
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
  bool _fetchingData = false;
  int _progress = 0;
  int _total = 0;
  _Filter _filter = _Filter.hepsi;

  @override
  bool get wantKeepAlive => true; // Tab'ı değiştirince state'i koru

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 1. Cache'ten hemen yükle
    final cached = HistoricalIpoService.loadFromCache();
    final base = await HistoricalIpoService.loadAll();

    if (mounted) {
      setState(() {
        _ipos = cached.isNotEmpty ? cached : base;
        _isLoading = false;
      });
    }

    // 2. Arka planda eksik/bayat verileri çek
    _backgroundFetch(cached.isNotEmpty ? cached : base);
  }

  Future<void> _backgroundFetch(List<HistoricalIpo> ipos) async {
    if (_fetchingData) return;
    setState(() { _fetchingData = true; _total = ipos.length; _progress = 0; });

    await HistoricalIpoService.fetchAndRefreshAll(
      ipos: ipos,
      onProgress: (done, total) {
        if (mounted) setState(() { _progress = done; _total = total; });
      },
    );

    if (mounted) {
      setState(() { _ipos = ipos; _fetchingData = false; });
    }
  }

  Future<void> _fullRefresh() async {
    final ipos = await HistoricalIpoService.loadAll();
    // Statik fetch'i zorla yenile
    for (final ipo in ipos) {
      ipo.staticFetched = null;
    }
    await HistoricalIpoService.saveToCache(ipos);
    if (mounted) setState(() => _ipos = ipos);
    _backgroundFetch(ipos);
  }

  List<HistoricalIpo> get _filtered {
    switch (_filter) {
      case _Filter.hepsi:
        return _ipos;
      case _Filter.tavanlar:
        return _ipos.where((i) => i.tavanMi || (i.tavanGunSayisi ?? 0) > 0).toList();
      case _Filter.katilim:
        return _ipos.where((i) => i.katilimEndeksi).toList();
    }
  }

  int get _tavanCount => _ipos.where((i) => i.tavanMi).length;
  int get _katilimCount => _ipos.where((i) => i.katilimEndeksi).length;

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
            if (_fetchingData)
              _buildProgressBar(),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED))))
            else
              Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
            child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Performans',
                  style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Son 1 yılın halka arzları · ${_ipos.length} şirket',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          if (_fetchingData)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: const Color(0xFF7C3AED),
                  value: _total > 0 ? _progress / _total : null,
                ),
              ),
            ),
          IconButton(
            onPressed: _fetchingData ? null : _fullRefresh,
            icon: Icon(Icons.refresh_rounded,
                color: _fetchingData ? Colors.white24 : const Color(0xFF7C3AED)),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _total > 0 ? _progress / max(_total, 1) : null,
                backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF7C3AED)),
                minHeight: 2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$_progress/$_total',
            style: GoogleFonts.inter(color: Colors.white24, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _buildChip('Tümü (${_ipos.length})', Icons.list_rounded, _Filter.hepsi),
          const SizedBox(width: 8),
          _buildChip('Tavan Yapan ($_tavanCount)', Icons.rocket_launch_rounded,
              _Filter.tavanlar, color: const Color(0xFF00D4AA)),
          const SizedBox(width: 8),
          _buildChip('Katılım ($_katilimCount)', Icons.verified_rounded,
              _Filter.katilim, color: const Color(0xFF3B82F6)),
        ],
      ),
    );
  }

  Widget _buildChip(String label, IconData icon, _Filter f, {Color color = const Color(0xFF7C3AED)}) {
    final selected = _filter == f;
    return GestureDetector(
      onTap: () => setState(() => _filter = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : const Color(0xFF1A1F38),
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
            Text(label, style: GoogleFonts.inter(
              color: selected ? color : Colors.white54, fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final List<HistoricalIpo> filtered = _filtered;
    if (filtered.isEmpty) {
      return Center(
        child: Text('Bu filtrede sonuç yok',
            style: GoogleFonts.inter(color: Colors.white38)),
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
            MaterialPageRoute(builder: (_) => HistoricalIpoDetailScreen(ipo: filtered[i])),
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
              // ── Üst satır: kod · ad · tavan badge ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: renk.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ipo.sirketKodu,
                      style: GoogleFonts.inter(
                        color: renk, fontWeight: FontWeight.w800,
                        fontSize: 12, letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ipo.sirketAdi,
                      style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (ipo.tavanMi)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00D4AA), Color(0xFF00B4D8)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('🚀 TAVAN', style: GoogleFonts.inter(
                        color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800,
                      )),
                    )
                  else if (ipo.katilimEndeksi)
                    const Icon(Icons.verified, color: Color(0xFF3B82F6), size: 16),
                ],
              ),

              const SizedBox(height: 12),

              // ── Orta: fiyat + sparkline ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Sol: fiyatlar
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text('Arz: ', style: GoogleFonts.inter(color: Colors.white38, fontSize: 10)),
                          Text('₺${ipo.arzFiyati.toStringAsFixed(2)}',
                              style: GoogleFonts.inter(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 3),
                        Text(
                          ipo.guncelFiyat != null
                              ? '₺${ipo.guncelFiyat!.toStringAsFixed(2)}'
                              : '—',
                          style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (ipo.guncelFiyat != null)
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: renk.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${isPos ? '+' : ''}%${getiri.toStringAsFixed(1)}',
                                style: GoogleFonts.inter(
                                  color: renk, fontSize: 11, fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('arzdan',
                                style: GoogleFonts.inter(color: Colors.white24, fontSize: 10)),
                          ]),
                      ],
                    ),
                  ),
                  // Sağ: sparkline
                  SizedBox(
                    width: 100,
                    height: 55,
                    child: ipo.sparkline.length >= 3
                        ? _Sparkline(prices: ipo.sparkline, color: renk)
                        : Center(
                            child: ipo.staticFetched == true
                                ? Icon(Icons.show_chart, color: Colors.white12, size: 24)
                                : const SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Color(0xFF7C3AED),
                                    ),
                                  ),
                          ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              const Divider(color: Color(0xFF2A2F4A), height: 1),
              const SizedBox(height: 10),

              // ── Alt: istatistikler ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stat('Kişi Başı', '${ipo.kisiBasiLot} lot', Icons.person_outline_rounded),
                  _stat('Toplam Lot', _formatNumber(ipo.toplamLot), Icons.bar_chart_rounded),
                  _stat('Tavan Gün', '${ipo.tavanGunSayisi ?? '—'}', Icons.trending_up_rounded,
                      color: (ipo.tavanGunSayisi ?? 0) > 0 ? const Color(0xFF00D4AA) : null),
                  _stat('İşlem', _shortDate(ipo.islemTarihi), Icons.calendar_today_rounded),
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
        Text(value, style: GoogleFonts.inter(
          color: color ?? Colors.white70, fontSize: 11, fontWeight: FontWeight.w600,
        )),
        Text(label, style: GoogleFonts.inter(color: Colors.white24, fontSize: 9)),
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }

  String _shortDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year.toString().substring(2)}';
  }
}

// ─── Sparkline ───────────────────────────────────────────────────────────────

class _Sparkline extends StatelessWidget {
  final List<double> prices;
  final Color color;

  const _Sparkline({required this.prices, required this.color});

  @override
  Widget build(BuildContext context) {
    final spots = prices.asMap().entries
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
        minX: 0, maxX: (prices.length - 1).toDouble(),
        minY: minY - pad, maxY: maxY + pad,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 1.8,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.08),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
