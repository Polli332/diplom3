import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

// Объявляем базовый URL в начале файла
const String baseUrl = 'https://jvvrlmfl-3000.euw.devtunnels.ms'; // Замените на ваш публичный URL

class ManagerMenu extends StatefulWidget {
  const ManagerMenu({super.key});

  @override
  State<ManagerMenu> createState() => _ManagerMenuState();
}

class _ManagerMenuState extends State<ManagerMenu> with SingleTickerProviderStateMixin {
  String? userName;
  String? userEmail;
  int? userId;
  int? serviceId;
  String? userPhoto;
  String? serviceAddress;
  List<Request> requests = [];
  List<Mechanic> mechanics = [];
  List<Transport> transports = [];
  List<Applicant> applicants = [];
  List<Service> services = [];
  bool _isAccountPanelOpen = false;
  String _sortOrder = 'newest';
  String? _statusFilter;
  String? _mechanicFilter;
  String? _transportFilter;
  bool _isLoading = true;
  bool _photoLoading = false;

  late TabController _tabController;

  final Map<int, List<int>> _selectedMechanicsForRequest = {}; // requestId -> list of mechanicIds
  final Map<int, List<Mechanic>> _assignedMechanicsForRequest = {}; // requestId -> list of assigned mechanics
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _mechanicNameController = TextEditingController();
  final TextEditingController _mechanicEmailController = TextEditingController();
  final TextEditingController _mechanicPasswordController = TextEditingController();
  String? _selectedMechanicPhotoBase64;

  final List<String> _statusList = ['новая', 'принята', 'в работе', 'временно отклонена', 'завершена'];
  final List<String> _transportTypes = [
    'троллейбусы',
    'электробусы',
    'трамваи',
    'электрогрузовики'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _mechanicNameController.dispose();
    _mechanicEmailController.dispose();
    _mechanicPasswordController.dispose();
    super.dispose();
  }

