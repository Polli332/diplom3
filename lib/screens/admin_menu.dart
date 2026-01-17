import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../global_config.dart';

class AdminMenu extends StatefulWidget {
  const AdminMenu({super.key});

  @override
  State<AdminMenu> createState() => _AdminMenuState();
}

class _AdminMenuState extends State<AdminMenu> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  // Данные для каждой вкладки
  List<Applicant> applicants = [];
  List<Manager> managers = [];
  List<Mechanic> mechanics = [];
  List<Service> services = [];
  List<Request> requests = [];
  List<Transport> transports = [];

   // Для хранения выбранных сервисов
  Service? _selectedManagerService;
  Service? _selectedMechanicService;

  // Контроллеры для форм
  final TextEditingController _serviceAddressController = TextEditingController();
  final TextEditingController _serviceWorkTimeController = TextEditingController();
  
  // Контроллеры для редактирования сервиса
  final TextEditingController _editServiceAddressController = TextEditingController();
  final TextEditingController _editServiceWorkTimeController = TextEditingController();
  
  final TextEditingController _managerNameController = TextEditingController();
  final TextEditingController _managerEmailController = TextEditingController();
  final TextEditingController _managerPasswordController = TextEditingController();
  final TextEditingController _managerServiceIdController = TextEditingController();
  
  final TextEditingController _mechanicNameController = TextEditingController();
  final TextEditingController _mechanicEmailController = TextEditingController();
  final TextEditingController _mechanicPasswordController = TextEditingController();
  final TextEditingController _mechanicServiceIdController = TextEditingController();

  // Настройки администратора
  final TextEditingController _adminEmailController = TextEditingController();
  final TextEditingController _adminPasswordController = TextEditingController();
  final TextEditingController _serverUrlController = TextEditingController();

  @override
void initState() {
  super.initState();
  _tabController = TabController(length: 6, vsync: this);
  _loadSavedServerUrl();
  _loadAllData();
  _loadAdminSettings();
  
  // Добавьте слушатель для переключения вкладок
  _tabController.addListener(() {
    if (_tabController.index == 1) { // Вкладка менеджеров
      _loadManagers();
    } else if (_tabController.index == 2) { // Вкладка механиков
      _loadMechanics();
    }
  });
}

