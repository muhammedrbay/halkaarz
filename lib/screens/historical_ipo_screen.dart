import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/historical_ipo_service.dart';

enum _Filter { hepsi, tavanlar, yakinIsleme }

class HistoricalIpoScreen extends StatefulWidget {
  const HistoricalIpoScreen({super.key});

  @override
  State<HistoricalIpoScreen> createState() => _HistoricalIpoScreenState();
}

class _HistoricalIpoScreenState extends State<HistoricalIpoScreen> {
  List<HistoricalIpo> _ipos = [];
  bool _isLoading = true;
  int _progress = 0;
  int _total = 0;
  _Filter _filter = _Filter.hepsi;
  bool _refreshingPrices = false;

  @override
  void initState() {
    super.initState();
    // Önce cache'i hemen göster, arka planda refresh et
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final cached = HistoricalIpoService.loadFromCache();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _ipos = cached;
        _isLoading = false;
      });
      // Sekme açılınca arka planda fiyatları refresh et
      _backgroundRefresh();
    } else {
      // İlk açılış — tam yükleme
      await _fullLoad();
    }
  }

  Future<void> _fullLoad() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _progress = 0;
    });

    final ipos = await HistoricalIpoService.fetchAll(
      onProgress: (done, total) {
        if (mounted) setState(() { _progress = done; _total = total; });
      },
    );

    if (mounted) {
      setState(() {
        _ipos = ipos;
        _isLoading = false;
      });
    }
  }

  Future<void> _backgroundRefresh() async {
    if (_refreshingPrices) return;
    setState(() => _refreshingPrices = true);
    final updated = await HistoricalIpoService.refreshPrices(List.from(_ipos));
    if (mounted) {
      setState(() {
        _ipos = updated;
        _refreshingPrices = false;
      });
    }
  }

  List<HistoricalIpo> get _filtered {
    switch (_filter) {
      case _Filter.hepsi:
        return _ipos;
      case _Filter.tavanlar:
        return _ipos.where((i) => i.tavanMi).toList();
      case _Filter.yakinIsleme:
        final now = DateTime.now();
        return _ipos.where((i) {
          final diff = i.islemTarihi.difference(now).inDays.abs();
          return diff <= 5 && i.islemTarihi.isAfter(now.subtract(const Duration(days: 5)));
        }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Expanded(child: _buildLoadingState())
            else
              Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
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
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Son 1 yılın halka arzları',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_refreshingPrices)
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7C3AED)),
            )
          else
            IconButton(
              onPressed: _fullLoad,
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF7C3AED)),
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
          _FilterChip(
            label: 'Tümü (${_ipos.length})',
            icon: Icons.list_rounded,
            selected: _filter == _Filter.hepsi,
            onTap: () => setState(() => _filter = _Filter.hepsi),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Tavan (${_ipos.where((i) => i.tavanMi).length})',
            icon: Icons.arrow_upward_rounded,
            selected: _filter == _Filter.tavanlar,
            onTap: () => setState(() => _filter = _Filter.tavanlar),
            color: const Color(0xFF00D4AA),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Bu Hafta',
            icon: Icons.calendar_today_rounded,
            selected: _filter == _Filter.yakinIsleme,
            onTap: () => setState(() => _filter = _Filter.yakinIsleme),
            color: const Color(0xFFFFBE0B),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF7C3AED)),
          const SizedBox(height: 16),
          Text(
            _total > 0
                ? 'Veriler yükleniyor... $_progress/$_total'
                : 'Veriler hazırlanıyor...',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            'Yahoo Finance\'den fiyatlar alınıyor',
            style: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                color: Colors.white.withValues(alpha: 0.15), size: 64),
            const SizedBox(height: 12),
            Text('Bu filtrede veri yok',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 14)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fullLoad,
      color: const Color(0xFF7C3AED),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 80),
        itemCount: filtered.length,
        itemBuilder: (ctx, i) => _HistoricalIpoCard(ipo: filtered[i]),
      ),
    );
  }
}

// ─── Filter Chip ────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.color = const Color(0xFF7C3AED),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : const Color(0xFF1A1F38),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : const Color(0xFF2A2F4A),
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? color : Colors.white38),
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
}

// ─── IPO Card ────────────────────────────────────────────────────────────────

class _HistoricalIpoCard extends StatelessWidget {
  final HistoricalIpo ipo;

