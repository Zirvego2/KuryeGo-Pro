import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../services/firebase_service.dart';

// Brand colors
const _kPrimary = Color(0xFF2563EB);
const _kPrimaryDark = Color(0xFF1D4ED8);
const _kSurface = Color(0xFFF8FAFC);
const _kCardBg = Color(0xFFFFFFFF);
const _kBorder = Color(0xFFE2E8F0);
const _kTextPrimary = Color(0xFF111827);
const _kTextSecondary = Color(0xFF6B7280);
const _kSuccess = Color(0xFF10B981);
const _kInfoBg = Color(0xFFEFF6FF);
const _kInfoBorder = Color(0xFFBFDBFE);
const _kInfoText = Color(0xFF1D4ED8);

class ExternalOrderScreen extends StatefulWidget {
  final int bayId;
  final int courierId;

  const ExternalOrderScreen({
    super.key,
    required this.bayId,
    required this.courierId,
  });

  @override
  State<ExternalOrderScreen> createState() => _ExternalOrderScreenState();
}

class _ExternalOrderScreenState extends State<ExternalOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  static const String _baseUrl = 'https://zirvego.app';

  int? _selectedWorkId;
  String? _selectedWorkName;
  int? _packageCount;
  String? _reason;
  String _note = '';
  LatLng? _selectedLocation;

  bool _submitting = false;
  bool _worksLoading = true;
  List<Map<String, dynamic>> _works = [];

  @override
  void initState() {
    super.initState();
    _loadWorks();
  }

  Future<void> _loadWorks() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('t_work')
          .where('s_bay', isEqualTo: widget.bayId)
          .get();

      final List<Map<String, dynamic>> items = [];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final workId = data['s_id'] as int?;
        if (workId == null) continue;

        LatLng? loc;
        final sLoc = data['s_loc'];
        if (sLoc is Map) {
          final ss = sLoc['ss_location'];
          if (ss is GeoPoint) {
            loc = LatLng(ss.latitude, ss.longitude);
          }
        }
        items.add({
          'id': workId,
          'name': data['s_name'] ?? 'İşletme',
          'loc': loc,
        });
      }
      items.sort((a, b) =>
          (a['name'] as String).compareTo(b['name'] as String));
      if (!mounted) return;
      setState(() {
        _works = items;
        _worksLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _worksLoading = false);
      _showError('İşletmeler yüklenemedi: $e');
    }
  }

  /// 150 işletme için arama destekli seçim dialogu
  Future<void> _showWorkSearchDialog() async {
    String query = '';
    List<Map<String, dynamic>> filtered = List.of(_works);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Başlık
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                    decoration: const BoxDecoration(
                      color: _kPrimary,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.store_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'İşletme Seçin',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  // Arama kutusu
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'İşletme ara...',
                        hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: _kPrimary, size: 20),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: _kTextSecondary),
                                onPressed: () {
                                  setDialogState(() {
                                    query = '';
                                    filtered = List.of(_works);
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: _kSurface,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kPrimary, width: 2),
                        ),
                      ),
                      onChanged: (v) {
                        setDialogState(() {
                          query = v;
                          final q = v.toLowerCase();
                          filtered = _works
                              .where((w) => (w['name'] as String).toLowerCase().contains(q))
                              .toList();
                        });
                      },
                    ),
                  ),
                  // Sonuç sayısı
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${filtered.length} işletme',
                        style: const TextStyle(fontSize: 12, color: _kTextSecondary),
                      ),
                    ),
                  ),
                  // Liste
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.45,
                    ),
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Sonuç bulunamadı', style: TextStyle(color: _kTextSecondary)),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorder),
                            itemBuilder: (_, i) {
                              final w = filtered[i];
                              final isSelected = w['id'] == _selectedWorkId;
                              return InkWell(
                                onTap: () => Navigator.pop(ctx, w),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  color: isSelected ? _kPrimary.withOpacity(0.07) : null,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.store_rounded,
                                        size: 16,
                                        color: isSelected ? _kPrimary : _kTextSecondary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          w['name'] as String,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                            color: isSelected ? _kPrimary : _kTextPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check_circle_rounded, size: 18, color: _kPrimary),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedWorkId = result['id'] as int;
        _selectedWorkName = result['name'] as String;
      });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: _kSuccess,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWorkId == null) { _showError('Lütfen bir işletme seçin'); return; }
    if (_packageCount == null)   { _showError('Lütfen paket miktarını seçin'); return; }
    if (_reason == null || _reason!.isEmpty) { _showError('Lütfen nedeni seçin'); return; }

    final enabled = await FirebaseService.isExternalOrderEntryEnabledForBay(widget.bayId);
    if (!enabled) {
      if (!mounted) return;
      _showError('Sistem dışı paket girişi kapalı');
      return;
    }

    setState(() => _submitting = true);
    try {
      final payload = {
        's_bay': widget.bayId,
        's_courier': widget.courierId,
        's_work': _selectedWorkId,
        's_package_count': _packageCount,
        's_reason': _reason,
        's_note': _note.trim().isEmpty ? null : _note.trim(),
      };

      final uri = Uri.parse('$_baseUrl/api/external-orders/create');
      final resp = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      final status = resp.statusCode;
      final bodyText = resp.body.trim();
      Map<String, dynamic>? json;
      if (bodyText.isNotEmpty) {
        try { json = jsonDecode(bodyText) as Map<String, dynamic>?; } catch (_) {}
      }

      if (status == 201 && json?['success'] == true) {
        if (!mounted) return;
        _showSuccess('Kayıt gönderildi, onay bekliyor');
        Navigator.of(context).pop(true);
        return;
      }

      String message = 'Kayıt oluşturulamadı';
      if (status == 403) {
        message = json?['message']?.toString() ?? 'Sistem dışı paket girişi kapalı';
      } else if (status == 429) {
        message = json?['message']?.toString() ?? 'Çok hızlı istek. Lütfen tekrar deneyin.';
      } else if (status == 400) {
        final errs = json?['errors'];
        message = (errs is List && errs.isNotEmpty) ? errs.first.toString() : 'Geçersiz istek';
      } else if (json?['message'] != null) {
        message = json!['message'].toString();
      }

      if (!mounted) return;
      _showError(message);
    } catch (e) {
      if (!mounted) return;
      _showError('Hata: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 14),
      labelStyle: const TextStyle(color: _kTextSecondary, fontWeight: FontWeight.w500),
      floatingLabelStyle: const TextStyle(color: _kPrimary, fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, color: _kPrimary, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      filled: true,
      fillColor: _kSurface,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.red.shade500, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Sistem Dışı Paket Ekle',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Bilgi Bandı ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _kInfoBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kInfoBorder, width: 1.5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _kPrimary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.info_rounded, color: _kPrimary, size: 16),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Bu form yalnızca sistem dışı (entegrasyon harici) paketleri hızlıca bildirmeniz için tasarlanmıştır.',
                          style: TextStyle(
                            color: _kInfoText,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Zorunlu Bilgiler Kartı ──
                _SectionCard(
                  icon: Icons.assignment_outlined,
                  iconColor: _kPrimary,
                  title: 'Zorunlu Bilgiler',
                  subtitle: 'Aşağıdaki alanların tamamı zorunludur.',
                  child: Column(
                    children: [
                      // İşletme — arama destekli seçim
                      _worksLoading
                        ? Container(
                            height: 52,
                            decoration: BoxDecoration(
                              color: _kSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _kBorder),
                            ),
                            child: const Center(
                              child: SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimary),
                              ),
                            ),
                          )
                        : FormField<int>(
                            initialValue: _selectedWorkId,
                            validator: (_) => _selectedWorkId == null ? 'İşletme seçin' : null,
                            builder: (field) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: _showWorkSearchDialog,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    height: 52,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: _kSurface,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: field.hasError ? Colors.red.shade400 : _kBorder,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.store_rounded, color: _kPrimary, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _selectedWorkName ?? 'İşletme seçin',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: _selectedWorkName != null ? _kTextPrimary : _kTextSecondary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(Icons.search, color: _kTextSecondary, size: 20),
                                      ],
                                    ),
                                  ),
                                ),
                                if (field.hasError)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12, top: 4),
                                    child: Text(
                                      field.errorText!,
                                      style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      const SizedBox(height: 12),

                      // Paket miktarı
                      DropdownButtonFormField<int>(
                        decoration: _fieldDecoration(
                          label: 'Paket Miktarı',
                          hint: '1 – 10 arasında seçin',
                          icon: Icons.inventory_2_rounded,
                        ),
                        dropdownColor: _kCardBg,
                        borderRadius: BorderRadius.circular(12),
                        value: _packageCount,
                        items: List.generate(10, (i) => i + 1)
                            .map((n) => DropdownMenuItem<int>(
                                  value: n,
                                  child: Text(
                                    '$n paket',
                                    style: const TextStyle(fontSize: 14, color: _kTextPrimary),
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _packageCount = v),
                        validator: (v) => v == null ? 'Paket miktarı zorunlu' : null,
                      ),
                      const SizedBox(height: 12),

                      // Neden
                      DropdownButtonFormField<String>(
                        decoration: _fieldDecoration(
                          label: 'Nedeni Nedir?',
                          hint: 'Bir neden seçin',
                          icon: Icons.help_outline_rounded,
                        ),
                        dropdownColor: _kCardBg,
                        borderRadius: BorderRadius.circular(12),
                        value: _reason,
                        items: const [
                          DropdownMenuItem(
                            value: 'kapida_iptal',
                            child: Text('Kapıya giden sipariş iptali',
                                style: TextStyle(fontSize: 14, color: _kTextPrimary)),
                          ),
                          DropdownMenuItem(
                            value: 'bekleme_suresi',
                            child: Text('İşletmede fazla bekleme süresi',
                                style: TextStyle(fontSize: 14, color: _kTextPrimary)),
                          ),
                          DropdownMenuItem(
                            value: 'uzak_mesafe',
                            child: Text('Uzak mesafe',
                                style: TextStyle(fontSize: 14, color: _kTextPrimary)),
                          ),
                          DropdownMenuItem(
                            value: 'diger',
                            child: Text('Diğer',
                                style: TextStyle(fontSize: 14, color: _kTextPrimary)),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _reason = v);
                          _formKey.currentState?.validate();
                        },
                        validator: (v) => (v == null || v.isEmpty) ? 'Neden seçimi zorunlu' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Opsiyonel Bilgi Kartı ──
                _SectionCard(
                  icon: Icons.notes_rounded,
                  iconColor: _kTextSecondary,
                  title: 'Açıklama',
                  subtitle: 'Dilerseniz ek açıklama ekleyebilirsiniz.',
                  child: TextFormField(
                    style: const TextStyle(fontSize: 14, color: _kTextPrimary),
                    decoration: InputDecoration(
                      hintText: 'Kısa açıklama girin...',
                      hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 14),
                      alignLabelWithHint: true,
                      contentPadding: const EdgeInsets.all(14),
                      filled: true,
                      fillColor: _kSurface,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorder, width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kPrimary, width: 2),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.red.shade500, width: 2),
                      ),
                    ),
                    maxLines: 4,
                    onChanged: (v) => _note = v,
                    validator: (v) {
                      if (_reason == 'diger' && (v == null || v.trim().isEmpty)) {
                        return '"Diğer" seçildiğinde açıklama zorunludur';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 28),

                // ── Gönder Butonu ──
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _submitting ? _kPrimary.withOpacity(0.7) : _kPrimary,
                      foregroundColor: Colors.white,
                      elevation: _submitting ? 0 : 3,
                      shadowColor: _kPrimary.withOpacity(0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: 18, width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                              SizedBox(width: 10),
                              Text('Gönderiliyor...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            ],
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.send_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Gönder', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Yardımcı bileşen: Bölüm Kartı ──
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _kTextPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _kTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Divider(color: _kBorder, height: 24),
            child,
          ],
        ),
      ),
    );
  }
}
