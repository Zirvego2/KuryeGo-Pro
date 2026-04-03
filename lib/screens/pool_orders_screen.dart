import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../services/pool_order_service.dart';

// Brand colors
const _kPrimary     = Color(0xFF2563EB);
const _kSurface     = Color(0xFFF8FAFC);
const _kCardBg      = Color(0xFFFFFFFF);
const _kBorder      = Color(0xFFE2E8F0);
const _kTextPrimary = Color(0xFF111827);
const _kTextMuted   = Color(0xFF6B7280);
const _kSuccess     = Color(0xFF10B981);
const _kWarning     = Color(0xFFF59E0B);
const _kDanger      = Color(0xFFEF4444);

class PoolOrdersScreen extends StatefulWidget {
  final int courierId;
  final int bayId;
  final int courierStatus;
  final bool allowWhileBusy;
  final String businessScope;
  final List<int> businessIds;

  const PoolOrdersScreen({
    super.key,
    required this.courierId,
    required this.bayId,
    required this.courierStatus,
    required this.allowWhileBusy,
    required this.businessScope,
    required this.businessIds,
  });

  @override
  State<PoolOrdersScreen> createState() => _PoolOrdersScreenState();
}

class _PoolOrdersScreenState extends State<PoolOrdersScreen> {
  /// sWork (int) → işletme adı (t_work'ten çekilen)
  final Map<int, String> _workNames = {};

  String _paymentTypeText(int payType) {
    switch (payType) {
      case 0:  return 'Nakit';
      case 1:  return 'Kart';
      case 2:  return 'Online';
      default: return 'Bilinmiyor';
    }
  }

  Color _paymentColor(int payType) {
    switch (payType) {
      case 0:  return const Color(0xFF16A34A);
      case 1:  return _kPrimary;
      case 2:  return const Color(0xFF7C3AED);
      default: return _kTextMuted;
    }
  }

  IconData _paymentIcon(int payType) {
    switch (payType) {
      case 0:  return Icons.payments_outlined;
      case 1:  return Icons.credit_card_rounded;
      case 2:  return Icons.language_rounded;
      default: return Icons.help_outline;
    }
  }

