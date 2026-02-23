import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ipo_model.dart';
import '../models/portfolio_item.dart';
import '../services/portfolio_service.dart';

/// Portföye halka arz ekleme ekranı — çoklu hesap desteği
class AddPortfolioScreen extends StatefulWidget {
  final IpoModel ipo;

  const AddPortfolioScreen({super.key, required this.ipo});

  @override
  State<AddPortfolioScreen> createState() => _AddPortfolioScreenState();
}

class _AddPortfolioScreenState extends State<AddPortfolioScreen> {
  final _lotController = TextEditingController(text: '1');
  final _hesapController = TextEditingController(text: '1');

  int get _lot => int.tryParse(_lotController.text) ?? 1;
  int get _hesap => int.tryParse(_hesapController.text) ?? 1;
  int get _toplamLot => _lot * _hesap;
  double get _toplamMaliyet => _toplamLot * widget.ipo.arzFiyati;

  @override
  void dispose() {
    _lotController.dispose();
    _hesapController.dispose();
    super.dispose();
  }

  Future<void> _ekle() async {
    final item = PortfolioItem(
      id: '${widget.ipo.sirketKodu}_${DateTime.now().millisecondsSinceEpoch}',
      sirketKodu: widget.ipo.sirketKodu,
      sirketAdi: widget.ipo.sirketAdi,
      arzFiyati: widget.ipo.arzFiyati,
      lotSayisi: _lot,
      hesapSayisi: _hesap,
      eklenmeTarihi: DateTime.now(),
    );

    await PortfolioService.addItem(item);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.ipo.sirketAdi} portföye eklendi!',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF00D4AA),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      Navigator.pop(context);
      Navigator.pop(context); // Detay sayfasını da kapat
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Portföye Ekle',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Şirket bilgisi kartı
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF00D4AA).withValues(alpha: 0.1),
                    const Color(0xFF00B4D8).withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF00D4AA).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D4AA).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.ipo.sirketKodu,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF00D4AA),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.ipo.sirketAdi,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Arz Fiyatı: ₺${widget.ipo.arzFiyati.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Kaç farklı hesaptan katıldınız?
            Text(
              'Kaç farklı hesaptan katıldınız?',
              style: GoogleFonts.inter(
                color: const Color(0xFFFFBE0B),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Toplam lot hesabında hesap sayısı × lot olarak hesaplanır',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 10),
            _buildNumberInput(
              controller: _hesapController,
              icon: Icons.account_balance_outlined,
              label: 'Hesap Sayısı',
              hint: 'Örn: 4',
            ),

            const SizedBox(height: 20),

            // Lot sayısı
            Text(
              'Her hesaptan aldığınız lot sayısı',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _buildNumberInput(
              controller: _lotController,
              icon: Icons.inventory_2_outlined,
              label: 'Lot Sayısı',
              hint: 'Örn: 1',
            ),

            const SizedBox(height: 24),

            // Özet kartı
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F38),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF2A2F4A),
                  width: 0.5,
                ),
              ),
              child: Column(
                children: [
                  _buildSummaryRow('Hesap Sayısı', '$_hesap adet'),
                  _buildSummaryRow('Lot / Hesap', '$_lot lot'),
                  const Divider(color: Color(0xFF2A2F4A), height: 24),
                  _buildSummaryRow(
                    'Toplam Lot',
                    '$_toplamLot lot',
                    highlight: true,
                  ),
                  _buildSummaryRow(
                    'Toplam Maliyet',
                    '₺${_toplamMaliyet.toStringAsFixed(2)}',
                    highlight: true,
                    color: const Color(0xFF00B4D8),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Ekle butonu
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _ekle,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  'Portföye Ekle',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberInput({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.white24),
        filled: true,
        fillColor: const Color(0xFF1A1F38),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2F4A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A2F4A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00D4AA), width: 1.5),
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF00D4AA)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool highlight = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: color ?? (highlight ? Colors.white : Colors.white70),
              fontSize: highlight ? 15 : 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
