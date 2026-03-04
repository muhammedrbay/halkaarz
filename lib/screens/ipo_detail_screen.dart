import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ipo_model.dart';
import 'add_portfolio_screen.dart';

/// IPO Detay Sayfası — Hesaplayıcı ve tüm detay bilgileri
class IpoDetailScreen extends StatefulWidget {
  final IpoModel ipo;

  const IpoDetailScreen({super.key, required this.ipo});

  @override
  State<IpoDetailScreen> createState() => _IpoDetailScreenState();
}

class _IpoDetailScreenState extends State<IpoDetailScreen> {
  final _katilimciController = TextEditingController();
  double _tahminiLot = 0;
  double _tahminiTutar = 0;

  void _hesapla() {
    final katilimci = int.tryParse(_katilimciController.text) ?? 0;
    setState(() {
      _tahminiLot = widget.ipo.tahminiLot(katilimci);
      _tahminiTutar = _tahminiLot * widget.ipo.arzFiyati * 100;
    });
  }

  @override
  void dispose() {
    _katilimciController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ipo = widget.ipo;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: CustomScrollView(
        slivers: [
          // AppBar
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: const Color(0xFF0A0E21),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                ipo.sirketKodu,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF00D4AA).withValues(alpha: 0.2),
                      const Color(0xFF00B4D8).withValues(alpha: 0.1),
                      const Color(0xFF0A0E21),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Şirket Bilgileri
                  _buildSectionTitle('Şirket Bilgileri'),
                  const SizedBox(height: 12),
                  _buildInfoCard([
                    _buildInfoRow('Şirket Adı', ipo.sirketAdi),
                    _buildInfoRow(
                      'Arz Fiyatı',
                      '₺${ipo.arzFiyati.toStringAsFixed(2)}',
                    ),
                    _buildInfoRow(
                      'Toplam Lot',
                      '${_formatNumber(ipo.toplamLot)} Lot',
                    ),
                    _buildInfoRow('Dağıtım Şekli', ipo.dagitimSekli),
                    _buildInfoRow('Konsorsiyum Lideri', ipo.konsorsiyumLideri),
                    _buildInfoRow(
                      'Pazar',
                      ipo.pazar.isEmpty ? 'Belirtilmedi' : ipo.pazar,
                    ),
                    _buildInfoRow(
                      'Katılım Endeksine Uygun',
                      ipo.katilimEndeksineUygun ? '✅ Evet' : '❌ Hayır',
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // Tarihler
                  _buildSectionTitle('Tarihler'),
                  const SizedBox(height: 12),
                  _buildInfoCard([
                    _buildInfoRow('Halka Arz Tarihi', ipo.tarih.isEmpty ? 'Belirtilmedi' : ipo.tarih),
                    _buildInfoRow(
                      'Bist İlk İşlem',
                      ipo.bistIlkIslemTarihi.isEmpty
                          ? 'Belirtilmedi'
                          : ipo.bistIlkIslemTarihi,
                    ),
                    if (ipo.durum == 'islem' && ipo.sonFiyat != null)
                      _buildInfoRow('Son Fiyat', ipo.sonFiyatFormatli),
                  ]),

                  const SizedBox(height: 20),

                  // İşlem gören hisseler için açıklama
                  if (ipo.durum == 'islem' &&
                      ipo.sirketAciklama.isNotEmpty) ...[
                    _buildSectionTitle('Şirket Açıklaması'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1F38),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF2A2F4A), width: 0.5),
                      ),
                      child: Text(
                        ipo.sirketAciklama,
                        style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ---- Tahmini Lot Hesaplayıcı ----
                  _buildSectionTitle('Tahmini Lot Hesaplayıcı'),
                  const SizedBox(height: 12),
                  _buildCalculatorCard(ipo),

                  const SizedBox(height: 24),

                  // Portföye Ekle butonu
                  _buildAddToPortfolioButton(ipo),

                  const SizedBox(height: 24),

                  // Yasal Uyarı / Gecikme Notu
                  Center(
                    child: Text(
                      'Piyasa kuralları gereği veriler 15-20 dakika gecikmeli sağlanmaktadır.',
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 40),
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
        color: const Color(0xFF00D4AA),
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2F4A), width: 0.5),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  // _buildFonKullanimCard kaldırıldı (artık fonKullanimYeri verisi çekilmiyor)

  Widget _buildCalculatorCard(IpoModel ipo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00D4AA).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Input
          Text(
            'Tahmini Katılımcı Sayısı',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _katilimciController,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Örn: 150000',
                    hintStyle: GoogleFonts.inter(
                      color: Colors.white24,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF12162B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    prefixIcon: const Icon(
                      Icons.people_outline,
                      color: Color(0xFF00D4AA),
                      size: 20,
                    ),
                  ),
                  onChanged: (_) => _hesapla(),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _hesapla,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D4AA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Hesapla',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),

          // Sonuçlar
          if (_tahminiLot > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF00D4AA).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF00D4AA).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Tahmini Lot',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _tahminiLot.toStringAsFixed(2),
                          style: GoogleFonts.inter(
                            color: const Color(0xFF00D4AA),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.white12),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Gerekli Tutar',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₺${_formatCurrency(_tahminiTutar)}',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF00B4D8),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Kişi Başı Lot Bilgisi
          if (ipo.kisiBashiLot.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF12162B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_rounded,
                    color: Color(0xFFFFBE0B),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Kişi Başı Lot: ',
                    style: GoogleFonts.inter(
                      color: Color(0xFFFFBE0B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    ipo.kisiBashiLot,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // _buildKisiBasiLotCard kaldırıldı (sonKatilimciSayilari artık yok)

  Widget _buildAddToPortfolioButton(IpoModel ipo) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddPortfolioScreen(ipo: ipo)),
          );
        },
        icon: const Icon(Icons.add_circle_outline_rounded),
        label: Text(
          'Portföye Ekle',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00D4AA),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    }
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}K';
    }
    return number.toString();
  }

  String _formatCurrency(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)}M';
    }
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(2);
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }
}