  /// Eksik işletme adlarını t_work'ten çek, UI sessizce güncellenir
  Future<void> _enrichWorkNames(List<OrderModel> orders) async {
    final missing = orders
        .map((o) => o.sWork)
        .where((id) => id > 0 && !_workNames.containsKey(id))
        .toSet();
    if (missing.isEmpty) return;

    // Tekrar fetch şimdilik engelle (sentinel)
    _workNames.addAll({for (final id in missing) id: ''});

    final chunks = <List<int>>[];
    final list = missing.toList();
    for (var i = 0; i < list.length; i += 30) {
      chunks.add(list.sublist(i, i + 30 > list.length ? list.length : i + 30));
    }

    final fetched = <int, String>{};
    for (final chunk in chunks) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('t_work')
            .where('s_id', whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final rawId = data['s_id'];
          final sid = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
          final name = data['s_name']?.toString() ?? '';
          if (sid != null && name.isNotEmpty) fetched[sid] = name;
        }
      } catch (_) {}
    }

    if (fetched.isNotEmpty && mounted) {
      setState(() => _workNames.addAll(fetched));
    }
  }

  void _showSnack(BuildContext ctx, String msg, Color color, IconData icon) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500))),
        ]),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  Future<void> _confirmAndClaim(BuildContext context, OrderModel order) async {
    final workName = _workNames[order.sWork] ?? (order.sNameWork.isNotEmpty ? order.sNameWork : null) ?? 'İşletme';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shopping_bag_outlined, color: _kPrimary, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Siparişi Üzerinize Alın',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _kTextPrimary),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(workName ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _kTextPrimary)),
                    const SizedBox(height: 2),
                    Text('#${order.sId}',
                        style: const TextStyle(fontSize: 12, color: _kTextMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Vazgeç', style: TextStyle(color: _kTextMuted)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: _kPrimary.withOpacity(0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Üzerime Al', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    if (widget.courierStatus == 2 && !widget.allowWhileBusy) {
      if (context.mounted) {
        _showSnack(context, 'Aktif siparişiniz varken havuzdan sipariş alamazsınız.',
            _kWarning, Icons.warning_amber_rounded);
      }
      return;
    }

    try {
      final error = await PoolOrderService.claimPoolOrder(
        courierId: widget.courierId,
        orderSId: order.sId,
      );
      if (context.mounted) {
        if (error == null) {
          _showSnack(context, 'Sipariş başarıyla üzerinize alındı.',
              _kSuccess, Icons.check_circle_outline);
        } else {
          _showSnack(context, error, _kDanger, Icons.error_outline);
        }
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, 'İşlem sırasında hata oluştu: $e',
            _kDanger, Icons.error_outline);
      }
    }
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
          'Sipariş Havuzu',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white),
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
              gradient: LinearGradient(colors: [Color(0xFF60A5FA), Color(0xFF2563EB)]),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<OrderModel>>(
        stream: PoolOrderService.watchPoolOrders(
          bayId: widget.bayId,
          scope: widget.businessScope,
          allowedBusinessIds: widget.businessIds,
        ),
        builder: (context, snapshot) {
          // Loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _kPrimary, strokeWidth: 3),
                  SizedBox(height: 16),
                  Text('Siparişler yükleniyor...', style: TextStyle(color: _kTextMuted, fontSize: 14)),
                ],
              ),
            );
          }

          // Error
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 52, color: Colors.red.shade300),
                    const SizedBox(height: 12),
                    Text('Bağlantı hatası',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.red.shade700)),
                    const SizedBox(height: 6),
                    Text('${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _kTextMuted, fontSize: 13)),
                  ],
                ),
              ),
            );
          }

          final orders = snapshot.data ?? [];

          // t_work isimlerini arka planda çek (rebuild tetikleyen setState)
          _enrichWorkNames(orders);

          // Empty state
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _kPrimary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.inbox_rounded, size: 48, color: _kPrimary),
                  ),
                  const SizedBox(height: 16),
                  const Text('Havuz Boş',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _kTextPrimary)),
                  const SizedBox(height: 6),
                  const Text('Şu an uygun sipariş bulunmuyor.',
                      style: TextStyle(color: _kTextMuted, fontSize: 14)),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Sayaç banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: _kPrimary.withOpacity(0.06),
                child: Row(children: [
                  const Icon(Icons.local_shipping_outlined, size: 16, color: _kPrimary),
                  const SizedBox(width: 8),
                  Text(
                    '${orders.length} sipariş bekliyor',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kPrimary),
                  ),
                ]),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    // t_work'ten gelen ad öncelikli, yoksa sipariş içindeki ad
                    final tWorkName = _workNames[order.sWork];
                    final fallback = order.sNameWork.isNotEmpty
                        ? order.sNameWork
                        : 'İşletme #${order.sWork}';
                    final displayName = (tWorkName != null && tWorkName.isNotEmpty)
                        ? tWorkName
                        : fallback;

                    final km = double.tryParse(order.sDinstance) ?? 0;
                    final payColor = _paymentColor(order.ssPaytype);
                    final payIcon  = _paymentIcon(order.ssPaytype);
                    final payText  = _paymentTypeText(order.ssPaytype);

                    return Container(
                      decoration: BoxDecoration(
                        color: _kCardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _kBorder, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // ── Kart Başlığı — işletme adı ──
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: _kPrimary.withOpacity(0.06),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.store_rounded, size: 15, color: _kPrimary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 14, color: _kTextPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: _kBorder),
                                ),
                                child: Text(
                                  '#${order.sId}',
                                  style: const TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.w600, color: _kTextMuted),
                                ),
                              ),
                            ]),
                          ),

                          // ── Kart İçeriği ──
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            child: Column(
                              children: [
                                // Adres
                                _InfoRow(
                                  icon: Icons.location_on_outlined,
                                  iconColor: _kDanger,
                                  label: 'Adres',
                                  value: order.ssAdres.isEmpty ? 'Adres bilgisi yok' : order.ssAdres,
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 8),
                                Row(children: [
                                  Expanded(
                                    child: _InfoRow(
                                      icon: Icons.route_outlined,
                                      iconColor: const Color(0xFF8B5CF6),
                                      label: 'Mesafe',
                                      value: '${km.toStringAsFixed(2)} km',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _InfoRow(
                                      icon: payIcon,
                                      iconColor: payColor,
                                      label: 'Ödeme',
                                      value: payText,
                                      valueColor: payColor,
                                    ),
                                  ),
                                ]),
                                const SizedBox(height: 8),

                                // Tutar
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _kSuccess.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _kSuccess.withOpacity(0.2)),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.payments_rounded, size: 16, color: _kSuccess),
                                    const SizedBox(width: 8),
                                    const Text('Tutar:', style: TextStyle(fontSize: 13, color: _kTextMuted)),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${order.ssPaycount.toStringAsFixed(2)} TL',
                                      style: const TextStyle(
                                          fontSize: 14, fontWeight: FontWeight.w800, color: _kSuccess),
                                    ),
                                  ]),
                                ),
                                const SizedBox(height: 12),

                                // Üzerime Al butonu
                                SizedBox(
                                  width: double.infinity,
                                  height: 44,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kPrimary,
                                      foregroundColor: Colors.white,
                                      elevation: 2,
                                      shadowColor: _kPrimary.withOpacity(0.35),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => _confirmAndClaim(context, order),
                                    icon: const Icon(Icons.add_task_rounded, size: 18),
                                    label: const Text('Üzerime Al',
                                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Yardımcı: Bilgi Satırı ──
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color? valueColor;
  final int maxLines;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 6),
        Text('$label: ',
            style: const TextStyle(fontSize: 12, color: _kTextMuted, fontWeight: FontWeight.w500)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
                fontSize: 12,
                color: valueColor ?? _kTextPrimary,
                fontWeight: FontWeight.w600),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