  const _HistoricalIpoCard({required this.ipo});

  Color get _getiriColor {
    final g = ipo.getiviYuzde;
    if (g >= 10) return const Color(0xFF00D4AA);
    if (g >= 0) return const Color(0xFF4CAF50);
    return const Color(0xFFFF4757);
  }

  @override
  Widget build(BuildContext context) {
    final getiri = ipo.getiviYuzde;
    final isPositive = getiri >= 0;
    final color = _getiriColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ipo.tavanMi
              ? const Color(0xFF00D4AA).withValues(alpha: 0.4)
              : color.withValues(alpha: 0.12),
          width: ipo.tavanMi ? 1.5 : 0.5,
        ),
        boxShadow: ipo.tavanMi
            ? [BoxShadow(
                color: const Color(0xFF00D4AA).withValues(alpha: 0.08),
                blurRadius: 12,
              )]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Üst satır
            Row(
              children: [
                // Şirket kodu badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ipo.sirketKodu,
                    style: GoogleFonts.inter(
                      color: color,
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                if (ipo.katilimEndeksi && !ipo.tavanMi)
                  const Icon(Icons.verified, color: Color(0xFF00D4AA), size: 16),
              ],
            ),

            const SizedBox(height: 12),

            // Fiyat bilgisi + sparkline
            Row(
              children: [
                // Sol: fiyatlar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Arz fiyatı
                      Row(
                        children: [
                          Text(
                            'Arz: ',
                            style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
                          ),
                          Text(
                            '₺${ipo.arzFiyati.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Güncel fiyat
                      if (ipo.guncelFiyat != null)
                        Text(
                          '₺${ipo.guncelFiyat!.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      else
                        Text(
                          'Fiyat yükleniyor...',
                          style: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
                        ),

                      const SizedBox(height: 4),

                      // Getiri badge
                      if (ipo.guncelFiyat != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${isPositive ? '+' : ''}%${getiri.toStringAsFixed(2)} arzdan',
                            style: GoogleFonts.inter(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Sağ: Sparkline grafik
                SizedBox(
                  width: 110,
                  height: 60,
                  child: ipo.sparkline.length >= 3
                      ? _SparklineChart(
                          prices: ipo.sparkline,
                          color: color,
                        )
                      : Center(
                          child: Text(
                            'Grafik yükleniyor',
                            style: GoogleFonts.inter(
                              color: Colors.white24,
                              fontSize: 9,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Alt bilgi satırı
            Row(
              children: [
                _buildMiniInfo(
                  Icons.calendar_today_outlined,
                  _formatDate(ipo.islemTarihi),
                  'İşlem Tarihi',
                ),
                const SizedBox(width: 16),
                if (ipo.ilkGunFiyati != null)
                  _buildMiniInfo(
                    Icons.open_in_new_rounded,
                    '₺${ipo.ilkGunFiyati!.toStringAsFixed(2)}',
                    'İlk Gün',
                  ),
                const Spacer(),
                // Kaç gün önce işlem gördü
                Text(
                  _daysAgo(ipo.islemTarihi),
                  style: GoogleFonts.inter(color: Colors.white24, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniInfo(IconData icon, String value, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white24, size: 11),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(color: Colors.white24, fontSize: 9),
            ),
            Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  String _daysAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt).inDays;
    if (diff == 0) return 'Bugün';
    if (diff < 0) return '${(-diff)} gün sonra';
    if (diff < 30) return '$diff gün önce';
    final months = (diff / 30).round();
    return '$months ay önce';
  }
}

// ─── Sparkline Chart ─────────────────────────────────────────────────────────

class _SparklineChart extends StatelessWidget {
  final List<double> prices;
  final Color color;

  const _SparklineChart({required this.prices, required this.color});

  @override
  Widget build(BuildContext context) {
    final spots = prices.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value);
    }).toList();

    final minY = prices.reduce((a, b) => a < b ? a : b);
    final maxY = prices.reduce((a, b) => a > b ? a : b);
    final range = (maxY - minY).abs();
    final padding = range == 0 ? 1.0 : range * 0.1;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (prices.length - 1).toDouble(),
        minY: minY - padding,
        maxY: maxY + padding,
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
              color: color.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: const LineTouchData(enabled: false),
      ),
    );
  }
}
