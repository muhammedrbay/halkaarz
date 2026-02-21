import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/historical_ipo_service.dart';

class HistoricalIpoDetailScreen extends StatelessWidget {
  final HistoricalIpo ipo;

  const HistoricalIpoDetailScreen({super.key, required this.ipo});

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
    final ilkGunGetiri = ipo.ilkGunGetiri;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──
          SliverAppBar(
            backgroundColor: const Color(0xFF0A0E21),
            expandedHeight: 180,
            pinned: true,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A0A3B), Color(0xFF0A0E21)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: renk.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: renk.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                ipo.sirketKodu,
                                style: GoogleFonts.inter(
                                  color: renk, fontWeight: FontWeight.w800,
                                  fontSize: 16, letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (ipo.katilimEndeksi)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.verified, color: Color(0xFF3B82F6), size: 12),
                                  const SizedBox(width: 4),
                                  Text('Katılım Endeksi', style: GoogleFonts.inter(
                                    color: const Color(0xFF3B82F6), fontSize: 10, fontWeight: FontWeight.w600,
                                  )),
                                ]),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ipo.sirketAdi,
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Güncel Fiyat Kartı ──
                _buildPriceCard(renk, getiri),
                const SizedBox(height: 16),

                // ── Grafik ──
                if (ipo.sparkline.length >= 3) ...[
                  _buildChartCard(renk),
                  const SizedBox(height: 16),
                ],

                // ── İPO Detayları ──
                _buildSectionTitle('Halka Arz Bilgileri'),
                const SizedBox(height: 10),
                _buildInfoGrid([
                  _InfoItem('Arz Fiyatı', '₺${ipo.arzFiyati.toStringAsFixed(2)}', Icons.price_change_rounded),
                  _InfoItem('Kişi Başı Lot', '${ipo.kisiBasiLot} lot', Icons.person_rounded),
                  _InfoItem('Toplam Lot', _formatNumber(ipo.toplamLot), Icons.bar_chart_rounded),
                  _InfoItem('İşlem Tarihi', _formatDate(ipo.islemTarihi), Icons.calendar_month_rounded),
                ]),
                const SizedBox(height: 16),

                // ── Performans ──
                _buildSectionTitle('Performans'),
                const SizedBox(height: 10),
                _buildInfoGrid([
                  _InfoItem(
                    'İlk Gün Kapanış',
                    ipo.ilkGunKapanis != null ? '₺${ipo.ilkGunKapanis!.toStringAsFixed(2)}' : '—',
                    Icons.open_in_new_rounded,
                    subtitle: ipo.ilkGunKapanis != null
                        ? '${ilkGunGetiri >= 0 ? '+' : ''}%${ilkGunGetiri.toStringAsFixed(1)}'
                        : null,
                    subtitleColor: ilkGunGetiri >= 0 ? const Color(0xFF00D4AA) : const Color(0xFFFF4757),
                  ),
                  _InfoItem(
                    'Şuanki Fiyat',
                    ipo.guncelFiyat != null ? '₺${ipo.guncelFiyat!.toStringAsFixed(2)}' : '—',
                    Icons.monetization_on_rounded,
                    subtitle: '${getiri >= 0 ? '+' : ''}%${getiri.toStringAsFixed(1)} arzdan',
                    subtitleColor: renk,
                  ),
                  _InfoItem(
                    'Tavan Gün',
                    '${ipo.tavanGunSayisi ?? '—'}',
                    Icons.trending_up_rounded,
                    subtitle: ipo.tavanGunSayisi != null ? 'gün tavan yaptı' : null,
                    subtitleColor: const Color(0xFF00D4AA),
                  ),
                  _InfoItem(
                    'En Yüksek',
                    ipo.maxFiyat != null ? '₺${ipo.maxFiyat!.toStringAsFixed(2)}' : '—',
                    Icons.arrow_upward_rounded,
                    subtitleColor: const Color(0xFF00D4AA),
                  ),
                ]),
                const SizedBox(height: 10),
                _buildInfoGrid([
                  _InfoItem(
                    'En Düşük',
                    ipo.minFiyat != null ? '₺${ipo.minFiyat!.toStringAsFixed(2)}' : '—',
                    Icons.arrow_downward_rounded,
                    subtitleColor: const Color(0xFFFF4757),
                  ),
                  _InfoItem(
                    'Toplam Getiri',
                    ipo.guncelFiyat != null
                        ? '₺${(ipo.guncelFiyat! - ipo.arzFiyati).toStringAsFixed(2)}/hisse'
                        : '—',
                    Icons.account_balance_wallet_rounded,
                    subtitleColor: renk,
                  ),
                  _InfoItem(
                    '1 Lot Getiri',
                    ipo.guncelFiyat != null
                        ? '₺${((ipo.guncelFiyat! - ipo.arzFiyati) * 100).toStringAsFixed(0)}'
                        : '—',
                    Icons.payments_rounded,
                    subtitle: '100 hisse × fark',
                    subtitleColor: renk,
                  ),
                  _InfoItem(
                    'Güncellenme',
                    ipo.priceUpdatedAt != null ? _timeAgo(ipo.priceUpdatedAt!) : '—',
                    Icons.update_rounded,
                  ),
                ]),
                const SizedBox(height: 16),

                // ── Veri Kaynağı ──
                Center(
                  child: Text(
                    'Fiyat verileri Yahoo Finance\'dan • Borsa saatleri dışında gecikmeli',
                    style: GoogleFonts.inter(color: Colors.white12, fontSize: 9),
                    textAlign: TextAlign.center,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceCard(Color renk, double getiri) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [renk.withValues(alpha: 0.15), renk.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: renk.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Güncel Fiyat', style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  ipo.guncelFiyat != null ? '₺${ipo.guncelFiyat!.toStringAsFixed(2)}' : 'Yükleniyor...',
                  style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: renk.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${getiri >= 0 ? '+' : ''}%${getiri.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(color: renk, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 4),
              Text('Arz fiyatından', style: GoogleFonts.inter(color: Colors.white24, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(Color renk) {
    final spots = ipo.sparkline.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final minY = ipo.sparkline.reduce((a, b) => a < b ? a : b);
    final maxY = ipo.sparkline.reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;
    final pad = range < 0.01 ? 1.0 : range * 0.1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2F4A), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Son 30 Günlük Fiyat', style: GoogleFonts.inter(
            color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600,
          )),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.white.withValues(alpha: 0.04), strokeWidth: 1,
                  ),
                  drawVerticalLine: false,
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (v, _) => Text(
                        '₺${v.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(color: Colors.white24, fontSize: 9),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0, maxX: (ipo.sparkline.length - 1).toDouble(),
                minY: minY - pad, maxY: maxY + pad,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: renk,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: renk.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildInfoGrid(List<_InfoItem> items) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: items.map((item) => _buildInfoCell(item)).toList(),
    );
  }

  Widget _buildInfoCell(_InfoItem item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2F4A), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(item.icon, size: 18, color: item.subtitleColor ?? Colors.white24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(item.label, style: GoogleFonts.inter(color: Colors.white24, fontSize: 9)),
                Text(item.value, style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700,
                ), overflow: TextOverflow.ellipsis),
                if (item.subtitle != null)
                  Text(item.subtitle!, style: GoogleFonts.inter(
                    color: item.subtitleColor ?? Colors.white38, fontSize: 9,
                  )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    return '${diff.inDays} gün önce';
  }
}

class _InfoItem {
  final String label;
  final String value;
  final IconData icon;
  final String? subtitle;
  final Color? subtitleColor;

  const _InfoItem(this.label, this.value, this.icon, {this.subtitle, this.subtitleColor});
}
