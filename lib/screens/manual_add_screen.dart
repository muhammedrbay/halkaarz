import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/portfolio_item.dart';
import '../services/portfolio_service.dart';
import '../services/data_service.dart';
import '../services/historical_ipo_service.dart';

/// Manuel portföy ekleme — Kullanıcı şirket kodu, adı, fiyat girer
class ManualAddScreen extends StatefulWidget {
  const ManualAddScreen({super.key});

  @override
  State<ManualAddScreen> createState() => _ManualAddScreenState();
}

class _ManualAddScreenState extends State<ManualAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _kodController = TextEditingController();
  final _adController = TextEditingController();
  final _fiyatController = TextEditingController();
  final _lotController = TextEditingController(text: '1');
  final _hesapController = TextEditingController(text: '1');

  int get _lot => int.tryParse(_lotController.text) ?? 1;
  int get _hesap => int.tryParse(_hesapController.text) ?? 1;
  double get _fiyat => double.tryParse(_fiyatController.text) ?? 0;
  int get _toplamLot => _lot * _hesap;
  double get _toplamMaliyet => _toplamLot * _fiyat;

  List<Map<String, dynamic>> _allIpoData = [];

  @override
  void initState() {
    super.initState();
    _loadIpos();
  }

  Future<void> _loadIpos() async {
    final current = await DataService.loadFromLocal();
    final historical = HistoricalIpoService.loadFromCache();

    final Map<String, Map<String, dynamic>> map = {};

    for (var c in current) {
      map[c.sirketKodu] = {
        'kod': c.sirketKodu,
        'ad': c.sirketAdi,
        'arzFiyati': c.arzFiyati,
      };
    }
    for (var h in historical) {
      if (!map.containsKey(h.sirketKodu)) {
        map[h.sirketKodu] = {
          'kod': h.sirketKodu,
          'ad': h.sirketAdi,
          'arzFiyati': h.arzFiyati,
        };
      }
    }

    if (mounted) {
      setState(() {
        _allIpoData = map.values.toList();
      });
    }
  }

  @override
  void dispose() {
    _kodController.dispose();
    _adController.dispose();
    _fiyatController.dispose();
    _lotController.dispose();
    _hesapController.dispose();
    super.dispose();
  }

  Future<void> _ekle() async {
    if (!_formKey.currentState!.validate()) return;

    final item = PortfolioItem(
      id: '${_kodController.text.toUpperCase()}_${DateTime.now().millisecondsSinceEpoch}',
      sirketKodu: _kodController.text.toUpperCase().trim(),
      sirketAdi: _adController.text.trim(),
      arzFiyati: _fiyat,
      lotSayisi: _lot,
      hesapSayisi: _hesap,
      eklenmeTarihi: DateTime.now(),
    );

    await PortfolioService.addItem(item);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${item.sirketAdi} portföye eklendi!',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF00D4AA),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      Navigator.pop(context, true);
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
          'Manuel Portföy Ekle',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Şirket Kodu (Autocomplete)
              _buildLabel(
                'Şirket Kodu (Arama Eklendi)',
                Icons.business_rounded,
              ),
              const SizedBox(height: 8),
              Autocomplete<Map<String, dynamic>>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<Map<String, dynamic>>.empty();
                  }
                  final query = textEditingValue.text.toLowerCase();
                  return _allIpoData.where((ipo) {
                    return ipo['kod'].toString().toLowerCase().contains(
                          query,
                        ) ||
                        ipo['ad'].toString().toLowerCase().contains(query);
                  });
                },
                displayStringForOption: (option) => option['kod'],
                onSelected: (selection) {
                  _kodController.text = selection['kod'];
                  _adController.text = selection['ad'];
                  if (selection['arzFiyati'] != null &&
                      selection['arzFiyati'] > 0) {
                    _fiyatController.text = selection['arzFiyati'].toString();
                  }
                  setState(() {}); // Detayları güncelle
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                      // Bizim kendi kodController'ımız yerine, Autocomplete'in içsel controller'ını baz alıyoruz
                      // ama _kodController içerisine de kopyalıyoruz
                      controller.addListener(() {
                        _kodController.text = controller.text;
                      });
                      return _buildTextField(
                        controller: controller,
                        focusNode: focusNode,
                        hint: 'Aramak için yazın (Örn: THYAO)',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Zorunlu alan'
                            : null,
                      );
                    },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 8,
                      color: Colors.transparent,
                      child: Container(
                        margin: const EdgeInsets.only(top: 8, right: 32),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F38),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2A2F4A)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (BuildContext context, int index) {
                            final option = options.elementAt(index);
                            return InkWell(
                              onTap: () => onSelected(option),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF00D4AA,
                                        ).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        option['kod'],
                                        style: GoogleFonts.inter(
                                          color: const Color(0xFF00D4AA),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        option['ad'],
                                        style: GoogleFonts.inter(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Şirket Adı
              _buildLabel('Şirket Adı', Icons.badge_outlined),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _adController,
                hint: 'Örn: Türk Hava Yolları A.O.',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
              ),

              const SizedBox(height: 20),

              // Arz Fiyatı
              _buildLabel(
                'Arz / Alış Fiyatı (₺)',
                Icons.monetization_on_outlined,
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _fiyatController,
                hint: 'Örn: 32.50',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Zorunlu alan';
                  final val = double.tryParse(v);
                  if (val == null || val <= 0) return 'Geçerli fiyat girin';
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Hesap & Lot
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel(
                          'Hesap Sayısı',
                          Icons.account_balance_outlined,
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _hesapController,
                          hint: '1',
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Lot / Hesap', Icons.inventory_2_outlined),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _lotController,
                          hint: '1',
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Özet Kartı
              Container(
                width: double.infinity,
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
                    _buildSummaryRow('Toplam Lot', '$_toplamLot lot'),
                    const Divider(color: Color(0xFF2A2F4A), height: 20),
                    _buildSummaryRow(
                      'Toplam Maliyet',
                      '₺${_toplamMaliyet.toStringAsFixed(2)}',
                      highlight: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Ekle Butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _ekle,
                  icon: const Icon(Icons.add_circle_outline_rounded),
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
      ),
    );
  }

  Widget _buildLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF00D4AA), size: 16),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF4757)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: highlight ? const Color(0xFF00B4D8) : Colors.white70,
              fontSize: highlight ? 15 : 13,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
