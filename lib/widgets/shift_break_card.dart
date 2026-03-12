import 'dart:async';
import 'package:flutter/material.dart';
import '../models/courier_daily_log.dart';
import '../services/shift_log_service.dart';
import '../services/break_service.dart';

/// Vardiya & Mola Kartı Widget'ı
/// Ana ekranda küçük bir kart olarak görünür
class ShiftBreakCard extends StatefulWidget {
  final int courierId;

  const ShiftBreakCard({
    super.key,
    required this.courierId,
  });

  @override
  State<ShiftBreakCard> createState() => _ShiftBreakCardState();
}

class _ShiftBreakCardState extends State<ShiftBreakCard> {
  final ShiftLogService _shiftLogService = ShiftLogService();
  final BreakService _breakService = BreakService();

  CourierDailyLog? _activeLog;
  StreamSubscription<CourierDailyLog?>? _logSubscription;
  Timer? _refreshTimer;
  Map<String, dynamic>? _currentBreakInfo;

  @override
  void initState() {
    super.initState();
    _loadActiveShift();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Aktif vardiyayı yükle ve dinle
  Future<void> _loadActiveShift() async {
    // Önce tek seferlik yükle
    final activeLog = await _shiftLogService.getActiveShift(widget.courierId);
    if (mounted) {
      setState(() {
        _activeLog = activeLog;
      });
      _updateBreakInfo();
    }

    // Sonra real-time dinle
    _logSubscription = _shiftLogService
        .watchActiveShift(widget.courierId)
        .listen((log) {
      if (mounted) {
        setState(() {
          _activeLog = log;
        });
        _updateBreakInfo();
      }
    });
  }

  /// Anlık mola bilgisini güncelle
  Future<void> _updateBreakInfo() async {
    if (_activeLog?.status == 'BREAK') {
      final info = await _breakService.getCurrentBreakInfo(widget.courierId);
      if (mounted) {
        setState(() {
          _currentBreakInfo = info;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _currentBreakInfo = null;
        });
      }
    }
  }

  /// Her saniye yenile (anlık sayaç için)
  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeLog?.status == 'BREAK') {
        _updateBreakInfo();
      }
    });
  }

  /// Vardiyaya başla
  Future<void> _startShift() async {
    try {
      // breakAllowedMinutes değerini al
      final breakAllowed = await _shiftLogService.getBreakAllowedMinutes(widget.courierId);

      final result = await _shiftLogService.startShift(widget.courierId, breakAllowed);

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] as String),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          _loadActiveShift(); // Yeniden yükle
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] as String),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Vardiyayı bitir
  Future<void> _endShift() async {
    // Onay al
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vardiyayı Bitir'),
        content: const Text('Vardiyayı bitirmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Bitir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final result = await _shiftLogService.endShift(widget.courierId);

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] as String),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          _loadActiveShift(); // Yeniden yükle
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] as String),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Molaya çık
  Future<void> _startBreak() async {
    try {
      final result = await _breakService.startBreak(widget.courierId);

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] as String),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
          _loadActiveShift(); // Yeniden yükle
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] as String),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Molayı bitir
  Future<void> _endBreak() async {
    try {
      final result = await _breakService.endBreak(widget.courierId);

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] as String),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          _loadActiveShift(); // Yeniden yükle
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] as String),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Vardiya yoksa veya kapalıysa - "Vardiyaya Başla" butonu
    if (_activeLog == null || _activeLog!.isClosed) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.grey[600], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Vardiya & Mola',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Durum: OFF',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startShift,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Vardiyaya Başla'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Vardiya açık - Duruma göre göster
    final status = _activeLog!.status;
    final breakAllowed = _activeLog!.breakAllowedMinutes;
    final breakUsed = _activeLog!.breakUsedMinutes;
    final breakRemaining = _activeLog!.breakRemainingMinutes;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                _getStatusIcon(status),
                color: _getStatusColor(status),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Vardiya & Mola',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Durum
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getStatusColor(status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Durum: ${_getStatusText(status)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _getStatusColor(status),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Mola bilgileri
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBreakInfo('Toplam', '$breakAllowed dk', Colors.blue),
              _buildBreakInfo('Kullanılan', '$breakUsed dk', Colors.orange),
              _buildBreakInfo('Kalan', '$breakRemaining dk', breakRemaining > 0 ? Colors.green : Colors.red),
            ],
          ),

          // BREAK durumunda anlık sayaç
          if (status == 'BREAK' && _currentBreakInfo != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        'Geçen',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentBreakInfo!['elapsedFormatted'] as String,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.blue.shade200,
                  ),
                  Column(
                    children: [
                      Text(
                        'Kalan',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentBreakInfo!['remainingFormatted'] as String,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: breakRemaining > 0 ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Butonlar
          if (status == 'OFF' || _activeLog!.isClosed)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startShift,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Vardiyaya Başla'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            )
          else if (status == 'ACTIVE') ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: breakRemaining > 0 ? _startBreak : null,
                    icon: const Icon(Icons.free_breakfast, size: 18),
                    label: const Text('Molaya Çık'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _endShift,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Vardiyayı Bitir'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            if (breakRemaining <= 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ Mola hakkınız bitti',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange[700],
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ]
          else if (status == 'BREAK') ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _endBreak,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Molayı Bitir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _endShift,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Vardiyayı Bitir'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'ACTIVE':
        return Icons.check_circle;
      case 'BREAK':
        return Icons.free_breakfast;
      case 'OFF':
      default:
        return Icons.access_time;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'ACTIVE':
        return Colors.green;
      case 'BREAK':
        return Colors.blue;
      case 'OFF':
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'ACTIVE':
        return 'AKTİF';
      case 'BREAK':
        return 'MOLADA';
      case 'OFF':
      default:
        return 'KAPALI';
    }
  }
}
