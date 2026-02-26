import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/portfolio_item.dart';
import '../services/portfolio_service.dart';
import '../services/price_service.dart';
import 'sell_screen.dart';
import 'manual_add_screen.dart';

/// Portföy / Cüzdan ekranı — Canlı K/Z, satılmış pozisyonlar, toplam kazanç
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, double> _livePrices = {};
  bool _loadingPrices = false;
  Timer? _priceTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchPrices();

    // Her 60 saniyede fiyat güncelle
    _priceTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _fetchPrices(),
    );
  }

  Future<void> _fetchPrices() async {
    final active = PortfolioService.getActivePositions();
    if (active.isEmpty) return;

    setState(() => _loadingPrices = true);

    final tickers = active.map((e) => e.sirketKodu).toSet().toList();
    final prices = await PriceService.getMultiplePrices(tickers);

    if (mounted) {
      setState(() {
        _livePrices = prices;
        _loadingPrices = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _priceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalEarnings = PortfolioService.getTotalEarnings();
    final active = PortfolioService.getActivePositions();
    final sold = PortfolioService.getSoldPositions();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0E21), Color(0xFF0F1328)],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(totalEarnings),
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildActiveList(active),
                      _buildSoldList(sold),
                    ],
                  ),
                ),
              ],
            ),
            // FAB — Manuel ekleme
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManualAddScreen(),
                    ),
                  );
                  if (result == true && mounted) {
                    setState(() {});
                    _fetchPrices();
                  }
                },
                backgroundColor: const Color(0xFF00D4AA),
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: Text(
                  'Ekle',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double totalEarnings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Cüzdan',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_loadingPrices)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF00D4AA),
                  ),
                )
              else
                IconButton(
                  onPressed: _fetchPrices,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Color(0xFF00D4AA),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Tüm Zamanların Toplam Kazancı
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF00D4AA).withValues(alpha: 0.15),
                  const Color(0xFF00B4D8).withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF00D4AA).withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFFFBE0B),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Tüm Zamanların Toplam Kazancı',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${totalEarnings >= 0 ? '+' : ''}₺${totalEarnings.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    color: totalEarnings >= 0
                        ? const Color(0xFF00D4AA)
                        : const Color(0xFFFF4757),
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.trending_up_rounded, size: 16),
                const SizedBox(width: 4),
                Text('Aktif Pozisyonlar',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history_rounded, size: 16),
                const SizedBox(width: 4),
                Text('İşlem Geçmişi',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveList(List<PortfolioItem> items) {
    if (items.isEmpty) {
      return _buildEmptyState(
        Icons.account_balance_wallet_outlined,
        'Henüz aktif pozisyon yok',
        'Halka arz detay sayfasından portföye ekleyebilirsiniz',
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPrices,
      color: const Color(0xFF00D4AA),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 80),
        itemCount: items.length,
        itemBuilder: (ctx, i) => _buildActiveCard(items[i]),
      ),
    );
  }

  Widget _buildActiveCard(PortfolioItem item) {
    final livePrice = _livePrices[item.sirketKodu];
    final hasPrice = livePrice != null;
    final kz = hasPrice ? item.karZarar(livePrice) : 0.0;
    final kzYuzde = hasPrice ? item.karZararYuzde(livePrice) : 0.0;
    final isProfit = kz >= 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasPrice
              ? (isProfit
                  ? const Color(0xFF00D4AA).withValues(alpha: 0.15)
                  : const Color(0xFFFF4757).withValues(alpha: 0.15))
              : const Color(0xFF2A2F4A),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Üst satır
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D4AA).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.sirketKodu,
                    style: GoogleFonts.inter(
                      color: const Color(0xFF00D4AA),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.sirketAdi,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Detay satırları
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMiniInfo('Alış', '₺${item.arzFiyati.toStringAsFixed(2)}'),
                _buildMiniInfo('Lot', '${item.toplamLot}'),
                _buildMiniInfo('Hesap', '${item.hesapSayisi}'),
                _buildMiniInfo('Maliyet', '₺${item.toplamMaliyet.toStringAsFixed(0)}'),
              ],
            ),

            if (hasPrice) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: (isProfit
                          ? const Color(0xFF00D4AA)
                          : const Color(0xFFFF4757))
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Güncel Fiyat',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          '₺${livePrice.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isProfit ? 'KAR' : 'ZARAR',
                          style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          '${isProfit ? '+' : ''}₺${kz.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            color: isProfit
                                ? const Color(0xFF00D4AA)
                                : const Color(0xFFFF4757),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${isProfit ? '+' : ''}%${kzYuzde.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            color: (isProfit
                                    ? const Color(0xFF00D4AA)
                                    : const Color(0xFFFF4757))
                                .withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Sat & Sil butonları
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SellScreen(item: item),
                        ),
                      );
                      if (result == true && mounted) {
                        setState(() {});
                        _fetchPrices();
                      }
                    },
                    icon: const Icon(Icons.sell_outlined, size: 16),
                    label: Text(
                      'Sat',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00D4AA),
                      side: const BorderSide(
                        color: Color(0xFF00D4AA),
                        width: 1,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () => _deleteItem(item),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFFF4757),
                    size: 20,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoldList(List<PortfolioItem> items) {
    if (items.isEmpty) {
      return _buildEmptyState(
        Icons.history_rounded,
        'İşlem Geçmişi yok',
        'Sattığınız hisseler burada görünecek',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 80),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _buildSoldCard(items[i]),
    );
  }

  Widget _buildSoldCard(PortfolioItem item) {
    final isProfit = item.satisNetKar >= 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2F4A), width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.sirketKodu,
                  style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.sirketAdi,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isProfit ? '+' : ''}₺${item.satisNetKar.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      color: isProfit
                          ? const Color(0xFF00D4AA)
                          : const Color(0xFFFF4757),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '${isProfit ? '+' : ''}%${item.satisNetKarYuzde.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniInfo('Alış', '₺${item.arzFiyati.toStringAsFixed(2)}'),
              _buildMiniInfo('Satış', '₺${item.satisFiyati?.toStringAsFixed(2) ?? '-'}'),
              _buildMiniInfo('Lot', '${item.toplamLot}'),
              _buildMiniInfo(
                'Tarih',
                item.satisTarihi != null
                    ? '${item.satisTarihi!.day}.${item.satisTarihi!.month.toString().padLeft(2, '0')}'
                    : '-',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfo(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.1), size: 64),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(PortfolioItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Silme Onayı',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '${item.sirketAdi} portföyünüzden silinecek. Emin misiniz?',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'İptal',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4757),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Sil',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PortfolioService.deleteItem(item.id);
      if (mounted) setState(() {});
    }
  }
}
