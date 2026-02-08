import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../models/user_model.dart';
import 'home_pages.dart';
import '../global_config.dart';
import 'admin_menu.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Определяем кастомный цвет
  static const Color primaryColor = Color(0xFFF5BC38);
  static const Color primaryColorDark = Color(0xFFD4A22F); // Немного темнее для hover эффектов
  
  final _formKey = GlobalKey<FormState>();
  bool isLogin = true;
  final TextEditingController emailCtl = TextEditingController();
  final TextEditingController passCtl = TextEditingController();
  final TextEditingController nameCtl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  // Данные администратора (хранятся локально)
  static const String adminEmail = 'admin@admin.com';
  static const String adminPassword = 'admin123';

  // Тестовые данные для быстрой проверки
  void _fillTestData() {
    if (isLogin) {
      emailCtl.text = 'applicant@test.com';
      passCtl.text = 'password';
    } else {
      nameCtl.text = 'Тестовый пользователь';
      emailCtl.text = 'test@test.com';
      passCtl.text = 'password';
    }
    _formKey.currentState?.validate();
  }

  // Проверка входа администратора
  bool _isAdminLogin() {
    final email = emailCtl.text.trim();
    final password = passCtl.text.trim();
    return email == adminEmail && password == adminPassword;
  }

  Future<void> _doLogin() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _loading = true);
    
    try {
      if (_isAdminLogin()) {
        print('🔐 Вход как администратор');
        
        // Сохраняем данные администратора
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', 0); 
        await prefs.setString('user_name', 'Администратор');
        await prefs.setString('user_email', adminEmail);
        await prefs.setString('user_role', 'admin');
        
        print('✅ Успешный вход как администратор');
        
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AdminMenu()),
            (route) => false,
          );
        }
        return;
      }
      
      // Обычный вход через сервер
      print('🔐 Вход пользователя: ${emailCtl.text}');
      final user = await ApiService.login(
        emailCtl.text.trim(), 
        passCtl.text.trim()
      );
      print('✅ Успешный вход: ${user.role}');
      await _saveAndNavigate(user);
    } catch (e) {
      print('❌ Ошибка входа: $e');
      _showError('Ошибка входа: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _doRegister() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _loading = true);
    try {
      print('🔐 Регистрация пользователя: ${emailCtl.text}');
      final user = await ApiService.registerApplicant(
        nameCtl.text.trim(), 
        emailCtl.text.trim(), 
        passCtl.text.trim()
      );
      print('✅ Успешная регистрация: ${user.role}');
      await _saveAndNavigate(user);
    } catch (e) {
      developer.log('❌ Ошибка регистрации: $e');
      _showError('Ошибка регистрации: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveAndNavigate(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('user_id', user.id);
      await prefs.setString('user_name', user.name);
      await prefs.setString('user_email', user.email);
      await prefs.setString('user_role', user.role);

      print('💾 Данные сохранены: ${user.name} (${user.role})');

      if (mounted) {
        _navigateByRole(user.role);
      }
    } catch (e) {
      print('❌ Ошибка сохранения: $e');
      if (mounted) {
        _showError('Ошибка сохранения данных: $e');
      }
    }
  }

  void _navigateByRole(String role) {
    print('🧭 Навигация для роли: $role');
    
    final normalizedRole = role.toLowerCase();
    print('🔧 Нормализованная роль: $normalizedRole');

    Widget page;
    switch (normalizedRole) {
      case 'manager':
        page = const ManagerHomePage();
        break;
      case 'mechanic':
        page = const MechanicHomePage();
        break;
      case 'applicant':
      default:
        page = const ClientHomePage();
        break;
    }

    print('🚀 Переход на: ${page.runtimeType}');
    
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => page),
      (route) => false,
    );
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      )
    );
  }

  void _showSuccess(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      )
    );
  }

  // Метод для очистки формы
  void _clearForm() {
    emailCtl.clear();
    passCtl.clear();
    nameCtl.clear();
    _formKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(isLogin ? 'Вход в систему' : 'Регистрация'),
        backgroundColor: primaryColor, // <-- ИЗМЕНЕНО ЗДЕСЬ
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: _loading
            ? _buildLoading()
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Заголовок с иконкой
                      const SizedBox(height: 20),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.1), // <-- ИЗМЕНЕНО ЗДЕСЬ
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isLogin ? Icons.login : Icons.person_add,
                          size: 40,
                          color: primaryColor, // <-- ИЗМЕНЕНО ЗДЕСЬ
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isLogin ? 'Вход в систему' : 'Создание аккаунта',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isLogin 
                            ? 'Введите ваши учетные данные' 
                            : 'Заполните форму для регистрации',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      // Поля формы
                      if (!isLogin) ...[
                        TextFormField(
                          controller: nameCtl,
                          decoration: const InputDecoration(
                            labelText: 'Полное имя',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (v) => v == null || v.trim().isEmpty 
                              ? 'Введите ваше имя' 
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      TextFormField(
                        controller: emailCtl,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Введите email';
                          }
                          if (!v.contains('@') || !v.contains('.')) {
                            return 'Введите корректный email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: passCtl,
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword 
                                  ? Icons.visibility_off 
                                  : Icons.visibility,
                              color: Colors.grey[600],
                            ),
                            onPressed: () => setState(() => 
                                _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        validator: (v) => v == null || v.length < 4 
                            ? 'Пароль должен быть не менее 4 символов' 
                            : null,
                      ),
                      const SizedBox(height: 30),

                      // Основная кнопка
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _loading 
                              ? null 
                              : (isLogin ? _doLogin : _doRegister),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor, // <-- ИЗМЕНЕНО ЗДЕСЬ
                            foregroundColor: const Color.fromARGB(255, 0, 0, 0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            isLogin ? 'Войти' : 'Зарегистрироваться',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Переключение между входом и регистрацией
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isLogin 
                                ? 'Нет аккаунта?' 
                                : 'Уже есть аккаунт?',
                            style: TextStyle(
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _loading 
                                ? null 
                                : () {
                                    setState(() {
                                      isLogin = !isLogin;
                                      _clearForm();
                                    });
                                  },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              isLogin ? 'Зарегистрируйтесь' : 'Войти',
                              style: TextStyle(
                                color: primaryColor, // <-- ИЗМЕНЕНО ЗДЕСЬ
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: primaryColor, // <-- ИЗМЕНЕНО ЗДЕСЬ (необязательно)
          ),
          const SizedBox(height: 20),
          Text(
            isLogin ? 'Выполняется вход...' : 'Регистрация...',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Пожалуйста, подождите',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    emailCtl.dispose();
    passCtl.dispose();
    nameCtl.dispose();
    super.dispose();
  }
}