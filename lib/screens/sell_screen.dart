import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/portfolio_item.dart';
import '../services/portfolio_service.dart';

/// Satış ekranı — Manuel satış fiyatı girişi ve net kar hesabı
class SellScreen extends StatefulWidget {
  final PortfolioItem item;

  const SellScreen({super.key, required this.item});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  final _fiyatController = TextEditingController();

  double get _satisFiyati =>
      double.tryParse(_fiyatController.text.replaceAll(',', '.')) ?? 0;

  double get _netKar {
    if (_satisFiyati <= 0) return 0;
    return (widget.item.toplamHisse * _satisFiyati) - widget.item.toplamMaliyet;
  }

  double get _netKarYuzde {
    if (widget.item.toplamMaliyet == 0) return 0;
    return (_netKar / widget.item.toplamMaliyet) * 100;
  }

  Future<void> _sat() async {
    if (_satisFiyati <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Satışı Onayla',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '${widget.item.sirketAdi} hisselerinizi '
          '₺${_satisFiyati.toStringAsFixed(2)} fiyattan satmak istediğinize emin misiniz?\n\n'
          'Net ${_netKar >= 0 ? "Kar" : "Zarar"}: '
          '₺${_netKar.abs().toStringAsFixed(2)}',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
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
              backgroundColor: _netKar >= 0
                  ? const Color(0xFF00D4AA)
                  : const Color(0xFFFF4757),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Sat',
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
      final netKar = await PortfolioService.sellItem(
        widget.item.id,
        _satisFiyati,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Satış tamamlandı! Net ${netKar >= 0 ? "Kar" : "Zarar"}: '
              '₺${netKar.abs().toStringAsFixed(2)}',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            backgroundColor:
                netKar >= 0 ? const Color(0xFF00D4AA) : const Color(0xFFFF4757),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    }
  }

  @override
  void dispose() {
    _fiyatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Hisse Sat',
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
            // Mevcut pozisyon bilgisi
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00D4AA).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.sirketKodu,
                          style: GoogleFonts.inter(
                            color: const Color(0xFF00D4AA),
                            fontWeight: FontWeight.w800,
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
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildRow('Alış Fiyatı', '₺${item.arzFiyati.toStringAsFixed(2)}'),
                  _buildRow('Toplam Lot', '${item.toplamLot} (${item.hesapSayisi} hesap × ${item.lotSayisi} lot)'),
                  _buildRow('Toplam Hisse', '${item.toplamHisse} adet'),
                  _buildRow('Toplam Maliyet', '₺${item.toplamMaliyet.toStringAsFixed(2)}'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Satış fiyatı girişi
            Text(
              'Satış Fiyatı',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hisse başına satış fiyatını girin',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _fiyatController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: GoogleFonts.inter(
                  color: Colors.white24,
                  fontSize: 22,
                ),
                filled: true,
                fillColor: const Color(0xFF1A1F38),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF2A2F4A)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF2A2F4A)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF00D4AA), width: 1.5),
                ),
                prefixText: '₺ ',
                prefixStyle: GoogleFonts.inter(
                  color: const Color(0xFF00D4AA),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 24),

            // Net kar/zarar gösterimi
            if (_satisFiyati > 0)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _netKar >= 0
                        ? [
                            const Color(0xFF00D4AA).withValues(alpha: 0.1),
                            const Color(0xFF00D4AA).withValues(alpha: 0.05),
                          ]
                        : [
                            const Color(0xFFFF4757).withValues(alpha: 0.1),
                            const Color(0xFFFF4757).withValues(alpha: 0.05),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (_netKar >= 0
                            ? const Color(0xFF00D4AA)
                            : const Color(0xFFFF4757))
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _netKar >= 0 ? 'NET KAR' : 'NET ZARAR',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_netKar >= 0 ? '+' : ''}₺${_netKar.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        color: _netKar >= 0
                            ? const Color(0xFF00D4AA)
                            : const Color(0xFFFF4757),
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_netKarYuzde >= 0 ? '+' : ''}%${_netKarYuzde.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                        color: _netKar >= 0
                            ? const Color(0xFF00D4AA).withValues(alpha: 0.7)
                            : const Color(0xFFFF4757).withValues(alpha: 0.7),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 30),

            // Sat butonu
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _satisFiyati > 0 ? _sat : null,
                icon: const Icon(Icons.sell_outlined),
                label: Text(
                  'Satışı Tamamla',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _netKar >= 0
                      ? const Color(0xFF00D4AA)
                      : const Color(0xFFFF4757),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white12,
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

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
}