Future<void> _loadSavedServerUrl() async {
  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('server_url');
  if (savedUrl != null && savedUrl.isNotEmpty) {
    GlobalConfig.updateServerUrl(savedUrl);
  }
  // Обновляем контроллер в UI
  _serverUrlController.text = GlobalConfig.serverUrl;
}

  @override
  void dispose() {
    _tabController.dispose();
    _serviceAddressController.dispose();
    _serviceWorkTimeController.dispose();
    _editServiceAddressController.dispose();
    _editServiceWorkTimeController.dispose();
    _managerNameController.dispose();
    _managerEmailController.dispose();
    _managerPasswordController.dispose();
    _managerServiceIdController.dispose();
    _mechanicNameController.dispose();
    _mechanicEmailController.dispose();
    _mechanicPasswordController.dispose();
    _mechanicServiceIdController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  // Загрузка всех данных
  Future<void> _loadAllData() async {
  setState(() => _isLoading = true);
  try {
    await Future.wait([
      _loadApplicants(),
      _loadManagers(),
      _loadMechanics(),
      _loadServices(),
      _loadRequests(),
      _loadTransports(),
    ]);
  } catch (e) {
    _showError('Ошибка загрузки данных: $e');
  } finally {
    setState(() => _isLoading = false);
  }
}

  Future<void> _loadAdminSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _adminEmailController.text = prefs.getString('admin_email') ?? 'admin@admin.com';
    _adminPasswordController.text = prefs.getString('admin_password') ?? 'admin123';
  }

  Future<void> _saveAdminSettings() async {
    final newUrl = _serverUrlController.text.trim();
    
    if (newUrl.isEmpty) {
      _showError('Введите URL сервера');
      return;
    }

    try {
      // Обновляем URL в GlobalConfig
      GlobalConfig.updateServerUrl(newUrl);
      
      // Сохраняем настройки в SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_email', _adminEmailController.text.trim());
      await prefs.setString('admin_password', _adminPasswordController.text.trim());
      await prefs.setString('server_url', newUrl);
      
      _showSuccess('Настройки сохранены');
      
      // Опционально: перезагрузить данные с нового сервера
      await _loadAllData();
      
    } catch (e) {
      _showError('Ошибка сохранения настроек: $e');
    }
  }

  Future<void> _loadApplicants() async {
    try {
      final response = await http.get(Uri.parse('${GlobalConfig.serverUrl}/applicants'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          applicants = data.map((item) => Applicant.fromJson(item)).toList();
        });
      }
    } catch (e) {
      print('Error loading applicants: $e');
    }
  }

  Future<void> _loadManagers() async {
    try {
      final response = await http.get(Uri.parse('${GlobalConfig.serverUrl}/managers'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          managers = data.map((item) => Manager.fromJson(item)).toList();
        });
      }
    } catch (e) {
      print('Error loading managers: $e');
    }
  }

  Future<void> _loadMechanics() async {
    try {
      final response = await http.get(Uri.parse('${GlobalConfig.serverUrl}/mechanics'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          mechanics = data.map((item) => Mechanic.fromJson(item)).toList();
        });
      }
    } catch (e) {
      print('Error loading mechanics: $e');
    }
  }

  Future<void> _loadServices() async {
    try {
      final response = await http.get(Uri.parse('${GlobalConfig.serverUrl}/services-with-details'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          services = data.map((item) => Service.fromJson(item)).toList();
        });
      }
    } catch (e) {
      print('Error loading services: $e');
    }
  }

  Future<void> _loadRequests() async {
    try {
      final response = await http.get(Uri.parse('${GlobalConfig.serverUrl}/requests'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          requests = data.map((item) => Request.fromJson(item)).toList();
        });
      }
    } catch (e) {
      print('Error loading requests: $e');
    }
  }

  Future<void> _loadTransports() async {
    try {
      final response = await http.get(Uri.parse('${GlobalConfig.serverUrl}/transports'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          transports = data.map((item) => Transport.fromJson(item)).toList();
        });
      }
    } catch (e) {
      print('Error loading transports: $e');
    }
  }

  // Создание сервиса
  Future<void> _createService() async {
    if (_serviceAddressController.text.trim().isEmpty) {
      _showError('Введите адрес сервиса');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${GlobalConfig.serverUrl}/services'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'address': _serviceAddressController.text.trim(),
          'workTime': _serviceWorkTimeController.text.trim(),
        }),
      );

      print('Create service response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        _serviceAddressController.clear();
        _serviceWorkTimeController.clear();
        await _loadServices();
        _showSuccess('Сервис создан');
      } else {
        _showError('Ошибка создания сервиса: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _showError('Ошибка создания сервиса: $e');
    }
  }

  // Редактирование сервиса
  Future<void> _editService(Service service) async {
    _editServiceAddressController.text = service.address;
    _editServiceWorkTimeController.text = service.workTime;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать сервис'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _editServiceAddressController,
                decoration: const InputDecoration(
                  labelText: 'Адрес',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _editServiceWorkTimeController,
                decoration: const InputDecoration(
                  labelText: 'Время работы',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _updateService(service.id);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  // Обновление сервиса
  Future<void> _updateService(int serviceId) async {
    if (_editServiceAddressController.text.trim().isEmpty) {
      _showError('Введите адрес сервиса');
      return;
    }

    try {
      final response = await http.put(
        Uri.parse('${GlobalConfig.serverUrl}/services/$serviceId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'address': _editServiceAddressController.text.trim(),
          'workTime': _editServiceWorkTimeController.text.trim(),
        }),
      );

      print('Update service response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        _editServiceAddressController.clear();
        _editServiceWorkTimeController.clear();
        await _loadServices();
        _showSuccess('Сервис обновлен');
      } else {
        _showError('Ошибка обновления сервиса: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _showError('Ошибка обновления сервиса: $e');
    }
  }

  // Удаление сервиса
  // Упрощенная функция удаления сервиса (с использованием каскадного эндпоинта)
Future<void> _deleteServiceSimple(int id) async {
  final confirmed = await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Удалить сервис'),
      content: const Text('Вы уверены, что хотите удалить этот сервис? Будут удалены все связанные заявки, механики и менеджеры этого сервиса.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          child: const Text('Удалить все'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  try {
    final response = await http.delete(Uri.parse('${GlobalConfig.serverUrl}/services/$id/cascade'));
    
    print('Cascade delete response: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      await _loadAllData();
      _showSuccess('Сервис и все связанные данные успешно удалены');
    } else {
      try {
        final errorData = json.decode(response.body);
        _showError('Ошибка удаления сервиса: ${errorData['error'] ?? response.body}');
      } catch (e) {
        _showError('Ошибка удаления сервиса: ${response.statusCode} - ${response.body}');
      }
    }
  } catch (e) {
    print('Exception deleting service: $e');
    _showError('Ошибка удаления сервиса: $e');
  }
}

 // Создание менеджера с выпадающим списком
Future<void> _createManager() async {
  if (_managerNameController.text.trim().isEmpty || 
      _managerEmailController.text.trim().isEmpty ||
      _managerPasswordController.text.trim().isEmpty) {
    _showError('Заполните все обязательные поля');
    return;
  }

  try {
    final Map<String, dynamic> requestData = {
      'name': _managerNameController.text.trim(),
      'email': _managerEmailController.text.trim(),
      'password': _managerPasswordController.text.trim(),
      'role': 'manager',
    };

    // Добавляем serviceId только если выбран сервис
    if (_selectedManagerService != null) {
      requestData['serviceId'] = _selectedManagerService!.id;
    }

    print('Отправка данных менеджера: $requestData');

    final response = await http.post(
      Uri.parse('${GlobalConfig.serverUrl}/managers'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(requestData),
    );

    print('Create manager response: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      _managerNameController.clear();
      _managerEmailController.clear();
      _managerPasswordController.clear();
      setState(() {
        _selectedManagerService = null;
      });
      await _loadManagers();
      _showSuccess('Менеджер создан');
    } else {
      try {
        final errorData = json.decode(response.body);
        _showError('Ошибка создания менеджера: ${errorData['error'] ?? response.body}');
      } catch (e) {
        _showError('Ошибка создания менеджера: ${response.statusCode} - ${response.body}');
      }
    }
  } catch (e) {
    print('Exception creating manager: $e');
    _showError('Ошибка создания менеджера: $e');
  }
}

  // Редактирование менеджера
  Future<void> _editManager(Manager manager) async {
    final nameController = TextEditingController(text: manager.name);
    final emailController = TextEditingController(text: manager.email);
    final passwordController = TextEditingController();
    final serviceIdController = TextEditingController(
      text: manager.serviceId?.toString() ?? ''
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать менеджера'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Имя',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Новый пароль (оставьте пустым, чтобы не менять)',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: serviceIdController,
                decoration: const InputDecoration(
                  labelText: 'ID сервиса (необязательно)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _updateManager(manager.id, nameController.text.trim(),
                  emailController.text.trim(), passwordController.text.trim(),
                  serviceIdController.text.trim());
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  // Обновление менеджера
  Future<void> _updateManager(int id, String name, String email, String password, String serviceId) async {
    try {
      final Map<String, dynamic> requestData = {
        'name': name,
        'email': email,
      };

      if (password.isNotEmpty) {
        requestData['password'] = password;
      }

      if (serviceId.isNotEmpty) {
        requestData['serviceId'] = int.parse(serviceId);
      } else {
        requestData['serviceId'] = null;
      }

      final response = await http.put(
        Uri.parse('${GlobalConfig.serverUrl}/managers/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      );

      print('Update manager response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        await _loadManagers();
        _showSuccess('Менеджер обновлен');
      } else {
        _showError('Ошибка обновления менеджера: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _showError('Ошибка обновления менеджера: $e');
    }
  }

  // Удаление менеджера
  Future<void> _deleteManager(int id) async {
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить менеджера'),
        content: const Text('Вы уверены, что хотите удалить этого менеджера?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.delete(Uri.parse('${GlobalConfig.serverUrl}/managers/$id'));
      
      print('Delete manager response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        await _loadManagers();
        _showSuccess('Менеджер удален');
      } else {
        _showError('Ошибка удаления менеджера: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _showError('Ошибка удаления менеджера: $e');
    }
  }

  // Создание механика
  Future<void> _createMechanic() async {
  if (_mechanicNameController.text.trim().isEmpty || 
      _mechanicEmailController.text.trim().isEmpty ||
      _mechanicPasswordController.text.trim().isEmpty ||
      _selectedMechanicService == null) {
    _showError('Заполните все обязательные поля');
    return;
  }

  try {
    final Map<String, dynamic> requestData = {
      'name': _mechanicNameController.text.trim(),
      'email': _mechanicEmailController.text.trim(),
      'password': _mechanicPasswordController.text.trim(),
      'role': 'mechanic',
      'serviceId': _selectedMechanicService!.id,
    };

    print('Отправка данных механика: $requestData');

    final response = await http.post(
      Uri.parse('${GlobalConfig.serverUrl}/mechanics'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(requestData),
    );

    print('Create mechanic response: ${response.statusCode}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      _mechanicNameController.clear();
      _mechanicEmailController.clear();
      _mechanicPasswordController.clear();
      setState(() {
        _selectedMechanicService = null;
      });
      await _loadMechanics();
      _showSuccess('Механик создан');
    } else {
      try {
        final errorData = json.decode(response.body);
        _showError('Ошибка создания механика: ${errorData['error'] ?? response.body}');
      } catch (e) {
        _showError('Ошибка создания механика: ${response.statusCode} - ${response.body}');
      }
    }
  } catch (e) {
    print('Exception creating mechanic: $e');
    _showError('Ошибка создания механика: $e');
  }
}

  // Редактирование механика
  Future<void> _editMechanic(Mechanic mechanic) async {
    final nameController = TextEditingController(text: mechanic.name);
    final emailController = TextEditingController(text: mechanic.email);
    final passwordController = TextEditingController();
    final serviceIdController = TextEditingController(
      text: mechanic.serviceId.toString()
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать механика'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Имя',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Новый пароль (оставьте пустым, чтобы не менять)',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: serviceIdController,
                decoration: const InputDecoration(
                  labelText: 'ID сервиса (обязательно)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _updateMechanic(mechanic.id, nameController.text.trim(),
                  emailController.text.trim(), passwordController.text.trim(),
                  serviceIdController.text.trim());
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  // Обновление механика
  Future<void> _updateMechanic(int id, String name, String email, String password, String serviceId) async {
    if (serviceId.isEmpty) {
      _showError('ID сервиса обязателен для механика');
      return;
    }

    try {
      final Map<String, dynamic> requestData = {
        'name': name,
        'email': email,
        'serviceId': int.parse(serviceId),
      };

      if (password.isNotEmpty) {
        requestData['password'] = password;
      }

      final response = await http.put(
        Uri.parse('${GlobalConfig.serverUrl}/mechanics/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      );

      print('Update mechanic response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        await _loadMechanics();
        _showSuccess('Механик обновлен');
      } else {
        _showError('Ошибка обновления механика: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _showError('Ошибка обновления механика: $e');
    }
  }

  // Удаление механика
  Future<void> _deleteMechanic(int id) async {
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить механика'),
        content: const Text('Вы уверены, что хотите удалить этого механика?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.delete(Uri.parse('${GlobalConfig.serverUrl}/mechanics/$id'));
      
      print('Delete mechanic response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        await _loadMechanics();
        _showSuccess('Механик удален');
      } else {
        _showError('Ошибка удаления механика: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _showError('Ошибка удаления механика: $e');
    }
  }

  // Удаление заявителя
  Future<void> _deleteApplicant(int id) async {
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить заявителя'),
        content: const Text('Вы уверены, что хотите удалить этого заявителя? Все его заявки также будут удалены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.delete(Uri.parse('${GlobalConfig.serverUrl}/applicants/$id'));
      
      print('Delete applicant response: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        await _loadApplicants();
        _showSuccess('Заявитель удален');
      } else {
        final errorData = json.decode(response.body);
        _showError('Ошибка удаления заявителя: ${errorData['error'] ?? response.body}');
      }
    } catch (e) {
      _showError('Ошибка удаления заявителя: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  // Вкладка заявителей
  Widget _buildApplicantsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Text(
                'Все заявители',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadApplicants,
                tooltip: 'Обновить',
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : applicants.isEmpty
                  ? const Center(child: Text('Заявителей нет'))
                  : ListView.builder(
                      itemCount: applicants.length,
                      itemBuilder: (context, index) {
                        final applicant = applicants[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.person, color: Colors.blue),
                            title: Text(applicant.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Email: ${applicant.email}'),
                                Text('Роль: ${applicant.role}'),
                                //Text('Заявок: ${applicant.requests?.length ?? 0}'),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteApplicant(applicant.id),
                            ),
                            onTap: () {
                              _showApplicantDetails(applicant);
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _showApplicantDetails(Applicant applicant) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Детали заявителя'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Имя: ${applicant.name}'),
              Text('Email: ${applicant.email}'),
              Text('Роль: ${applicant.role}'),
              const SizedBox(height: 16),
              /*const Text('Заявки:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...(applicant.requests ?? []).take(5).map((request) => 
                ListTile(
                  title: Text(request['problem'] ?? 'Описание не указано'),
                  subtitle: Text('Статус: ${request['status'] ?? 'неизвестно'}'),
                  dense: true,
                )
              ).toList(),
              if ((applicant.requests?.length ?? 0) > 5)
                const Text('... и другие заявки'),*/
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  // Вкладка менеджеров
  // Вкладка менеджеров
Widget _buildManagersTab() {
  // Фильтруем сервисы без менеджеров
  final servicesWithoutManager = services.where((service) => service.manager == null).toList();
  
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Добавить менеджера',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Информация о доступных сервисах
            if (servicesWithoutManager.isNotEmpty) ...[
              Text('Доступные сервисы без менеджеров: ${servicesWithoutManager.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              const SizedBox(height: 8),
            ],
            
            TextField(
              controller: _managerNameController,
              decoration: const InputDecoration(
                labelText: 'Имя*',
                border: OutlineInputBorder(),
                hintText: 'Введите имя менеджера',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _managerEmailController,
              decoration: const InputDecoration(
                labelText: 'Email*',
                border: OutlineInputBorder(),
                hintText: 'Введите email менеджера',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _managerPasswordController,
              decoration: const InputDecoration(
                labelText: 'Пароль*',
                border: OutlineInputBorder(),
                hintText: 'Введите пароль',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            
            // Выпадающий список для выбора сервиса
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: DropdownButton<Service>(
                  isExpanded: true,
                  value: _selectedManagerService,
                  hint: const Text('Выберите сервис (необязательно)'),
                  underline: const SizedBox(),
                  items: [
                    const DropdownMenuItem<Service>(
                      value: null,
                      child: Text('Без сервиса'),
                    ),
                    ...servicesWithoutManager.map((service) {
                      return DropdownMenuItem<Service>(
                        value: service,
                        child: Text('${service.id}: ${service.address}'),
                      );
                    }).toList(),
                  ],
                  onChanged: (Service? newValue) {
                    setState(() {
                      _selectedManagerService = newValue;
                    });
                  },
                ),
              ),
            ),
            
            // Информация о выбранном сервисе
            if (_selectedManagerService != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Выбранный сервис:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('ID: ${_selectedManagerService!.id}'),
                      Text('Адрес: ${_selectedManagerService!.address}'),
                      Text('Время работы: ${_selectedManagerService!.workTime}'),
                    ],
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _createManager,
              child: const Text('Создать менеджера'),
            ),
          ],
        ),
      ),
      const Divider(),
      
      // Список менеджеров
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : managers.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text(
                        'Менеджеров нет',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: managers.length,
                    itemBuilder: (context, index) {
                      final manager = managers[index];
                      Service? service;
                      if (manager.serviceId != null) {
                        try {
                          service = services.firstWhere(
                            (s) => s.id == manager.serviceId,
                            orElse: () => Service(id: 0, address: 'Не назначен', workTime: ''),
                          );
                        } catch (e) {
                          service = Service(id: 0, address: 'Не назначен', workTime: '');
                        }
                      }
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: const Icon(Icons.manage_accounts, color: Colors.purple),
                          title: Text(
                            manager.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('Email: ${manager.email}'),
                              const SizedBox(height: 4),
                              Text('Сервис: ${service?.address ?? 'Не назначен'}'),
                              if (manager.serviceId != null)
                                Text('ID сервиса: ${manager.serviceId}'),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _editManager(manager),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteManager(manager.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    ],
  );
}

  // Вкладка механиков
  // Вкладка механиков
Widget _buildMechanicsTab() {
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Добавить механика',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Информация о доступных сервисах
            if (services.isNotEmpty) ...[
              Text('Всего сервисов: ${services.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
              ),
              const SizedBox(height: 8),
            ],
            
            TextField(
              controller: _mechanicNameController,
              decoration: const InputDecoration(
                labelText: 'Имя*',
                border: OutlineInputBorder(),
                hintText: 'Введите имя механика',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mechanicEmailController,
              decoration: const InputDecoration(
                labelText: 'Email*',
                border: OutlineInputBorder(),
                hintText: 'Введите email механика',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mechanicPasswordController,
              decoration: const InputDecoration(
                labelText: 'Пароль*',
                border: OutlineInputBorder(),
                hintText: 'Введите пароль',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            
            // Выпадающий список для выбора сервиса
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: DropdownButton<Service>(
                  isExpanded: true,
                  value: _selectedMechanicService,
                  hint: const Text('Выберите сервис*'),
                  underline: const SizedBox(),
                  items: [
                    const DropdownMenuItem<Service>(
                      value: null,
                      child: Text('Выберите сервис'),
                    ),
                    ...services.map((service) {
                      String managerInfo = '';
                      if (service.manager != null) {
                        managerInfo = ' (Менеджер: ${service.manager!.name})';
                      }
                      return DropdownMenuItem<Service>(
                        value: service,
                        child: Text('${service.id}: ${service.address}$managerInfo'),
                      );
                    }).toList(),
                  ],
                  onChanged: (Service? newValue) {
                    setState(() {
                      _selectedMechanicService = newValue;
                    });
                  },
                ),
              ),
            ),
            
            // Информация о выбранном сервисе
            if (_selectedMechanicService != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Выбранный сервис:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('ID: ${_selectedMechanicService!.id}'),
                      Text('Адрес: ${_selectedMechanicService!.address}'),
                      Text('Время работы: ${_selectedMechanicService!.workTime}'),
                      if (_selectedMechanicService!.manager != null)
                        Text('Менеджер: ${_selectedMechanicService!.manager!.name}'),
                      if (_selectedMechanicService!.mechanics != null)
                        Text('Механиков: ${_selectedMechanicService!.mechanics!.length}'),
                    ],
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _createMechanic,
              child: const Text('Создать механика'),
            ),
          ],
        ),
      ),
      const Divider(),
      
      
      // Список механиков
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : mechanics.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text(
                        'Механиков нет',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: mechanics.length,
                    itemBuilder: (context, index) {
                      final mechanic = mechanics[index];
                      Service? service;
                      if (mechanic.serviceId != 0) {
                        try {
                          service = services.firstWhere(
                            (s) => s.id == mechanic.serviceId,
                            orElse: () => Service(id: 0, address: 'Не назначен', workTime: ''),
                          );
                        } catch (e) {
                          service = Service(id: 0, address: 'Не назначен', workTime: '');
                        }
                      }
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: const Icon(Icons.engineering, color: Colors.orange),
                          title: Text(
                            mechanic.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('Email: ${mechanic.email}'),
                              const SizedBox(height: 4),
                              Text('Сервис: ${service?.address ?? 'Не назначен'}'),
                              if (mechanic.serviceId != 0)
                                Text('ID сервиса: ${mechanic.serviceId}'),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _editMechanic(mechanic),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteMechanic(mechanic.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    ],
  );
}

  // Вкладка сервисов
  Widget _buildServicesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Добавить сервис',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _serviceAddressController,
                decoration: const InputDecoration(
                  labelText: 'Адрес',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _serviceWorkTimeController,
                decoration: const InputDecoration(
                  labelText: 'Время работы',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _createService,
                child: const Text('Создать сервис'),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : services.isEmpty
                  ? const Center(child: Text('Сервисов нет'))
                  : ListView.builder(
                      itemCount: services.length,
                      itemBuilder: (context, index) {
                        final service = services[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.business, color: Colors.green),
                            title: Text(service.address),
                            subtitle: Text(service.workTime),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _editService(service),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteServiceSimple(service.id),
                                ),
                              ],
                            ),
                            onTap: () {
                              _showServiceDetails(service);
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // Обновите функцию _loadAllData или добавьте эту функцию
Future<void> _loadServicesAndResetSelection() async {
  await _loadServices();
  
  // Сбросить выбранные сервисы при обновлении данных
  if (_selectedManagerService != null) {
    final currentService = services.firstWhere(
      (s) => s.id == _selectedManagerService!.id,
      orElse: () => Service(id: 0, address: '', workTime: ''),
    );
    if (currentService.id == 0) {
      setState(() {
        _selectedManagerService = null;
      });
    }
  }
  
  if (_selectedMechanicService != null) {
    final currentService = services.firstWhere(
      (s) => s.id == _selectedMechanicService!.id,
      orElse: () => Service(id: 0, address: '', workTime: ''),
    );
    if (currentService.id == 0) {
      setState(() {
        _selectedMechanicService = null;
      });
    }
  }
}

  void _showServiceDetails(Service service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Детали сервиса'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Адрес: ${service.address}'),
              Text('Время работы: ${service.workTime}'),
              const SizedBox(height: 16),
              if (service.manager != null)
                Text('Менеджер: ${service.manager!.name}'),
              if (service.mechanics != null && service.mechanics!.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Механики:'),
                    ...service.mechanics!.take(5).map((mechanic) => 
                      Text('  - ${mechanic.name}')
                    ).toList(),
                    if (service.mechanics!.length > 5)
                      const Text('  ... и другие'),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  // Вкладка заявок
  /*Widget _buildRequestsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Text(
                'Все заявки',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadRequests,
                tooltip: 'Обновить',
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : requests.isEmpty
                  ? const Center(child: Text('Заявок нет'))
                  : ListView.builder(
                      itemCount: requests.length,
                      itemBuilder: (context, index) {
                        final request = requests[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.list_alt, color: Colors.brown),
                            title: Text('Заявка #${request.id}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Проблема: ${request.problem}'),
                                Text('Статус: ${request.status}'),
                                Text('Дата: ${request.submittedAt.day}.${request.submittedAt.month}.${request.submittedAt.year}'),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.info, color: Colors.blue),
                              onPressed: () {
                                _showRequestDetails(request);
                              },
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }*/

  /*void _showRequestDetails(Request request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Детали заявки'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID: ${request.id}'),
              Text('Проблема: ${request.problem}'),
              Text('Статус: ${request.status}'),
              Text('Дата создания: ${request.submittedAt.day}.${request.submittedAt.month}.${request.submittedAt.year} ${request.submittedAt.hour}:${request.submittedAt.minute.toString().padLeft(2, '0')}'),
              if (request.closedAt != null)
                Text('Дата закрытия: ${request.closedAt!.day}.${request.closedAt!.month}.${request.closedAt!.year}'),
              Text('ID транспорта: ${request.transportId}'),
              Text('ID заявителя: ${request.applicantId}'),
              if (request.mechanicId != null)
                Text('ID механика: ${request.mechanicId}'),
              if (request.serviceId != null)
                Text('ID сервиса: ${request.serviceId}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }*/

  // Вкладка настроек
  Widget _buildSettingsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          const Text(
            'Настройки администратора',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _adminEmailController,
            decoration: const InputDecoration(
              labelText: 'Email администратора',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _adminPasswordController,
            decoration: const InputDecoration(
              labelText: 'Пароль администратора',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _serverUrlController,
            decoration: const InputDecoration(
              labelText: 'URL сервера',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _saveAdminSettings,
            child: const Text('Сохранить настройки'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _logout,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Выйти из аккаунта'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Панель администратора'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
            tooltip: 'Обновить все данные',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Заявители'),
            Tab(icon: Icon(Icons.manage_accounts), text: 'Менеджеры'),
            Tab(icon: Icon(Icons.engineering), text: 'Механики'),
            Tab(icon: Icon(Icons.business), text: 'Сервисы'),
            //Tab(icon: Icon(Icons.list_alt), text: 'Заявки'),
            Tab(icon: Icon(Icons.settings), text: 'Настройки'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildApplicantsTab(),
          _buildManagersTab(),
          _buildMechanicsTab(),
          _buildServicesTab(),
          //_buildRequestsTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }
}

// Модели данных
class Applicant {
  final int id;
  final String name;
  final String email;
  final String role;
  final List<dynamic>? requests;

  Applicant({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.requests,
  });

  factory Applicant.fromJson(Map<String, dynamic> json) {
    return Applicant(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Неизвестно',
      email: json['email'] ?? 'Неизвестно',
      role: json['role'] ?? 'applicant',
      requests: json['requests'] is List ? json['requests'] : null,
    );
  }
}

class Manager {
  final int id;
  final String name;
  final String email;
  final int? serviceId;
  final dynamic service;

  Manager({
    required this.id,
    required this.name,
    required this.email,
    this.serviceId,
    this.service,
  });

  factory Manager.fromJson(Map<String, dynamic> json) {
    return Manager(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Неизвестно',
      email: json['email'] ?? 'Неизвестно',
      serviceId: json['serviceId'],
      service: json['service'],
    );
  }
}

class Mechanic {
  final int id;
  final String name;
  final String email;
  final int serviceId;
  final dynamic service;

  Mechanic({
    required this.id,
    required this.name,
    required this.email,
    required this.serviceId,
    this.service,
  });

  factory Mechanic.fromJson(Map<String, dynamic> json) {
    return Mechanic(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Неизвестно',
      email: json['email'] ?? 'Неизвестно',
      serviceId: json['serviceId'] ?? 0,
      service: json['service'],
    );
  }
}

class Service {
  final int id;
  final String address;
  final String workTime;
  final Manager? manager;
  final List<Mechanic>? mechanics;

  Service({
    required this.id,
    required this.address,
    required this.workTime,
    this.manager,
    this.mechanics,
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    List<Mechanic>? mechanics;
    if (json['mechanics'] != null && json['mechanics'] is List) {
      mechanics = (json['mechanics'] as List).map((i) => Mechanic.fromJson(i)).toList();
    }

    Manager? manager;
    if (json['manager'] != null && json['manager'] is Map) {
      manager = Manager.fromJson(json['manager']);
    }

    return Service(
      id: json['id'] ?? 0,
      address: json['address'] ?? 'Адрес не указан',
      workTime: json['workTime'] ?? 'Время работы не указано',
      manager: manager,
      mechanics: mechanics,
    );
  }
}

class Request {
  final int id;
  final String problem;
  final DateTime submittedAt;
  final DateTime? closedAt;
  final String status;
  final int transportId;
  final int applicantId;
  final int? mechanicId;
  final int? serviceId;

  Request({
    required this.id,
    required this.problem,
    required this.submittedAt,
    this.closedAt,
    required this.status,
    required this.transportId,
    required this.applicantId,
    this.mechanicId,
    this.serviceId,
  });

  factory Request.fromJson(Map<String, dynamic> json) {
    return Request(
      id: json['id'] ?? 0,
      problem: json['problem'] ?? 'Описание не указано',
      submittedAt: DateTime.parse(json['submittedAt'] ?? DateTime.now().toIso8601String()),
      closedAt: json['closedAt'] != null ? DateTime.parse(json['closedAt']) : null,
      status: json['status'] ?? 'новая',
      transportId: json['transportId'] ?? 0,
      applicantId: json['applicantId'] ?? 0,
      mechanicId: json['mechanicId'],
      serviceId: json['serviceId'],
    );
  }
}

class Transport {
  final int id;
  final String type;
  final String serial;
  final String model;

  Transport({
    required this.id,
    required this.type,
    required this.serial,
    required this.model,
  });

  factory Transport.fromJson(Map<String, dynamic> json) {
    return Transport(
      id: json['id'] ?? 0,
      type: json['type'] ?? 'Неизвестно',
      serial: json['serial'] ?? 'Неизвестно',
      model: json['model'] ?? 'Неизвестно',
    );
  }
}