import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';

/// Kurye Başvuru Ekranı
class CourierApplicationScreen extends StatefulWidget {
  const CourierApplicationScreen({super.key});

  @override
  State<CourierApplicationScreen> createState() => _CourierApplicationScreenState();
}

class _CourierApplicationScreenState extends State<CourierApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Başvuruyu gönder
  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_passwordController.text != _passwordConfirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Şifreler eşleşmiyor!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Telefon numarası kontrolü (zaten kayıtlı mı?)
      final existingCourier = await FirebaseFirestore.instance
          .collection('t_courier')
          .where('s_phone', isEqualTo: _phoneController.text.trim())
          .limit(1)
          .get();

      if (existingCourier.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Bu telefon numarası zaten kayıtlı!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Başvuru kontrolü (beklemede olan başvuru var mı?)
      final existingApplication = await FirebaseFirestore.instance
          .collection('t_courier_applications')
          .where('phone', isEqualTo: _phoneController.text.trim())
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (existingApplication.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Bu telefon numarası ile zaten bir başvurunuz bekliyor!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Başvuruyu Firebase'e kaydet
      final applicationData = {
        'name': _nameController.text.trim(),
        'surname': _surnameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty 
            ? null 
            : _emailController.text.trim(),
        'password': _passwordController.text, // Şifre hash'lenmeli (backend'de)
        'address': _addressController.text.trim(),
        'notes': _notesController.text.trim().isEmpty 
            ? null 
            : _notesController.text.trim(),
        'status': 'pending', // pending, approved, rejected
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('t_courier_applications')
          .add(applicationData);

      print('✅ Kurye başvurusu kaydedildi: ${_phoneController.text}');

      if (mounted) {
        // Başarı mesajı göster
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 30),
                SizedBox(width: 10),
                Text('Başvuru Gönderildi'),
              ],
            ),
            content: const Text(
              'Kurye başvurunuz başarıyla alındı!\n\n'
              'Başvurunuz incelendikten sonra size bilgi verilecektir. '
              'Lütfen telefon ve e-posta adresinizi kontrol etmeyi unutmayın.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Dialog'u kapat
                  Navigator.of(context).pop(); // Login ekranına dön
                },
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('❌ Başvuru kaydetme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Kurye Başvurusu',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(0.1),
              Colors.blue.withOpacity(0.05),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Başlık
                  const Text(
                    'Kurye Başvuru Formu',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Lütfen aşağıdaki bilgileri eksiksiz doldurun',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),

                  // Ad
                  _buildTextField(
                    controller: _nameController,
                    label: 'Ad *',
                    hint: 'Adınızı girin',
                    icon: Icons.person_outline,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ad gereklidir';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 15),

                  // Soyad
                  _buildTextField(
                    controller: _surnameController,
                    label: 'Soyad *',
                    hint: 'Soyadınızı girin',
                    icon: Icons.person_outline,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Soyad gereklidir';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 15),

                  // Telefon
                  _buildTextField(
                    controller: _phoneController,
                    label: 'Telefon Numarası *',
                    hint: '05XX XXX XX XX',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Telefon numarası gereklidir';
                      }
                      if (value.trim().length < 10) {
                        return 'Geçerli bir telefon numarası girin';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 15),

                  // E-posta
                  _buildTextField(
                    controller: _emailController,
                    label: 'E-posta (Opsiyonel)',
                    hint: 'ornek@email.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Geçerli bir e-posta adresi girin';
                        }
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 15),

                  // Şifre
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Şifre *',
                    hint: 'En az 6 karakter',
                    icon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Şifre gereklidir';
                      }
                      if (value.length < 6) {
                        return 'Şifre en az 6 karakter olmalıdır';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 15),

                  // Şifre Tekrar
                  _buildTextField(
                    controller: _passwordConfirmController,
                    label: 'Şifre Tekrar *',
                    hint: 'Şifrenizi tekrar girin',
                    icon: Icons.lock_outline,
                    obscureText: _obscurePasswordConfirm,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePasswordConfirm ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscurePasswordConfirm = !_obscurePasswordConfirm);
                      },
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Şifre tekrar gereklidir';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 15),

                  // Adres
                  _buildTextField(
                    controller: _addressController,
                    label: 'Adres *',
                    hint: 'Adresinizi girin',
                    icon: Icons.location_on_outlined,
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Adres gereklidir';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 15),

                  // Notlar
                  _buildTextField(
                    controller: _notesController,
                    label: 'Ek Notlar (Opsiyonel)',
                    hint: 'Eklemek istediğiniz bilgiler...',
                    icon: Icons.note_outlined,
                    maxLines: 3,
                  ),

                  const SizedBox(height: 30),

                  // Gönder Butonu
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitApplication,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send, color: Colors.white),
                                SizedBox(width: 10),
                                Text(
                                  'Başvuruyu Gönder',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Bilgilendirme
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Başvurunuz incelendikten sonra size bilgi verilecektir.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.blue),
          suffixIcon: suffixIcon,
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(15),
        ),
        validator: validator,
      ),
    );
  }
}