  // НОВЫЙ МЕТОД: Загрузка назначенных механиков для заявки
  Future<void> _loadAssignedMechanicsForRequest(int requestId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/requests/$requestId/mechanics'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> mechanicsData = data['mechanics'];
        
        setState(() {
          _assignedMechanicsForRequest[requestId] = mechanicsData
              .map((m) => Mechanic.fromJson(m))
              .toList();
          
          // Также сохраняем ID выбранных механиков для диалога
          _selectedMechanicsForRequest[requestId] = mechanicsData
              .map((m) => m['id'] as int)
              .toList();
        });
      }
    } catch (e) {
      print('Ошибка загрузки назначенных механиков: $e');
    }
  }

  void _showAssignMechanicsDialog(Request request) async {
    // Загружаем текущих механиков заявки
    await _loadAssignedMechanicsForRequest(request.id);
    
    // Список ID выбранных механиков
    List<int> selectedMechanicIds = List.from(_selectedMechanicsForRequest[request.id] ?? []);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Назначить механиков'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Выберите механиков для этой заявки:'),
                    const SizedBox(height: 16),
                    
                    // Список механиков с чекбоксами
                    SizedBox(
                      height: 300,
                      child: ListView.builder(
                        itemCount: mechanics.length,
                        itemBuilder: (context, index) {
                          final mechanic = mechanics[index];
                          final isSelected = selectedMechanicIds.contains(mechanic.id);
                          
                          return CheckboxListTile(
                            title: Text(mechanic.name),
                            subtitle: Text(mechanic.email),
                            value: isSelected,
                            onChanged: (bool? value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedMechanicIds.add(mechanic.id);
                                } else {
                                  selectedMechanicIds.remove(mechanic.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    
                    // Информация о текущих назначенных механиках
                    if (_assignedMechanicsForRequest[request.id]?.isNotEmpty ?? false)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          const Text(
                            'Текущие механики:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          ..._assignedMechanicsForRequest[request.id]!.map((mechanic) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text('• ${mechanic.name}'),
                            );
                          }),
                        ],
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _assignMechanicsToRequest(request, selectedMechanicIds);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Назначить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _assignMechanicsToRequest(Request request, List<int> mechanicIds) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/requests/${request.id}/assign-mechanics'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'mechanicIds': mechanicIds,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Обновляем локальные данные
        setState(() {
          _selectedMechanicsForRequest[request.id] = mechanicIds;
          _assignedMechanicsForRequest[request.id] = mechanicIds
              .map((id) => mechanics.firstWhere((m) => m.id == id))
              .toList();
        });
        
        // Обновляем список заявок
        await _loadAllRequests();
        
        _showSuccess('${mechanicIds.length} механиков назначено на заявку');
      } else {
        _showError('Ошибка назначения механиков: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Ошибка назначения механиков: $e');
    }
  }

  // УПРОЩЕННЫЙ МЕТОД ЗАГРУЗКИ ФОТО С СЕРВЕРА
  Future<void> _loadUserPhoto() async {
    if (userId == null) return;
    
    setState(() {
      _photoLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user-data/manager/$userId'),
      );

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        
        if (userData['photo'] != null && userData['photo'].isNotEmpty) {
          final String photoBase64 = userData['photo'];
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_photo', photoBase64);
          
          setState(() {
            userPhoto = photoBase64;
          });
          return;
        }
      }

      _setDefaultPhoto();

    } catch (e) {
      print('Ошибка загрузки фото пользователя: $e');
      _setDefaultPhoto();
    } finally {
      setState(() {
        _photoLoading = false;
      });
    }
  }

  // Метод для установки фото по умолчанию
  void _setDefaultPhoto() {
    setState(() {
      userPhoto = null;
    });
  }

  // Метод для построения аватарки
  Widget _buildAvatar(String? photoBase64, double radius) {
    if (_photoLoading) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey[300],
        child: const CircularProgressIndicator(),
      );
    }

    if (photoBase64 != null && photoBase64.isNotEmpty) {
      try {
        if (photoBase64.length > 100) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: Colors.white,
            backgroundImage: MemoryImage(base64Decode(photoBase64)),
            onBackgroundImageError: (exception, stackTrace) {
              print('Ошибка загрузки изображения: $exception');
            },
          );
        }
      } catch (e) {
        print('Ошибка декодирования base64 изображения: $e');
      }
    }
    
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.blue,
      child: Icon(
        Icons.person,
        size: radius,
        color: Colors.white,
      ),
    );
  }

  // Обновленный метод для выбора фото
  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final base64Image = base64Encode(bytes);
        
        await _updateManagerPhoto(base64Image);
      }
    } catch (e) {
      _showError('Ошибка выбора фото: $e');
    }
  }

  // УЛУЧШЕННЫЙ МЕТОД ОБНОВЛЕНИЯ ФОТО
  Future<void> _updateManagerPhoto(String base64Image) async {
    setState(() {
      _photoLoading = true;
    });

    try {
      final response = await http.put(
        Uri.parse('$baseUrl/managers/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'photo': base64Image,
        }),
      );
      
      if (response.statusCode == 200) {
        setState(() {
          userPhoto = base64Image;
        });
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_photo', base64Image);
        
        _showSuccess('Фото профиля обновлено');
        
        await _loadUserPhoto();
      } else {
        _showError('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Ошибка обновления фото: $e');
    } finally {
      setState(() {
        _photoLoading = false;
      });
    }
  }

  // ДОБАВЛЕН МЕТОД ДЛЯ ВЫБОРА ФОТО МЕХАНИКА
  Future<void> _pickMechanicImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final base64Image = base64Encode(bytes);
        
        setState(() {
          _selectedMechanicPhotoBase64 = base64Image;
        });
        _showSuccess('Фото механика выбрано');
      }
    } catch (e) {
      _showError('Ошибка выбора фото механика: $e');
    }
  }

  // УЛУЧШЕННЫЙ МЕТОД ЗАГРУЗКИ ДАННЫХ
  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        userId = prefs.getInt('user_id');
        userName = prefs.getString('user_name') ?? 'Менеджер';
        userEmail = prefs.getString('user_email') ?? 'Email не указан';
        
        _nameController.text = userName!;
        _emailController.text = userEmail!;
      });

      if (userId != null) {
        await _loadUserPhoto();
        await _loadManagerService();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Ошибка загрузки данных пользователя: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadManagerService() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/managers/$userId'));
      
      if (response.statusCode == 200) {
        final managerData = json.decode(response.body);
        setState(() {
          serviceId = managerData['serviceId'];
        });
        
        await _loadServiceDetails();
        await _loadAllData();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Ошибка загрузки данных менеджера: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadServiceDetails() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/services/$serviceId'));
      if (response.statusCode == 200) {
        final serviceData = json.decode(response.body);
        setState(() {
          serviceAddress = serviceData['address'] ?? 'Адрес не указан';
        });
      }
    } catch (e) {
      print('Ошибка загрузки деталей сервиса: $e');
      setState(() {
        serviceAddress = 'Адрес не указан';
      });
    }
  }

  // ОБНОВЛЕННЫЙ МЕТОД ЗАГРУЗКИ ДАННЫХ
  Future<void> _loadAllData() async {
    try {
      await Future.wait([
        _loadAllRequests(),
        _loadServiceMechanics(),
        _loadTransports(),
        _loadApplicants(),
        _loadServices(),
      ]);
      
      // Загружаем назначенных механиков для каждой заявки
      for (var request in requests) {
        await _loadAssignedMechanicsForRequest(request.id);
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      print('Ошибка загрузки всех данных: $e');
      setState(() => _isLoading = false);
    }
  }

  // ИЗМЕНЕН МЕТОД ЗАГРУЗКИ ЗАЯВОК - ЗАГРУЖАЕМ ВСЕ ЗАЯВКИ
  Future<void> _loadAllRequests() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/requests'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          requests = data.map((item) => Request.fromJson(item)).toList();
          // НЕ фильтруем по serviceId - показываем все заявки
        });
      }
    } catch (e) {
      print('Error loading requests: $e');
    }
  }

  Future<void> _loadServiceMechanics() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/mechanics'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        List<Mechanic> allMechanics = data.map((item) => Mechanic.fromJson(item)).toList();
        
        // Фильтруем механиков по serviceId только если serviceId не null
        setState(() {
          if (serviceId != null) {
            mechanics = allMechanics.where((mechanic) => mechanic.serviceId == serviceId).toList();
          } else {
            mechanics = allMechanics;
          }
        });
      }
    } catch (e) {
      print('Error loading mechanics: $e');
    }
  }

  Future<void> _loadTransports() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/transports'));
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

  Future<void> _loadApplicants() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/applicants'));
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

  Future<void> _loadServices() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/services'));
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

  // ДОБАВЛЕН МЕТОД ДЛЯ ПОКАЗА СТАТИСТИКИ НА ВЕСЬ ЭКРАН
  void _openStatisticsScreen() {
    // Закрываем панель профиля
    setState(() {
      _isAccountPanelOpen = false;
    });
    
    // Открываем статистику на весь экран
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StatisticsScreen(
          requests: requests,
        ),
      ),
    );
  }

  // НОВЫЙ МЕТОД ДЛЯ ПОКАЗА ДЕТАЛЕЙ ЗАЯВКИ ВО ВЕСЬ ЭКРАН (как у заявителя)
  void _showRequestDetails(Request request) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => RequestDetailsScreen(
          request: request,
          transports: transports,
          services: services,
          mechanics: mechanics,
          assignedMechanics: _assignedMechanicsForRequest[request.id] ?? [],
          onAssignMechanics: () => _showAssignMechanicsDialog(request),
        ),
      ),
    );
  }

  void _showAddMechanicDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Добавить механика'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _mechanicNameController,
                      decoration: const InputDecoration(
                        labelText: 'Имя механика *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _mechanicEmailController,
                      decoration: const InputDecoration(
                        labelText: 'Email *',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _mechanicPasswordController,
                      decoration: const InputDecoration(
                        labelText: 'Пароль *',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _pickMechanicImage,
                          child: const Text('Выбрать фото'),
                        ),
                        const SizedBox(width: 8),
                        if (_selectedMechanicPhotoBase64 != null)
                          const Text('Фото выбрано', style: TextStyle(color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '* - обязательные поля',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _clearMechanicForm();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_validateMechanicForm()) {
                      _createMechanic();
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Создать'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _validateMechanicForm() {
    if (_mechanicNameController.text.trim().isEmpty) {
      _showError('Введите имя механика');
      return false;
    }
    if (_mechanicEmailController.text.trim().isEmpty) {
      _showError('Введите email механика');
      return false;
    }
    if (_mechanicPasswordController.text.trim().isEmpty) {
      _showError('Введите пароль механика');
      return false;
    }
    return true;
  }

  Future<void> _createMechanic() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/mechanics'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': _mechanicNameController.text.trim(),
          'email': _mechanicEmailController.text.trim(),
          'password': _mechanicPasswordController.text.trim(),
          'photo': _selectedMechanicPhotoBase64,
          'role': 'mechanic',
          'serviceId': serviceId,
        }),
      );
      
      if (response.statusCode == 200) {
        await _loadServiceMechanics();
        _clearMechanicForm();
        _showSuccess('Механик успешно создан');
      } else {
        final errorData = json.decode(response.body);
        _showError('Ошибка создания механика: ${errorData['error'] ?? response.statusCode}');
      }
    } catch (e) {
      _showError('Ошибка создания механика: $e');
    }
  }

  void _clearMechanicForm() {
    _mechanicNameController.clear();
    _mechanicEmailController.clear();
    _mechanicPasswordController.clear();
    _selectedMechanicPhotoBase64 = null;
  }

  Future<void> _deleteMechanic(Mechanic mechanic) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/mechanics/${mechanic.id}'),
      );

      if (response.statusCode == 200) {
        await _loadServiceMechanics();
        _showSuccess('Механик удален');
      } else {
        _showError('Ошибка удаления механика: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Ошибка удаления механика: $e');
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'новая': return Colors.blue;
      case 'принята': return Colors.orange;
      case 'в работе': return Colors.purple;
      case 'временно отклонена': return Colors.red;
      case 'завершена': return Colors.green;
      default: return Colors.grey;
    }
  }

  String _getRequestStatus(Request request) {
     if (request.status == 'временно отклонена' || request.status == 'отклонена')
     { return 'временно отклонена';}
    if (request.closedAt != null) return 'закрыта';
    if (request.mechanicId != null) return 'в работе';
    return 'новая';
  }

  // ОБНОВЛЕННЫЙ МЕТОД ФИЛЬТРАЦИИ И СОРТИРОВКИ
  List<Request> _getFilteredAndSortedRequests() {
    List<Request> filtered = List.from(requests);

    if (_statusFilter != null) {
      filtered = filtered.where((request) => request.status == _statusFilter).toList();
    }

    if (_mechanicFilter != null) {
      filtered = filtered.where((request) => request.mechanicId?.toString() == _mechanicFilter).toList();
    }

    if (_transportFilter != null) {
      filtered = filtered.where((request) {
        final transport = transports.firstWhere(
          (t) => t.id == request.transportId,
          orElse: () => Transport(id: 0, type: '', serial: '', model: ''),
        );
        return transport.type == _transportFilter;
      }).toList();
    }

    filtered.sort((a, b) {
      if (_sortOrder == 'newest') {
        return b.submittedAt.compareTo(a.submittedAt);
      } else {
        return a.submittedAt.compareTo(b.submittedAt);
      }
    });

    return filtered;
  }

  // ОБНОВЛЕННЫЙ МЕТОД ДЛЯ КАРТОЧКИ ЗАЯВКИ
  Widget _buildRequestCard(Request request) {
    final transport = transports.firstWhere(
      (t) => t.id == request.transportId,
      orElse: () => Transport(id: 0, type: 'Неизвестно', serial: 'Неизвестно', model: 'Неизвестно'),
    );

    final status = _getRequestStatus(request);
    final statusColor = _getStatusColor(status);
    
    // Получаем количество назначенных механиков
    final assignedCount = _assignedMechanicsForRequest[request.id]?.length ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showRequestDetails(request),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Фото транспорта
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _buildTransportImage(transport.photo),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Название транспорта
                    Text(
                      transport.model,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Описание проблемы (первая строка)
                    Text(
                      request.problem.split('\n').first,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Информация о механиках
                    if (assignedCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.people, size: 16, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text(
                              '$assignedCount механик${assignedCount == 1 ? '' : (assignedCount > 1 && assignedCount < 5 ? 'а' : 'ов')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Статус заявки
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: statusColor),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Метод для построения изображения транспорта
  Widget _buildTransportImage(String? photoData) {
    if (photoData == null || photoData.isEmpty) {
      return const Center(
        child: Icon(Icons.directions_bus, size: 40, color: Colors.grey),
      );
    }

    try {
      List<String> photoList = [];
      
      // Пытаемся разобрать как JSON массив
      if (photoData.startsWith('[')) {
        try {
          final decoded = json.decode(photoData) as List;
          photoList = decoded.cast<String>();
        } catch (e) {
          print('Ошибка декодирования JSON: $e');
          photoList = [photoData];
        }
      } else {
        photoList = [photoData];
      }

      if (photoList.isEmpty) {
        return const Center(
          child: Icon(Icons.directions_bus, size: 40, color: Colors.grey),
        );
      }

      final firstPhoto = photoList.first;
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          base64Decode(firstPhoto),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Icon(Icons.error, color: Colors.red),
            );
          },
        ),
      );
    } catch (e) {
      print('Ошибка загрузки изображения транспорта: $e');
      return const Center(
        child: Icon(Icons.directions_bus, size: 40, color: Colors.grey),
      );
    }
  }

  void _showSortFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Сортировка и фильтры'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Сортировка по дате:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    RadioListTile<String>(
                      title: const Text('Сначала новые'),
                      value: 'newest',
                      groupValue: _sortOrder,
                      onChanged: (String? value) {
                        setState(() {
                          _sortOrder = value!;
                        });
                        Navigator.of(context).pop();
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Сначала старые'),
                      value: 'oldest',
                      groupValue: _sortOrder,
                      onChanged: (String? value) {
                        setState(() {
                          _sortOrder = value!;
                        });
                        Navigator.of(context).pop();
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    
                    const Text(
                      'Фильтр по статусу:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButtonFormField<String>(
                      value: _statusFilter,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Все статусы'),
                        ),
                        ..._statusList.map((String status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Text(status),
                          );
                        }),
                      ],
                      onChanged: (String? newValue) {
                        setState(() {
                          _statusFilter = newValue;
                        });
                        Navigator.of(context).pop();
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    const Text(
                      'Фильтр по механику:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButtonFormField<String>(
                      value: _mechanicFilter,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Все механики'),
                        ),
                        ...mechanics.map((mechanic) {
                          return DropdownMenuItem(
                            value: mechanic.id.toString(),
                            child: Text(mechanic.name),
                          );
                        }),
                      ],
                      onChanged: (String? newValue) {
                        setState(() {
                          _mechanicFilter = newValue;
                        });
                        Navigator.of(context).pop();
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    const Text(
                      'Фильтр по типу транспорта:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButtonFormField<String>(
                      value: _transportFilter,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Все типы'),
                        ),
                        ..._transportTypes.map((String type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type),
                          );
                        }),
                      ],
                      onChanged: (String? newValue) {
                        setState(() {
                          _transportFilter = newValue;
                        });
                        Navigator.of(context).pop();
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _sortOrder = 'newest';
                      _statusFilter = null;
                      _mechanicFilter = null;
                      _transportFilter = null;
                    });
                    Navigator.of(context).pop();
                  },
                  child: const Text('Сбросить'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateProfile() async {
    if (_nameController.text.trim().isEmpty || _emailController.text.trim().isEmpty) {
      _showError('Заполните имя и email');
      return;
    }

    try {
      final Map<String, dynamic> updateData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
      };

      if (_passwordController.text.trim().isNotEmpty) {
        updateData['password'] = _passwordController.text.trim();
      }

      final response = await http.put(
        Uri.parse('$baseUrl/managers/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updateData),
      );

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_name', _nameController.text.trim());
        await prefs.setString('user_email', _emailController.text.trim());
        
        setState(() {
          userName = _nameController.text.trim();
          userEmail = _emailController.text.trim();
          _passwordController.clear();
        });

        _showSuccess('Профиль успешно обновлен');
      } else {
        _showError('Ошибка обновления профиля: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Ошибка обновления профиля: $e');
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
    setState(() => _isAccountPanelOpen = false);
    await Future.delayed(const Duration(milliseconds: 300));
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context, 
        '/login', 
        (route) => false
      );
    }
  }

  // Обновленный метод построения панели профиля
  Widget _buildProfilePanel() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            // Кастомный заголовок для панели профиля
            Container(
              height: 80,
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.blue,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() => _isAccountPanelOpen = false),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Профиль',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white),
                    onPressed: _logout,
                    tooltip: 'Выйти',
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          _buildAvatar(userPhoto, 50),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Нажмите на фото для изменения',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Информация о сервисе
                    if (serviceAddress != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.business, color: Colors.blue[700]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Адрес сервиса',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                  Text(
                                    serviceAddress!,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // КНОПКА ДЛЯ ПЕРЕХОДА К СТАТИСТИКЕ (теперь открывает на весь экран)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 20),
                      child: ElevatedButton.icon(
                        onPressed: _openStatisticsScreen,
                        icon: const Icon(Icons.bar_chart),
                        label: const Text('Статистика поломок'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[100],
                          foregroundColor: Colors.blue[700],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Имя',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Новый пароль (оставьте пустым, если не хотите менять)',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _updateProfile,
                        child: const Text('Сохранить изменения'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredRequests = _getFilteredAndSortedRequests();

    return Stack(
      children: [
        Scaffold(
          appBar: null,
          body: Column(
            children: [
              // Кастомный заголовок вместо AppBar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Заявки сервиса',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                        });
                        _loadAllData().then((_) => setState(() => _isLoading = false));
                      },
                      tooltip: 'Обновить',
                    ),
                    IconButton(
                      icon: const Icon(Icons.filter_list, color: Colors.white),
                      onPressed: _showSortFilterDialog,
                      tooltip: 'Сортировка и фильтры',
                    ),
                    IconButton(
                      icon: const Icon(Icons.account_circle, color: Colors.white),
                      onPressed: () => setState(() => _isAccountPanelOpen = true),
                      tooltip: 'Профиль',
                    ),
                  ],
                ),
              ),
              // Вкладки
              Container(
                color: Colors.blue[50],
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.blue,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.blue,
                  tabs: const [
                    Tab(icon: Icon(Icons.list_alt), text: 'Заявки'),
                    Tab(icon: Icon(Icons.engineering), text: 'Механики'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Вкладка заявок
                    _isLoading
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Загрузка заявок...'),
                              ],
                            ),
                          )
                        : filteredRequests.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.list_alt, size: 80, color: Colors.grey),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Заявок нет',
                                      style: TextStyle(fontSize: 18, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Нет доступных заявок для вашего сервиса',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: filteredRequests.length,
                                itemBuilder: (context, index) {
                                  final request = filteredRequests[index];
                                  return _buildRequestCard(request);
                                },
                              ),
                    // Вкладка механиков
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: ElevatedButton.icon(
                                  onPressed: _showAddMechanicDialog,
                                  icon: const Icon(Icons.person_add),
                                  label: const Text('Добавить механика'),
                                ),
                              ),
                              Expanded(
                                child: mechanics.isEmpty
                                    ? const Center(child: Text('Механиков нет'))
                                    : ListView.builder(
                                        itemCount: mechanics.length,
                                        itemBuilder: (context, index) {
                                          final mechanic = mechanics[index];
                                          return Card(
                                            margin: const EdgeInsets.symmetric(
                                                vertical: 4, horizontal: 8),
                                            child: ListTile(
                                              leading: _buildAvatar(mechanic.photo, 20),
                                              title: Text(mechanic.name),
                                              subtitle: Text(mechanic.email),
                                              trailing: IconButton(
                                                icon: const Icon(Icons.delete,
                                                    color: Colors.red),
                                                onPressed: () =>
                                                    _deleteMechanic(mechanic),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // затемнение фона
        if (_isAccountPanelOpen)
          Container(
            color: Colors.black54,
          ),

        // панель профиля
        if (_isAccountPanelOpen)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _buildProfilePanel(),
          ),
      ],
    );
  }
}

// Класс для экрана статистики на весь экран
class StatisticsScreen extends StatefulWidget {
  final List<Request> requests;

  const StatisticsScreen({
    super.key,
    required this.requests,
  });

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Map<String, int> _monthlyRequests;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateMonthlyStatistics();
  }

  // Метод для вычисления статистики локально из загруженных данных
  void _calculateMonthlyStatistics() {
    final now = DateTime.now();
    final monthlyRequests = <String, int>{};
    
    // Инициализируем последние 6 месяцев
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i);
      final monthKey = '${_getMonthName(month.month)} ${month.year}';
      monthlyRequests[monthKey] = 0;
    }
    
    // Подсчитываем заявки по месяцам
    for (final request in widget.requests) {
      final monthKey = '${_getMonthName(request.submittedAt.month)} ${request.submittedAt.year}';
      if (monthlyRequests.containsKey(monthKey)) {
        monthlyRequests[monthKey] = monthlyRequests[monthKey]! + 1;
      }
    }
    
    setState(() {
      _monthlyRequests = monthlyRequests;
      _isLoading = false;
    });
  }

  // Метод для получения названия месяца по номеру
  String _getMonthName(int month) {
    switch (month) {
      case 1: return 'Январь';
      case 2: return 'Февраль';
      case 3: return 'Март';
      case 4: return 'Апрель';
      case 5: return 'Май';
      case 6: return 'Июнь';
      case 7: return 'Июль';
      case 8: return 'Август';
      case 9: return 'Сентябрь';
      case 10: return 'Октябрь';
      case 11: return 'Ноябрь';
      case 12: return 'Декабрь';
      default: return 'Месяц $month';
    }
  }

  // Метод для определения цвета в зависимости от количества заявок
  Color _getCountColor(int count) {
    if (count == 0) return Colors.grey;
    if (count <= 5) return Colors.green;
    if (count <= 15) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Статистика поломок'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _calculateMonthlyStatistics();
            },
            tooltip: 'Обновить статистику',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Загрузка статистики...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок статистики
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bar_chart, color: Colors.blue[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Количество поданных заявок за месяц',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                              Text(
                                'Последние 6 месяцев',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Список месяцев со статистикой
                  if (_monthlyRequests.isNotEmpty)
                    Column(
                      children: _monthlyRequests.entries.map((entry) {
                        final month = entry.key;
                        final count = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      month,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$count заявок',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Индикатор
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _getCountColor(count),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  count.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  else
                    const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bar_chart, size: 80, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Нет данных за последние месяцы',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 30),
                  
                  // Итоговая статистика
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.summarize, color: Colors.blue[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Общая статистика',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Всего заявок: ${widget.requests.length}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                'Период: ${_monthlyRequests.keys.isNotEmpty ? '${_monthlyRequests.keys.first} - ${_monthlyRequests.keys.last}' : 'Нет данных'}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Диаграмма (простая гистограмма)
                  const Text(
                    'Гистограмма заявок',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: _monthlyRequests.entries.map((entry) {
                        final month = entry.key.split(' ')[0]; // Берем только название месяца
                        final count = entry.value;
                        final maxCount = _monthlyRequests.values.reduce((a, b) => a > b ? a : b);
                        final height = maxCount > 0 ? (count / maxCount) * 150.0 : 10.0;
                        
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              count.toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 40,
                              height: height,
                              decoration: BoxDecoration(
                                color: _getCountColor(count),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(4),
                                  topRight: Radius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: 60,
                              child: Text(
                                month,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}

// Класс для экрана деталей заявки - вынесен на уровень файла
class RequestDetailsScreen extends StatelessWidget {
  final Request request;
  final List<Transport> transports;
  final List<Service> services;
  final List<Mechanic> mechanics;
  final List<Mechanic> assignedMechanics;
  final VoidCallback onAssignMechanics;

  const RequestDetailsScreen({
    super.key,
    required this.request,
    required this.transports,
    required this.services,
    required this.mechanics,
    required this.assignedMechanics,
    required this.onAssignMechanics,
  });

  String _getRequestStatus() {
    if (request.status == 'временно отклонена' || request.status == 'отклонена') {
      return 'временно отклонена';
    }
    if (request.closedAt != null) return 'закрыта';
    if (request.mechanicId != null) return 'в работе';
    
    return 'новая';
  }

  Color _getStatusColor() {
    final status = _getRequestStatus();
    switch (status) {
      case 'новая':
        return Colors.blue;
      case 'в работе':
        return Colors.orange;
      case 'закрыта':
        return Colors.green;
      case 'отклонена':
        return Colors.red;
      case 'временно отклонена':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // Метод для получения списка фотографий из данных транспорта
  List<String> _getTransportPhotos(String? photoData) {
    if (photoData == null || photoData.isEmpty) {
      return [];
    }

    try {
      List<String> photoList = [];
      
      // Пытаемся разобрать как JSON массив
      if (photoData.startsWith('[')) {
        try {
          final decoded = json.decode(photoData) as List;
          photoList = decoded.cast<String>();
        } catch (e) {
          print('Ошибка декодирования JSON фото: $e');
          photoList = [photoData];
        }
      } else {
        photoList = [photoData];
      }

      return photoList;
    } catch (e) {
      print('Ошибка получения фотографий транспорта: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final transport = transports.firstWhere(
      (t) => t.id == request.transportId,
      orElse: () => Transport(id: 0, type: 'Неизвестно', serial: 'Неизвестно', model: 'Неизвестно'),
    );

    final service = request.serviceId != null 
        ? services.firstWhere(
            (s) => s.id == request.serviceId,
            orElse: () => Service(id: 0, address: 'Не указан', workTime: ''),
          )
        : Service(id: 0, address: 'Не назначен', workTime: '');

    final status = _getRequestStatus();
    final statusColor = _getStatusColor();
    
    // Получаем все фотографии транспорта
    final transportPhotos = _getTransportPhotos(transport.photo);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Детали заявки #${request.id}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Статус заявки
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor),
              ),
              child: Row(
                children: [
                  Icon(
                    status == 'закрыта' 
                      ? Icons.check_circle
                      : status == 'в работе'
                        ? Icons.build
                        : status == 'отклонена' || status == 'временно отклонена'
                        ? Icons.warning
                        : Icons.new_releases,
                    color: statusColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Статус: $status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Основная информация
            const Text(
              'Основная информация',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Номер заявки:', '#${request.id}'),
            _buildDetailRow('Дата создания:', 
              '${request.submittedAt.day}.${request.submittedAt.month}.${request.submittedAt.year} ${request.submittedAt.hour}:${request.submittedAt.minute.toString().padLeft(2, '0')}'),
            if (request.closedAt != null)
              _buildDetailRow('Дата закрытия:', 
                '${request.closedAt!.day}.${request.closedAt!.month}.${request.closedAt!.year}'),
            _buildDetailRow('Сервисный центр:', service.address),
            if (service.workTime.isNotEmpty)
              _buildDetailRow('Время работы:', service.workTime),
            
            const SizedBox(height: 24),
            
            // Перечень проблем - нумерованный список
            const Text(
              'Перечень проблем',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...request.problem.split('\n').where((line) => line.trim().isNotEmpty).toList().asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('${entry.key + 1}. ${entry.value.trim()}'),
                    ),
                  ).toList(),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Причина отклонения (если заявка отклонена)
            if (request.rejectionReason != null && request.rejectionReason!.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning, color: Colors.red),
                            SizedBox(width: 8),
                            Text(
                              'Заявка временно отклонена',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Причина отклонения:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          request.rejectionReason!,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            
            // Данные транспорта
            const Text(
              'Данные транспорта',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Тип транспорта:', transport.type),
            _buildDetailRow('Модель:', transport.model),
            _buildDetailRow('Серийный номер:', transport.serial),
            
            // Фотографии транспорта
            if (transportPhotos.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'Фотографии транспорта:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${transportPhotos.length} фото',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: transportPhotos.length,
                      itemBuilder: (context, index) {
                        final photoBase64 = transportPhotos[index];
                        return Container(
                          width: 200,
                          margin: EdgeInsets.only(
                            right: index < transportPhotos.length - 1 ? 12 : 0,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              base64Decode(photoBase64),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.error, color: Colors.red, size: 40),
                                      const SizedBox(height: 8),
                                      Text('Фото ${index + 1}',
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (transportPhotos.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Прокрутите вправо чтобы увидеть все фотографии',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            
            // Механик
            const SizedBox(height: 24),
            const Text(
              'Назначенные механики',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 12),
            
            if (assignedMechanics.isNotEmpty)
              ...assignedMechanics.map((mechanic) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(mechanic.name[0]),
                    ),
                    title: Text(mechanic.name),
                    subtitle: Text(mechanic.email),
                  ),
                );
              }).toList()
            else
              const Text('Механики не назначены'),
            
            const SizedBox(height: 24),
            
            // Кнопки действий для менеджера
            Center(
              child: ElevatedButton(
                onPressed: onAssignMechanics,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text(
                  'Назначить механиков',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text(
                  'Закрыть',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Модели данных - ОТДЕЛЬНО от класса RequestDetailsScreen
class Request {
  final int id;
  final String problem;
  final DateTime submittedAt;
  final DateTime? closedAt;
  final int transportId;
  final int applicantId;
  final int? mechanicId;
  final int? serviceId;
  final String status;
  final String? rejectionReason;
  final Map<String, dynamic>? applicant;
  final Map<String, dynamic>? transport;
  final Map<String, dynamic>? mechanic;

  Request({
    required this.id,
    required this.problem,
    required this.submittedAt,
    this.closedAt,
    required this.transportId,
    required this.applicantId,
    this.mechanicId,
    this.serviceId,
    required this.status,
    this.rejectionReason,
    this.applicant,
    this.transport,
    this.mechanic,
  });

  factory Request.fromJson(Map<String, dynamic> json) {
    return Request(
      id: json['id'] ?? 0,
      problem: json['problem'] ?? 'Описание не указано',
      submittedAt: DateTime.parse(json['submittedAt'] ?? DateTime.now().toIso8601String()),
      closedAt: json['closedAt'] != null ? DateTime.parse(json['closedAt']) : null,
      transportId: json['transportId'] ?? 0,
      applicantId: json['applicantId'] ?? 0,
      mechanicId: json['mechanicId'],
      serviceId: json['serviceId'],
      status: json['status'] ?? 'новая',
      rejectionReason: json['rejectionReason'],
      applicant: json['applicant'] is Map ? Map<String, dynamic>.from(json['applicant']) : null,
      transport: json['transport'] is Map ? Map<String, dynamic>.from(json['transport']) : null,
      mechanic: json['mechanic'] is Map ? Map<String, dynamic>.from(json['mechanic']) : null,
    );
  }
}

class Mechanic {
  final int id;
  final String name;
  final String email;
  final String? photo;
  final int serviceId;

  Mechanic({
    required this.id,
    required this.name,
    required this.email,
    required this.serviceId,
    this.photo,
  });

  factory Mechanic.fromJson(Map<String, dynamic> json) {
    return Mechanic(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Неизвестно',
      email: json['email'] ?? 'Неизвестно',
      serviceId: json['serviceId'] ?? 0,
      photo: json['photo'],
    );
  }
}

class Applicant {
  final int id;
  final String name;
  final String email;

  Applicant({required this.id, required this.name, required this.email});

  factory Applicant.fromJson(Map<String, dynamic> json) {
    return Applicant(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Неизвестно',
      email: json['email'] ?? 'Неизвестно',
    );
  }
}

class Transport {
  final int id;
  final String type;
  final String serial;
  final String? photo;
  final String model;

  Transport({
    required this.id,
    required this.type,
    required this.serial,
    required this.model,
    this.photo,
  });

  factory Transport.fromJson(Map<String, dynamic> json) {
    return Transport(
      id: json['id'] ?? 0,
      type: json['type'] ?? 'Неизвестно',
      serial: json['serial'] ?? 'Неизвестно',
      model: json['model'] ?? 'Неизвестно',
      photo: json['photo'],
    );
  }
}

class Service {
  final int id;
  final String address;
  final String workTime;

  Service({
    required this.id,
    required this.address,
    required this.workTime,
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'] ?? 0,
      address: json['address'] ?? 'Адрес не указан',
      workTime: json['workTime'] ?? '',
    );
  }
}