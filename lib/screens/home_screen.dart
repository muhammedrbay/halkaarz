import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ipo_model.dart';
import '../services/ipo_service.dart';
import '../widgets/ipo_card.dart';
import '../widgets/katilim_toggle.dart';
import '../services/realtime_price_service.dart';
import '../services/ad_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

enum _SortType { tarihYeni, tarihEski, fiyatArtan, fiyatAzalan, isimAZ, isimZA }

/// Ana Ekran — 3 sekmeli halka arz listesi
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<IpoModel> _allIpos = [];
  bool _katilimFilter = false;
  bool _isLoading = true;
  _SortType _sortType = _SortType.tarihYeni;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final ipos = await IpoService.getIpos();
      // Yenile butonuna/pull-to-refresh'e tıklandığında cache'i atla ve Firebase'den taze çek
      await RealtimePriceService.fetchAll(forceRefresh: true);
      if (mounted) {
        setState(() {
          _allIpos = ipos;
          _isLoading = false;
        });
      }
    } catch (e) {
      final ipos = await IpoService.getIpos();
      await RealtimePriceService.fetchAll(forceRefresh: true);
      if (mounted) {
        setState(() {
          _allIpos = ipos;
          _isLoading = false;
        });
      }
    }
  }

  List<IpoModel> _getFilteredIpos(String durum) {
    var filtered = IpoService.filterByDurum(_allIpos, durum);
    if (_katilimFilter) {
      filtered = IpoService.filterKatilimEndeksi(filtered);
    }
    // Sıralama uygula
    filtered = List.from(filtered);
    switch (_sortType) {
      case _SortType.tarihYeni:
        filtered.sort((a, b) => _parseDate(b.bistIlkIslemTarihi.isNotEmpty ? b.bistIlkIslemTarihi : b.tarih)
            .compareTo(_parseDate(a.bistIlkIslemTarihi.isNotEmpty ? a.bistIlkIslemTarihi : a.tarih)));
        break;
      case _SortType.tarihEski:
        filtered.sort((a, b) => _parseDate(a.bistIlkIslemTarihi.isNotEmpty ? a.bistIlkIslemTarihi : a.tarih)
            .compareTo(_parseDate(b.bistIlkIslemTarihi.isNotEmpty ? b.bistIlkIslemTarihi : b.tarih)));
        break;
      case _SortType.fiyatArtan:
        filtered.sort((a, b) => a.arzFiyati.compareTo(b.arzFiyati));
        break;
      case _SortType.fiyatAzalan:
        filtered.sort((a, b) => b.arzFiyati.compareTo(a.arzFiyati));
        break;
      case _SortType.isimAZ:
        filtered.sort((a, b) => a.sirketAdi.compareTo(b.sirketAdi));
        break;
      case _SortType.isimZA:
        filtered.sort((a, b) => b.sirketAdi.compareTo(a.sirketAdi));
        break;
    }
    return filtered;
  }

  DateTime _parseDate(String s) {
    // "05.03.2025" veya "05.03.2025 - 07.03.2025" formatı
    try {
      final part = s.split(' ').first.trim();
      final parts = part.split('.');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      }
    } catch (_) {}
    return DateTime(2000);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
            KatilimToggle(
              value: _katilimFilter,
              onChanged: (val) => setState(() => _katilimFilter = val),
            ),
            _buildTabBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00D4AA),
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildIpoList('taslak'),
                        _buildIpoList('arz'),
                        _buildIpoList('islem', showSort: true),
                      ],
                    ),
            ),
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
                colors: [Color(0xFF00D4AA), Color(0xFF00B4D8)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.trending_up_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Halka Arz Takip',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Güncel halka arzları keşfet',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00D4AA)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF12162B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2F4A), width: 0.5),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00D4AA), Color(0xFF00B4D8)],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.edit_note_rounded, size: 16),
                const SizedBox(width: 4),
                Text('Taslak', style: GoogleFonts.inter(fontSize: 12)),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.how_to_vote_rounded, size: 16),
                const SizedBox(width: 4),
                Text('Arz', style: GoogleFonts.inter(fontSize: 12)),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.show_chart_rounded, size: 16),
                const SizedBox(width: 4),
                Text('İşlem', style: GoogleFonts.inter(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIpoList(String durum, {bool showSort = false}) {
    final ipos = _getFilteredIpos(durum);
    if (ipos.isEmpty) {
      // Taslaklar sekmesine özel mesaj
      if (durum == 'taslak') {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F38),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFFBE0B).withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFBE0B).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.hourglass_empty_rounded,
                      color: Color(0xFFFFBE0B),
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Şu an aktif taslak veri bulunmuyor',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SPK tarafından yeni halka arz taslağı yayınlandığında burada listelenecektir.',
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              color: Colors.white.withValues(alpha: 0.15),
              size: 64,
            ),
            const SizedBox(height: 12),
            Text(
              _katilimFilter
                  ? 'Katılım endeksine uygun halka arz bulunamadı'
                  : 'Bu kategoride halka arz bulunamadı',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final hasAd = AdService.isNativeAdLoaded('home');
    final adIndex = ipos.length >= 3 ? 3 : ipos.length;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF00D4AA),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 80),
        itemCount: ipos.length + (hasAd ? 1 : 0) + (showSort ? 1 : 0),
        itemBuilder: (context, index) {
          // Sıralama satırı
          if (showSort && index == 0) {
            return _buildSortRow();
          }
          final adjustedIndex = showSort ? index - 1 : index;
          if (hasAd && adjustedIndex == adIndex) {
            return AdService.buildNativeAdWidget('home');
          }
          final ipoIndex = hasAd && adjustedIndex > adIndex ? adjustedIndex - 1 : adjustedIndex;
          if (ipoIndex >= ipos.length || ipoIndex < 0) return const SizedBox.shrink();
          return IpoCard(ipo: ipos[ipoIndex]);
        },
      ),
    );
  }

  Widget _buildSortRow() {
    String label;
    switch (_sortType) {
      case _SortType.tarihYeni: label = 'Tarih (Yeni → Eski)'; break;
      case _SortType.tarihEski: label = 'Tarih (Eski → Yeni)'; break;
      case _SortType.fiyatArtan: label = 'Fiyat (Düşük → Yüksek)'; break;
      case _SortType.fiyatAzalan: label = 'Fiyat (Yüksek → Düşük)'; break;
      case _SortType.isimAZ: label = 'İsim (A → Z)'; break;
      case _SortType.isimZA: label = 'İsim (Z → A)'; break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                  ..._SortType.values.map((s) {
                    String text;
                    IconData icon;
                    switch (s) {
                      case _SortType.tarihYeni: text = 'Tarih (Yeni → Eski)'; icon = Icons.calendar_month; break;
                      case _SortType.tarihEski: text = 'Tarih (Eski → Yeni)'; icon = Icons.calendar_month; break;
                      case _SortType.fiyatArtan: text = 'Fiyat (Düşük → Yüksek)'; icon = Icons.trending_up; break;
                      case _SortType.fiyatAzalan: text = 'Fiyat (Yüksek → Düşük)'; icon = Icons.trending_down; break;
                      case _SortType.isimAZ: text = 'İsim (A → Z)'; icon = Icons.sort_by_alpha; break;
                      case _SortType.isimZA: text = 'İsim (Z → A)'; icon = Icons.sort_by_alpha; break;
                    }
                    return ListTile(
                      leading: Icon(icon, color: _sortType == s ? const Color(0xFF00D4AA) : Colors.white38, size: 20),
                      title: Text(text, style: GoogleFonts.inter(
                        color: _sortType == s ? const Color(0xFF00D4AA) : Colors.white70,
                        fontSize: 14, fontWeight: _sortType == s ? FontWeight.w700 : FontWeight.w400,
                      )),
                      trailing: _sortType == s ? const Icon(Icons.check, color: Color(0xFF00D4AA), size: 18) : null,
                      onTap: () {
                        setState(() => _sortType = s);
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
              const Icon(Icons.sort_rounded, size: 14, color: Color(0xFF00D4AA)),
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
}
