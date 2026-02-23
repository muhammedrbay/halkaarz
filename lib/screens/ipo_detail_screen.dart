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
                      'İskonto Oranı',
                      '%${ipo.iskontoOrani.toStringAsFixed(1)}',
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
                    _buildInfoRow('Talep Toplama', ipo.talepTarihAraligi),
                    _buildInfoRow(
                      'Borsada İşlem',
                      ipo.borsadaIslemTarihi.isEmpty
                          ? 'Belirtilmedi'
                          : _formatDate(ipo.borsadaIslemTarihi),
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // Fon Kullanım Yeri (Pie Chart benzeri gösterim)
                  _buildSectionTitle('Fon Kullanım Yeri'),
                  const SizedBox(height: 12),
                  _buildFonKullanimCard(ipo),

                  const SizedBox(height: 24),

                  // ---- Kişi Başı Lot Kartı (sadece sonuçlanmış arzlarda) ----
                  if (ipo.durum == 'islem_goruyor' &&
                      ipo.sonKatilimciSayilari.isNotEmpty) ...[
                    _buildKisiBasiLotCard(ipo),
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

  Widget _buildFonKullanimCard(IpoModel ipo) {
    final fon = ipo.fonKullanimYeri;
    final entries = [
      MapEntry('Yatırım', (fon['yatirim'] ?? 0).toDouble()),
      MapEntry('Borç Ödeme', (fon['borc_odeme'] ?? 0).toDouble()),
      MapEntry('İşletme Sermayesi', (fon['isletme_sermayesi'] ?? 0).toDouble()),
    ];

    final colors = [
      const Color(0xFF00D4AA),
      const Color(0xFF00B4D8),
      const Color(0xFFFFBE0B),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2F4A), width: 0.5),
      ),
      child: Column(
        children: [
          // Bar chart gösterimi
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 20,
              child: Row(
                children: entries.asMap().entries.map((e) {
                  final pct = e.value.value;
                  return Expanded(
                    flex: pct.toInt().clamp(1, 100),
                    child: Container(color: colors[e.key]),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...entries.asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors[e.key],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    e.value.key,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '%${e.value.value.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

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

          // Son 3 Halka Arza Katılan Kişi Sayıları
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF12162B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      color: Color(0xFFFFBE0B),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Son 3 Halka Arza Katılan Kişi Sayıları',
                      style: GoogleFonts.inter(
                        color: Color(0xFFFFBE0B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (ipo.sonKatilimciSayilari.isEmpty)
                  Text(
                    'Henüz referans verisi yok',
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  )
                else
                  ...ipo.sonKatilimciSayilari.asMap().entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${e.key + 1}',
                              style: GoogleFonts.inter(
                                color: Colors.white38,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_formatNumber(e.value)} kişi',
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKisiBasiLotCard(IpoModel ipo) {
    final katilimci = ipo.sonKatilimciSayilari.last;
    final kisiBasiLot = katilimci > 0 ? (ipo.toplamLot / katilimci) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF00D4AA).withValues(alpha: 0.08),
            const Color(0xFF00B4D8).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00D4AA).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4AA).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Color(0xFF00D4AA),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kişi Başı Ortalama',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '${kisiBasiLot.toStringAsFixed(1)} Lot Düştü',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF00D4AA),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatNumber(ipo.toplamLot)} lot / ${_formatNumber(katilimci)} kişi',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
