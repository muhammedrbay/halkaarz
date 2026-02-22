import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ipo_model.dart';
import '../services/data_service.dart';
import '../widgets/ipo_card.dart';
import '../widgets/katilim_toggle.dart';
import '../services/realtime_price_service.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final ipos = await DataService.fetchFromRemote();
      await RealtimePriceService.fetchAll();
      if (mounted) {
        setState(() {
          _allIpos = ipos;
          _isLoading = false;
        });
      }
    } catch (e) {
      final ipos = await DataService.loadFromLocal();
      await RealtimePriceService.fetchAll();
      if (mounted) {
        setState(() {
          _allIpos = ipos;
          _isLoading = false;
        });
      }
    }
  }

  List<IpoModel> _getFilteredIpos(String durum) {
    var filtered = DataService.filterByDurum(_allIpos, durum);
    if (_katilimFilter) {
      filtered = DataService.filterKatilimEndeksi(filtered);
    }
    return filtered;
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
                        _buildIpoList('talep_topluyor'),
                        _buildIpoList('islem_goruyor'),
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
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(
              Icons.refresh_rounded,
              color: Color(0xFF00D4AA),
            ),
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
                Text('Taslaklar',
                    style: GoogleFonts.inter(fontSize: 12)),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.how_to_vote_rounded, size: 16),
                const SizedBox(width: 4),
                Text('Talep',
                    style: GoogleFonts.inter(fontSize: 12)),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.show_chart_rounded, size: 16),
                const SizedBox(width: 4),
                Text('İşlem',
                    style: GoogleFonts.inter(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIpoList(String durum) {
    final ipos = _getFilteredIpos(durum);
    if (ipos.isEmpty) {
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

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF00D4AA),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 80),
        itemCount: ipos.length,
        itemBuilder: (context, index) => IpoCard(ipo: ipos[index]),
      ),
    );
  }
}
