import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrimary = Color(0xFF2563EB);
const _kPrimaryLight = Color(0xFFEFF6FF);
const _kTextPrimary = Color(0xFF111827);
const _kTextMuted = Color(0xFF6B7280);

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.local_shipping_rounded,
      iconColor: Color(0xFF2563EB),
      bgColor: Color(0xFFEFF6FF),
      title: 'ZirveGo Kurye\'ye\nHoş Geldiniz!',
      description:
          'Siparişlerinizi kolayca yönetin, müşterilere hızlı teslimat yapın ve kazancınızı takip edin.',
    ),
    _OnboardingPage(
      icon: Icons.notifications_active_rounded,
      iconColor: Color(0xFF059669),
      bgColor: Color(0xFFECFDF5),
      title: 'Sipariş Bildirimleri',
      description:
          'Yeni sipariş geldiğinde anında bildirim alırsınız. Siparişi kabul veya reddedebilirsiniz. Kabul edilen siparişi restorandan teslim alıp müşteriye götürün.',
    ),
    _OnboardingPage(
      icon: Icons.route_rounded,
      iconColor: Color(0xFF7C3AED),
      bgColor: Color(0xFFF5F3FF),
      title: 'Teslimat Adımları',
      description:
          'Restorandan siparişi alırken "Teslim Al" butonuna basın. Müşteriye teslim ettikten sonra "Teslim Et" butonuna basarak siparişi tamamlayın.',
    ),
    _OnboardingPage(
      icon: Icons.inventory_2_rounded,
      iconColor: Color(0xFFD97706),
      bgColor: Color(0xFFFFFBEB),
      title: 'Sipariş Havuzu',
      description:
          'Harita ekranındaki "Havuz" butonundan müsait siparişlere bakabilirsiniz. Uygun gördüğünüz siparişi üzerinize alabilirsiniz.',
    ),
    _OnboardingPage(
      icon: Icons.payments_rounded,
      iconColor: Color(0xFF0891B2),
      bgColor: Color(0xFFECFEFF),
      title: 'Ödeme ve Vardiya',
      description:
          'Nakit ödemelerde tutarı doğrulayın. Vardiya başlatmadan sipariş alamazsınız. Günlük kazancınızı ve geçmiş siparişlerinizi raporlar bölümünden takip edin.',
    ),
    _OnboardingPage(
      icon: Icons.location_on_rounded,
      iconColor: Color(0xFFDC2626),
      bgColor: Color(0xFFFEF2F2),
      title: 'Konum İzni Gerekli',
      description:
          'ZirveGo, siparişlerinizi haritada göstermek, müşteriye olan mesafeyi hesaplamak ve vardiya süresince konumunuzu yöneticilerinizle paylaşmak için arka planda konum erişimi kullanır.\n\nKonum izni vermeden uygulama düzgün çalışmaz.',
      badge: 'Neden gerekli?',
      badgeColor: Color(0xFFDC2626),
      bullets: [
        _Bullet(Icons.map_rounded, 'Haritada sipariş konumlarını görmek için'),
        _Bullet(Icons.social_distance_rounded, 'Müşteriye mesafe hesaplamak için'),
        _Bullet(Icons.supervisor_account_rounded, 'Yöneticinizin sizi takip edebilmesi için'),
      ],
    ),
    _OnboardingPage(
      icon: Icons.check_circle_rounded,
      iconColor: Color(0xFF2563EB),
      bgColor: Color(0xFFEFF6FF),
      title: 'Başlamaya Hazırsınız!',
      description:
          'Tüm adımları öğrendiniz. Şimdi giriş yaparak siparişleri yönetmeye başlayabilirsiniz.',
    ),
  ];

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_shown', true);
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Atla butonu
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text(
                    'Atla',
                    style: TextStyle(color: _kTextMuted, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),

            // Sayfa içeriği
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _PageContent(page: _pages[i]),
              ),
            ),

            // Nokta göstergesi + buton
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _currentPage ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _currentPage ? _kPrimary : const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // İleri / Başla butonu
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: _kPrimary.withOpacity(0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _next,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLast ? 'Başla' : 'İleri',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isLast ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet {
  final IconData icon;
  final String text;
  const _Bullet(this.icon, this.text);
}

class _OnboardingPage {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String description;
  final String? badge;
  final Color? badgeColor;
  final List<_Bullet> bullets;

  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.description,
    this.badge,
    this.badgeColor,
    this.bullets = const [],
  });
}

class _PageContent extends StatelessWidget {
  final _OnboardingPage page;

  const _PageContent({required this.page});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 16),

          // İkon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: page.bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 60, color: page.iconColor),
          ),
          const SizedBox(height: 28),

          // Badge (opsiyonel)
          if (page.badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: (page.badgeColor ?? _kPrimary).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: page.badgeColor ?? _kPrimary),
                  const SizedBox(width: 5),
                  Text(
                    page.badge!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: page.badgeColor ?? _kPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Başlık
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _kTextPrimary,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),

          // Açıklama
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: _kTextMuted,
              height: 1.6,
            ),
          ),

          // Bullet listesi (opsiyonel)
          if (page.bullets.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: page.bgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (page.badgeColor ?? _kPrimary).withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: page.bullets.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (page.badgeColor ?? _kPrimary).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(b.icon,
                            size: 16, color: page.badgeColor ?? _kPrimary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            b.text,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _kTextPrimary,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
