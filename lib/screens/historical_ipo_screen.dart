import 'dart:async';
import 'dart:math' show max;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/historical_ipo_service.dart';
import '../services/realtime_price_service.dart';
import '../services/ad_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'historical_ipo_detail_screen.dart';

enum _Filter { hepsi, tavanlar, katilim }
enum _HistSort { tarihYeni, tarihEski, getiriArtan, getiriAzalan, fiyatArtan, fiyatAzalan, isimAZ }

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
  _HistSort _sort = _HistSort.tarihYeni;
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
    List<HistoricalIpo> list;
    switch (_filter) {
      case _Filter.hepsi:
        list = List.from(_ipos);
        break;
      case _Filter.tavanlar:
        list = _ipos
            .where((i) => i.tavanMi || (i.tavanGunSayisi ?? 0) > 0)
            .toList();
        break;
      case _Filter.katilim:
        list = _ipos.where((i) => i.katilimEndeksi).toList();
        break;
    }
    // Sıralama
    switch (_sort) {
      case _HistSort.tarihYeni:
        list.sort((a, b) => b.islemTarihi.compareTo(a.islemTarihi));
        break;
      case _HistSort.tarihEski:
        list.sort((a, b) => a.islemTarihi.compareTo(b.islemTarihi));
        break;
      case _HistSort.getiriArtan:
        list.sort((a, b) => a.getiviYuzde.compareTo(b.getiviYuzde));
        break;
      case _HistSort.getiriAzalan:
        list.sort((a, b) => b.getiviYuzde.compareTo(a.getiviYuzde));
        break;
      case _HistSort.fiyatArtan:
        list.sort((a, b) => a.arzFiyati.compareTo(b.arzFiyati));
        break;
      case _HistSort.fiyatAzalan:
        list.sort((a, b) => b.arzFiyati.compareTo(a.arzFiyati));
        break;
      case _HistSort.isimAZ:
        list.sort((a, b) => a.sirketAdi.compareTo(b.sirketAdi));
        break;
    }
    return list;
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
            _buildSortRow(),
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

  Widget _buildSortRow() {
    String label;
    switch (_sort) {
      case _HistSort.tarihYeni: label = 'Tarih (Yeni → Eski)'; break;
      case _HistSort.tarihEski: label = 'Tarih (Eski → Yeni)'; break;
      case _HistSort.getiriArtan: label = 'Getiri (Düşük → Yüksek)'; break;
      case _HistSort.getiriAzalan: label = 'Getiri (Yüksek → Düşük)'; break;
      case _HistSort.fiyatArtan: label = 'Fiyat (Düşük → Yüksek)'; break;
      case _HistSort.fiyatAzalan: label = 'Fiyat (Yüksek → Düşük)'; break;
      case _HistSort.isimAZ: label = 'İsim (A → Z)'; break;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: const Color(0xFF1A1F38),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (_) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Sıralama', style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700,
                    )),
                  ),
                  ..._HistSort.values.map((s) {
                    String text;
                    IconData icon;
                    switch (s) {
                      case _HistSort.tarihYeni: text = 'Tarih (Yeni → Eski)'; icon = Icons.calendar_month; break;
                      case _HistSort.tarihEski: text = 'Tarih (Eski → Yeni)'; icon = Icons.calendar_month; break;
                      case _HistSort.getiriArtan: text = 'Getiri (Düşük → Yüksek)'; icon = Icons.trending_up; break;
                      case _HistSort.getiriAzalan: text = 'Getiri (Yüksek → Düşük)'; icon = Icons.trending_down; break;
                      case _HistSort.fiyatArtan: text = 'Fiyat (Düşük → Yüksek)'; icon = Icons.price_change; break;
                      case _HistSort.fiyatAzalan: text = 'Fiyat (Yüksek → Düşük)'; icon = Icons.price_change; break;
                      case _HistSort.isimAZ: text = 'İsim (A → Z)'; icon = Icons.sort_by_alpha; break;
                    }
                    return ListTile(
                      leading: Icon(icon, color: _sort == s ? const Color(0xFF7C3AED) : Colors.white38, size: 20),
                      title: Text(text, style: GoogleFonts.inter(
                        color: _sort == s ? const Color(0xFF7C3AED) : Colors.white70,
                        fontSize: 14, fontWeight: _sort == s ? FontWeight.w700 : FontWeight.w400,
                      )),
                      trailing: _sort == s ? const Icon(Icons.check, color: Color(0xFF7C3AED), size: 18) : null,
                      onTap: () {
                        setState(() => _sort = s);
                        Navigator.pop(context);
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF12162B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2A2F4A), width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sort_rounded, size: 14, color: Color(0xFF7C3AED)),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(
                color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500,
              )),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white38),
            ],
          ),
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
    final hasAd = AdService.isNativeAdLoaded('historical');
    final adIndex = filtered.length >= 3 ? 3 : filtered.length;

    return RefreshIndicator(
      onRefresh: _fullRefresh,
      color: const Color(0xFF7C3AED),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 90),
        itemCount: filtered.length + (hasAd ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (hasAd && i == adIndex) {
            return AdService.buildNativeAdWidget('historical');
          }
          final idx = hasAd && i > adIndex ? i - 1 : i;
          if (idx >= filtered.length) return const SizedBox.shrink();
          return _IpoCard(
            ipo: filtered[idx],
            onTap: () => Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) => HistoricalIpoDetailScreen(ipo: filtered[idx]),
              ),
            ),
          );
        },
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
                            // 1. Arzdan Getiri (Total Return)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: renk.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${isPos ? '+' : ''}%${getiri.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  color: renk,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'toplam',
                              style: GoogleFonts.inter(
                                color: Colors.white38,
                                fontSize: 9,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 2. Günlük Getiri (Daily Return)
                            if (ipo.sparkline.length >= 2) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: (ipo.gunlukGetiriYuzde >= 0 ? const Color(0xFF00D4AA) : const Color(0xFFFF4757)).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${ipo.gunlukGetiriYuzde >= 0 ? '+' : ''}%${ipo.gunlukGetiriYuzde.toStringAsFixed(2)}',
                                  style: GoogleFonts.inter(
                                    color: ipo.gunlukGetiriYuzde >= 0 ? const Color(0xFF00D4AA) : const Color(0xFFFF4757),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'bugün',
                                style: GoogleFonts.inter(
                                  color: Colors.white38,
                                  fontSize: 9,
                                ),
                              ),
                            ]
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
                child: ipo.islemTarihi.isAfter(DateTime.now())
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              color: Color(0xFFFFBE0B),
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Henüz işlemlere başlamadı',
                              style: GoogleFonts.inter(
                                color: const Color(0xFFFFBE0B),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ipo.sparkline.length >= 3
                    ? _Sparkline(
                        prices: ipo.sparkline,
                        color: renk,
                        sparklineDates: ipo.sparklineDates,
                      )
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
                    'Arz Fiyatı',
                    '₺${ipo.arzFiyati.toStringAsFixed(2)}',
                    Icons.monetization_on_outlined,
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
  final List<String> sparklineDates;

  const _Sparkline({
    required this.prices,
    required this.color,
    required this.sparklineDates,
  });

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
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1A1F38),
            tooltipBorder: BorderSide(color: color.withValues(alpha: 0.3)),
            tooltipRoundedRadius: 8,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                String dateStr;
                if (idx < sparklineDates.length) {
                  // Gerçek tarih mevcut
                  try {
                    final dt = DateTime.parse(sparklineDates[idx]);
                    dateStr =
                        '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
                  } catch (_) {
                    dateStr = sparklineDates[idx];
                  }
                } else {
                  dateStr = 'Gün ${idx + 1}';
                }
                return LineTooltipItem(
                  '₺${spot.y.toStringAsFixed(2)}\n$dateStr',
                  GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList();
            },
          ),
          getTouchedSpotIndicator: (barData, spotIndexes) {
            return spotIndexes.map((i) {
              return TouchedSpotIndicatorData(
                FlLine(color: color.withValues(alpha: 0.4), strokeWidth: 1),
                FlDotData(
                  show: true,
                  getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                    radius: 4,
                    color: color,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
                ),
              );
            }).toList();
          },
        ),
      ),
    );
  }
}
