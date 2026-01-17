import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../global_config.dart';

final String baseUrl = GlobalConfig.baseUrl;


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
  final Map<int, List<RepairDetail>> _repairDetailsByRequest = {}; // requestId -> list of repair details
  final Map<int, String> _mechanicNames = {}; // mechanicId -> mechanic name
  
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
  
  // Новые переменные для статусов механиков
  final List<String> _mechanicStatuses = [
    'свободен',
    'занят',
    'болеет',
    'в отпуске'
  ];
  
  // Мапа для хранения статусов механиков
  final Map<int, Map<String, dynamic>> _mechanicStatusData = {};

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

  // НОВЫЙ МЕТОД: Загрузка деталей ремонта для заявки
  Future<void> _loadRepairDetailsForRequest(int requestId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/requests/$requestId/repair-details'),
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<RepairDetail> details = data.map((item) => RepairDetail.fromJson(item)).toList();
        
        setState(() {
          _repairDetailsByRequest[requestId] = details;
        });
      } else if (response.statusCode == 404) {
        // Если деталей нет, создаем пустой список
        setState(() {
          _repairDetailsByRequest[requestId] = [];
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки деталей ремонта для заявки $requestId: $e');
      setState(() {
        _repairDetailsByRequest[requestId] = [];
      });
    }
  }

  // НОВЫЙ МЕТОД: Загрузка деталей ремонта для всех заявок
  Future<void> _loadRepairDetailsForAllRequests() async {
    for (var request in requests) {
      await _loadRepairDetailsForRequest(request.id);
    }
  }

  // НОВЫЙ МЕТОД: Загрузка имен механиков для отображения в деталях ремонта
  Future<void> _loadMechanicNames() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/mechanics'),
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        setState(() {
          for (var mechanicData in data) {
            final mechanicId = mechanicData['id'] as int;
            final mechanicName = mechanicData['name'] as String;
            _mechanicNames[mechanicId] = mechanicName;
          }
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки имен механиков: $e');
    }
  }

  // НОВЫЙ МЕТОД: Загрузка статусов механиков
  Future<void> _loadMechanicsStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/mechanics-with-status'),
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        setState(() {
          for (final mechanicData in data) {
            final mechanicId = mechanicData['id'] as int;
            _mechanicStatusData[mechanicId] = {
              'status': mechanicData['status'] ?? 'свободен',
              'statusStartDate': mechanicData['statusStartDate'] != null 
                ? DateTime.parse(mechanicData['statusStartDate'])
                : null,
              'statusEndDate': mechanicData['statusEndDate'] != null 
                ? DateTime.parse(mechanicData['statusEndDate'])
                : null,
            };
          }
        });
        
        // Проверяем окончание сроков болезни/отпуска
        _checkAndUpdateExpiredStatuses();
      }
    } catch (e) {
      debugPrint('Ошибка загрузки статусов механиков: $e');
    }
  }

  // НОВЫЙ МЕТОД: Проверка и обновление истекших статусов болезни/отпуска
  void _checkAndUpdateExpiredStatuses() {
    final now = DateTime.now();
    
    setState(() {
      for (final entry in _mechanicStatusData.entries) {
        final mechanicId = entry.key;
        final statusData = entry.value;
        final status = statusData['status'] as String?;
        final endDate = statusData['statusEndDate'] as DateTime?;
        
        // Если статус "болеет" или "в отпуске" и срок истек
        if ((status == 'болеет' || status == 'в отпуске') && 
            endDate != null && 
            now.isAfter(endDate)) {
          
          // Автоматически меняем статус на "свободен"
          _mechanicStatusData[mechanicId] = {
            'status': 'свободен',
            'statusStartDate': null,
            'statusEndDate': null,
          };
          
          // Обновляем статус на сервере (в фоновом режиме)
          _updateMechanicStatusToFree(mechanicId);
        }
      }
    });
  }

  // НОВЫЙ МЕТОД: Обновление статуса механика на "свободен" на сервере
  Future<void> _updateMechanicStatusToFree(int mechanicId) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/mechanics/$mechanicId/status'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'status': 'свободен',
          'statusStartDate': null,
          'statusEndDate': null,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Статус механика $mechanicId автоматически изменен на "свободен"');
      } else {
        debugPrint('Ошибка автоматического обновления статуса механика $mechanicId: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Ошибка автоматического обновления статуса механика $mechanicId: $e');
    }
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
      debugPrint('Ошибка загрузки назначенных механиков: $e');
    }
  }

  // НОВЫЙ МЕТОД: Диалог назначения статуса механику
  void _showMechanicStatusDialog(Mechanic mechanic) {
    final currentStatus = _mechanicStatusData[mechanic.id]?['status'] ?? 'свободен';
    DateTime? startDate = _mechanicStatusData[mechanic.id]?['statusStartDate'];
    DateTime? endDate = _mechanicStatusData[mechanic.id]?['statusEndDate'];
    
    String selectedStatus = currentStatus;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Статус механика'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ФИО механика
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          _buildAvatar(mechanic.photo, 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mechanic.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  mechanic.email,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Выбор статуса
                    const Text(
                      'Выберите статус:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    ..._mechanicStatuses.map((status) {
                      return RadioListTile<String>(
                        title: Text(status),
                        value: status,
                        groupValue: selectedStatus,
                        onChanged: (String? value) {
                          setDialogState(() {
                            selectedStatus = value!;
                          });
                        },
                      );
                    }).toList(),
                    
                    // Календарь для статусов с датами
                    if (selectedStatus == 'болеет' || selectedStatus == 'в отпуске')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          const Text(
                            'Период отсутствия:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          
                          const SizedBox(height: 8),
                          
                          // Дата начала
                          ListTile(
                            leading: const Icon(Icons.calendar_today),
                            title: Text(
                              startDate != null 
                                ? _formatDate(startDate!)
                                : 'Выберите дату начала',
                            ),
                            trailing: const Icon(Icons.arrow_drop_down),
                            onTap: () async {
                              final DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: startDate ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime(DateTime.now().year + 1),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  startDate = picked;
                                });
                              }
                            },
                          ),
                          
                          // Дата окончания
                          ListTile(
                            leading: const Icon(Icons.calendar_today),
                            title: Text(
                              endDate != null 
                                ? _formatDate(endDate!)
                                : 'Выберите дату окончания',
                            ),
                            trailing: const Icon(Icons.arrow_drop_down),
                            onTap: () async {
                              final DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: endDate ?? (startDate ?? DateTime.now()),
                                firstDate: startDate ?? DateTime.now(),
                                lastDate: DateTime(DateTime.now().year + 1),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  endDate = picked;
                                });
                              }
                            },
                          ),
                          
                          // Проверка корректности дат
                          if (startDate != null && endDate != null && endDate!.isBefore(startDate!))
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'Дата окончания должна быть позже даты начала',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ),
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
                    if (selectedStatus == 'болеет' || selectedStatus == 'в отпуске') {
                      if (startDate == null || endDate == null) {
                        _showError('Укажите даты начала и окончания');
                        return;
                      }
                      if (endDate!.isBefore(startDate!)) {
                        _showError('Дата окончания должна быть позже даты начала');
                        return;
                      }
                    }
                    
                    await _updateMechanicStatus(mechanic, selectedStatus, startDate, endDate);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // НОВЫЙ МЕТОД: Обновление статуса механика
  Future<void> _updateMechanicStatus(Mechanic mechanic, String status, DateTime? startDate, DateTime? endDate) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/mechanics/${mechanic.id}/status'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'status': status,
          'statusStartDate': startDate?.toIso8601String(),
          'statusEndDate': endDate?.toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _mechanicStatusData[mechanic.id] = {
            'status': status,
            'statusStartDate': startDate,
            'statusEndDate': endDate,
          };
        });
        
        _showSuccess('Статус механика обновлен');
        
        // Обновляем список механиков
        await _loadServiceMechanics();
      } else {
        _showError('Ошибка обновления статуса: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Ошибка обновления статуса: $e');
    }
  }

  // НОВЫЙ МЕТОД: Получение цвета статуса механика
  Color _getMechanicStatusColor(String status) {
    switch (status) {
      case 'свободен': return Colors.green;
      case 'занят': return Colors.orange;
      case 'болеет': return Colors.red;
      case 'в отпуске': return Colors.blue;
      default: return Colors.grey;
    }
  }

  // НОВЫЙ МЕТОД: Получение иконки статуса механика
  IconData _getMechanicStatusIcon(String status) {
    switch (status) {
      case 'свободен': return Icons.check_circle;
      case 'занят': return Icons.work;
      case 'болеет': return Icons.local_hospital;
      case 'в отпуске': return Icons.beach_access;
      default: return Icons.help;
    }
  }

  // НОВЫЙ МЕТОД: Форматирование дат статуса
  String _formatMechanicStatusDates(DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) return '';
    
    final startStr = _formatDate(startDate);
    final endStr = _formatDate(endDate);
    
    return '$startStr - $endStr';
  }

  // Метод для форматирования даты
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
                    
                    // Список механиков с чекбоксами и статусами
                    SizedBox(
                      height: 300,
                      child: ListView.builder(
                        itemCount: mechanics.length,
                        itemBuilder: (context, index) {
                          final mechanic = mechanics[index];
                          final isSelected = selectedMechanicIds.contains(mechanic.id);
                          final status = _mechanicStatusData[mechanic.id]?['status'] ?? 'свободен';
                          final statusColor = _getMechanicStatusColor(status);
                          final statusIcon = _getMechanicStatusIcon(status);
                          
                          // Проверяем доступность механика
                          bool isAvailable = true;
                          if (status == 'болеет' || status == 'в отпуске') {
                            final startDate = _mechanicStatusData[mechanic.id]?['statusStartDate'];
                            final endDate = _mechanicStatusData[mechanic.id]?['statusEndDate'];
                            final now = DateTime.now();
                            
                            if (startDate != null && endDate != null) {
                              isAvailable = now.isBefore(startDate) || now.isAfter(endDate);
                            }
                          } else if (status == 'занят') {
                            isAvailable = false;
                          }
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: CheckboxListTile(
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mechanic.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  
                                  // Статус механика
                                  Row(
                                    children: [
                                      Icon(
                                        statusIcon,
                                        size: 14,
                                        color: statusColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        status,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: statusColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      
                                      // Даты если есть
                                      if ((status == 'болеет' || status == 'в отпуске') && 
                                          _mechanicStatusData[mechanic.id]?['statusStartDate'] != null &&
                                          _mechanicStatusData[mechanic.id]?['statusEndDate'] != null)
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 8),
                                            child: Text(
                                              _formatMechanicStatusDates(
                                                _mechanicStatusData[mechanic.id]?['statusStartDate'],
                                                _mechanicStatusData[mechanic.id]?['statusEndDate'],
                                              ),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[600],
                                                fontStyle: FontStyle.italic,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  
                                  // Предупреждение если механик недоступен
                                  if (!isAvailable)
                                    Text(
                                      'Недоступен для назначения',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.red,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(mechanic.email),
                              value: isSelected,
                              onChanged: isAvailable 
                                ? (bool? value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selectedMechanicIds.add(mechanic.id);
                                      } else {
                                        selectedMechanicIds.remove(mechanic.id);
                                      }
                                    });
                                  }
                                : null, // Делаем недоступным если механик занят/болеет/в отпуске
                            ),
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
                            final status = _mechanicStatusData[mechanic.id]?['status'] ?? 'свободен';
                            final statusColor = _getMechanicStatusColor(status);
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    _getMechanicStatusIcon(status),
                                    size: 16,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text('• ${mechanic.name}'),
                                  ),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: statusColor,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
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
        // Обновляем локальные данные
        setState(() {
          _selectedMechanicsForRequest[request.id] = mechanicIds;
          _assignedMechanicsForRequest[request.id] = mechanicIds
              .map((id) => mechanics.firstWhere((m) => m.id == id))
              .toList();
        });
        
        // Автоматически меняем статус механиков на "занят"
        for (final mechanicId in mechanicIds) {
          await _updateMechanicStatusToBusy(mechanicId);
        }
        
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

  // НОВЫЙ МЕТОД: Автоматическое изменение статуса механика на "занят"
  Future<void> _updateMechanicStatusToBusy(int mechanicId) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/mechanics/$mechanicId/status'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'status': 'занят',
          'statusStartDate': null,
          'statusEndDate': null,
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _mechanicStatusData[mechanicId] = {
            'status': 'занят',
            'statusStartDate': null,
            'statusEndDate': null,
          };
        });
        
        // Обновляем список механиков
        await _loadServiceMechanics();
      } else {
        debugPrint('Ошибка обновления статуса механика на "занят": ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Ошибка обновления статуса механика на "занят": $e');
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
      debugPrint('Ошибка загрузки фото пользователя: $e');
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
              debugPrint('Ошибка загрузки изображения: $exception');
            },
          );
        }
      } catch (e) {
        debugPrint('Ошибка декодирования base64 изображения: $e');
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
      debugPrint('Ошибка загрузки данных пользователя: $e');
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
      debugPrint('Ошибка загрузки данных менеджера: $e');
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
      debugPrint('Ошибка загрузки деталей сервиса: $e');
      setState(() {
        serviceAddress = 'Адрес не указан';
      });
    }
  }

  // ОБНОВЛЕННЫЙ МЕТОД ЗАГРУЗКИ ДАННЫХ (с загрузкой деталей ремонта)
  Future<void> _loadAllData() async {
    try {
      await Future.wait([
        _loadAllRequests(),
        _loadServiceMechanics(),
        _loadTransports(),
        _loadApplicants(),
        _loadServices(),
        _loadMechanicsStatus(), // Загружаем статусы механиков
        _loadMechanicNames(), // Загружаем имена механиков
      ]);
      
      // Загружаем назначенных механиков для каждой заявки
      for (var request in requests) {
        await _loadAssignedMechanicsForRequest(request.id);
        await _loadRepairDetailsForRequest(request.id); // Загружаем детали ремонта
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Ошибка загрузки всех данных: $e');
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
        
        // НОВЫЙ КОД: Проверяем закрытые заявки и освобождаем механиков
        await _checkAndFreeMechanicsFromClosedRequests();
      }
    } catch (e) {
      debugPrint('Error loading requests: $e');
    }
  }

  // НОВЫЙ МЕТОД: Проверка закрытых заявок и освобождение механиков
  Future<void> _checkAndFreeMechanicsFromClosedRequests() async {
    for (final request in requests) {
      // Если заявка закрыта (имеет дату закрытия)
      if (request.closedAt != null) {
        // Получаем назначенных механиков для этой заявки
        final assignedMechanics = _assignedMechanicsForRequest[request.id];
        
        if (assignedMechanics != null && assignedMechanics.isNotEmpty) {
          for (final mechanic in assignedMechanics) {
            // Проверяем, что механик все еще в статусе "занят"
            final currentStatus = _mechanicStatusData[mechanic.id]?['status'] ?? 'свободен';
            
            if (currentStatus == 'занят') {
              // Меняем статус на "свободен"
              await _updateMechanicStatusToFree(mechanic.id);
              
              // Обновляем локальные данные
              setState(() {
                _mechanicStatusData[mechanic.id] = {
                  'status': 'свободен',
                  'statusStartDate': null,
                  'statusEndDate': null,
                };
              });
            }
          }
        }
      }
    }
  }

  // Обновленный метод загрузки механиков сервиса
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
        
        // Загружаем статусы для каждого механика
        for (final mechanic in mechanics) {
          await _loadMechanicStatus(mechanic.id);
        }
      }
    } catch (e) {
      debugPrint('Error loading mechanics: $e');
    }
  }

  // НОВЫЙ МЕТОД: Загрузка статуса конкретного механика
  Future<void> _loadMechanicStatus(int mechanicId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/mechanics/$mechanicId/status'),
      );
      
      if (response.statusCode == 200) {
        final statusData = json.decode(response.body);
        
        setState(() {
          _mechanicStatusData[mechanicId] = {
            'status': statusData['status'] ?? 'свободен',
            'statusStartDate': statusData['statusStartDate'] != null 
              ? DateTime.parse(statusData['statusStartDate'])
              : null,
            'statusEndDate': statusData['statusEndDate'] != null 
              ? DateTime.parse(statusData['statusEndDate'])
              : null,
          };
        });
        
        // Проверяем, не истек ли срок болезни/отпуска
        _checkAndUpdateSingleExpiredStatus(mechanicId);
      }
    } catch (e) {
      debugPrint('Ошибка загрузки статуса механика $mechanicId: $e');
    }
  }

  // НОВЫЙ МЕТОД: Проверка и обновление истекшего статуса для конкретного механика
  void _checkAndUpdateSingleExpiredStatus(int mechanicId) {
    final now = DateTime.now();
    final statusData = _mechanicStatusData[mechanicId];
    
    if (statusData != null) {
      final status = statusData['status'] as String?;
      final endDate = statusData['statusEndDate'] as DateTime?;
      
      // Если статус "болеет" или "в отпуске" и срок истек
      if ((status == 'болеет' || status == 'в отпуске') && 
          endDate != null && 
          now.isAfter(endDate)) {
        
        // Автоматически меняем статус на "свободен"
        setState(() {
          _mechanicStatusData[mechanicId] = {
            'status': 'свободен',
            'statusStartDate': null,
            'statusEndDate': null,
          };
        });
        
        // Обновляем статус на сервере (в фоновом режиме)
        _updateMechanicStatusToFree(mechanicId);
      }
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
      debugPrint('Error loading transports: $e');
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
      debugPrint('Error loading applicants: $e');
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
      debugPrint('Error loading services: $e');
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

  // НОВЫЙ МЕТОД ДЛЯ ПОКАЗА ДЕТАЛЕЙ ЗАЯВКИ ВО ВЕСЬ ЭКРАН (теперь с деталями ремонта)
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
          mechanicStatusData: _mechanicStatusData,
          repairDetails: _repairDetailsByRequest[request.id] ?? [], // Передаем детали ремонта
          mechanicNames: _mechanicNames, // Передаем имена механиков
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
        await _loadMechanicsStatus();
        await _loadMechanicNames();
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
        // Удаляем статус из локального хранилища
        setState(() {
          _mechanicStatusData.remove(mechanic.id);
          _mechanicNames.remove(mechanic.id);
        });
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

  // НОВЫЙ МЕТОД: Получение форматированного описания проблемы для карточки
  String _getFormattedProblemPreview(String description) {
    String cleanedDescription = description.replaceAll(RegExp(r'!+$'), '');
    List<String> problems = cleanedDescription.split('!').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    
    if (problems.isNotEmpty) {
      return '1. ${problems[0]}';
    }
    
    return 'Проблема не указана';
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
    
    // Получаем детали ремонта
    final repairDetailsCount = _repairDetailsByRequest[request.id]?.length ?? 0;

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
                    // Описание проблемы
                    Text(
                      (request.problemDescription?.isNotEmpty ?? false) 
                        ? _getFormattedProblemPreview(request.problemDescription!)
                        : _getFormattedProblemPreview(request.problem),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Информация о механиках и деталях ремонта
                    Row(
                      children: [
                        if (assignedCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Row(
                              children: [
                                Icon(Icons.people, size: 14, color: Colors.blue),
                                const SizedBox(width: 4),
                                Text(
                                  '$assignedCount',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        if (repairDetailsCount > 0)
                          Row(
                            children: [
                              Icon(Icons.build_circle, size: 14, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                '$repairDetailsCount',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
          debugPrint('Ошибка декодирования JSON: $e');
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
      debugPrint('Ошибка загрузки изображения транспорта: $e');
      return const Center(
        child: Icon(Icons.directions_bus, size: 40, color: Colors.grey),
      );
    }
  }

  // Обновленный метод построения карточки механика во вкладке механиков
  Widget _buildMechanicCard(Mechanic mechanic) {
    final status = _mechanicStatusData[mechanic.id]?['status'] ?? 'свободен';
    final statusColor = _getMechanicStatusColor(status);
    final statusIcon = _getMechanicStatusIcon(status);
    
    // Форматируем даты если есть
    String datesText = '';
    if ((status == 'болеет' || status == 'в отпуске') && 
        _mechanicStatusData[mechanic.id]?['statusStartDate'] != null &&
        _mechanicStatusData[mechanic.id]?['statusEndDate'] != null) {
      datesText = _formatMechanicStatusDates(
        _mechanicStatusData[mechanic.id]?['statusStartDate'],
        _mechanicStatusData[mechanic.id]?['statusEndDate'],
      );
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: _buildAvatar(mechanic.photo, 20),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mechanic.name),
            
            // Статус механика
            Row(
              children: [
                Icon(
                  statusIcon,
                  size: 14,
                  color: statusColor,
                ),
                const SizedBox(width: 4),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            
            // Даты если есть
            if (datesText.isNotEmpty)
              Text(
                datesText,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
        subtitle: Text(mechanic.email),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showMechanicStatusDialog(mechanic),
              tooltip: 'Изменить статус',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteMechanic(mechanic),
            ),
          ],
        ),
      ),
    );
  }

  // Обновленный метод для вкладки механиков
  Widget _buildMechanicsTab() {
    return _isLoading
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
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.engineering, size: 80, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'Механиков нет',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Добавьте механиков для вашего сервиса',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: mechanics.length,
                        itemBuilder: (context, index) {
                          final mechanic = mechanics[index];
                          return _buildMechanicCard(mechanic);
                        },
                      ),
              ),
            ],
          );
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
                    _buildMechanicsTab(),
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

// Класс для экрана статистики на весь экран - ИЗМЕНЕН ДЛЯ СТАТИСТИКИ ПО ПРОБЛЕМАМ
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
  late Map<String, int> _problemStatistics;
  late Map<String, List<Request>> _problemToRequestsMap;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateProblemStatistics();
  }

  // ИЗМЕНЕННЫЙ МЕТОД: Теперь статистика основывается на перечне проблем
  void _calculateProblemStatistics() {
    final problemStatistics = <String, int>{};
    final problemToRequestsMap = <String, List<Request>>{};
    
    // Обрабатываем все заявки
    for (final request in widget.requests) {
      // Проверяем, есть ли данные о проблемах в формате списка
      if (request.problems?.isNotEmpty ?? false) {
        // Если есть структурированный список проблем
        for (final problem in request.problems!) {
          final problemName = problem['name'] ?? 'Неизвестная проблема';
          
          // Увеличиваем счетчик для этой проблемы
          problemStatistics[problemName] = (problemStatistics[problemName] ?? 0) + 1;
          
          // Добавляем заявку в мапу для этой проблемы
          if (!problemToRequestsMap.containsKey(problemName)) {
            problemToRequestsMap[problemName] = [];
          }
          problemToRequestsMap[problemName]!.add(request);
        }
      } else {
        // Если нет структурированного списка, анализируем текстовое описание
        final problemText = (request.problemDescription?.isNotEmpty ?? false) 
            ? request.problemDescription! 
            : request.problem;
        
        // Очищаем текст от разделителей
        String cleanedDescription = problemText.replaceAll(RegExp(r'!+$'), '');
        List<String> problems = cleanedDescription.split('!')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        
        if (problems.isNotEmpty) {
          // Берем первую проблему как основную
          final mainProblem = problems[0];
          problemStatistics[mainProblem] = (problemStatistics[mainProblem] ?? 0) + 1;
          
          // Добавляем заявку в мапу для этой проблемы
          if (!problemToRequestsMap.containsKey(mainProblem)) {
            problemToRequestsMap[mainProblem] = [];
          }
          problemToRequestsMap[mainProblem]!.add(request);
        } else {
          // Если проблем нет, используем общее описание
          final fallbackProblem = 'Общая проблема';
          problemStatistics[fallbackProblem] = (problemStatistics[fallbackProblem] ?? 0) + 1;
          
          if (!problemToRequestsMap.containsKey(fallbackProblem)) {
            problemToRequestsMap[fallbackProblem] = [];
          }
          problemToRequestsMap[fallbackProblem]!.add(request);
        }
      }
    }
    
    // Сортируем по количеству заявок (по убыванию)
    final sortedEntries = problemStatistics.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final sortedStatistics = <String, int>{};
    for (final entry in sortedEntries) {
      sortedStatistics[entry.key] = entry.value;
    }
    
    setState(() {
      _problemStatistics = sortedStatistics;
      _problemToRequestsMap = problemToRequestsMap;
      _isLoading = false;
    });
  }

  // Метод для форматирования даты
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  // Метод для определения цвета в зависимости от количества заявок
  Color _getCountColor(int count) {
    if (count == 0) return Colors.grey;
    if (count <= 3) return Colors.green;
    if (count <= 10) return Colors.orange;
    return Colors.red;
  }

  // Метод для показа деталей по конкретной проблеме
  void _showProblemDetails(String problemName, List<Request> requests) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Заявки с проблемой: $problemName'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                Text(
                  'Всего заявок: ${requests.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final request = requests[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text('Заявка #${request.id}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Дата: ${_formatDate(request.submittedAt)}'),
                              Text('Статус: ${request.status}'),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
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
              _calculateProblemStatistics();
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
                                'Статистика поломок по типам проблем',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                              Text(
                                'Всего различных проблем: ${_problemStatistics.length}',
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
                  
                  // Список проблем со статистикой
                  if (_problemStatistics.isNotEmpty)
                    Column(
                      children: _problemStatistics.entries.map((entry) {
                        final problemName = entry.key;
                        final count = entry.value;
                        final requestsForProblem = _problemToRequestsMap[problemName] ?? [];
                        
                        return GestureDetector(
                          onTap: () => _showProblemDetails(problemName, requestsForProblem),
                          child: Container(
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
                                        problemName,
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
                            'Нет данных о проблемах',
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
                                'Уникальных проблем: ${_problemStatistics.length}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Диаграмма (простая гистограмма) проблем
                  if (_problemStatistics.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Гистограмма проблем',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          height: 250,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: _problemStatistics.entries.take(6).map((entry) {
                              final problemName = entry.key;
                              final count = entry.value;
                              final maxCount = _problemStatistics.values.reduce((a, b) => a > b ? a : b);
                              final height = maxCount > 0 ? (count / maxCount) * 150.0 : 10.0;
                              
                              // Сокращаем название проблемы для отображения
                              String displayName = problemName;
                              if (problemName.length > 15) {
                                displayName = '${problemName.substring(0, 12)}...';
                              }
                              
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
                                    width: 50,
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
                                      displayName,
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
                        if (_problemStatistics.length > 6)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Показано топ-6 проблем из ${_problemStatistics.length}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
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
  final Map<int, Map<String, dynamic>> mechanicStatusData;
  final List<RepairDetail> repairDetails;
  final Map<int, String> mechanicNames; // mechanicId -> name

  const RequestDetailsScreen({
    super.key,
    required this.request,
    required this.transports,
    required this.services,
    required this.mechanics,
    required this.assignedMechanics,
    required this.onAssignMechanics,
    required this.mechanicStatusData,
    this.repairDetails = const [],
    this.mechanicNames = const {},
  });

  // НОВЫЙ ВИДЖЕТ для отображения деталей ремонта (для менеджера)
  Widget _buildRepairDetailsSection() {
    if (repairDetails.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        child: const Center(
          child: Text(
            'Детали ремонта не добавлены',
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Детали ремонта',
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
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Column(
            children: [
              // Заголовок таблицы
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Деталь',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Кол-во',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Артикул',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Механик',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.blue),
              // Список деталей
              ...repairDetails.map((detail) {
                final mechanicName = mechanicNames[detail.mechanicId] ?? 'Неизвестно';
                
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.blue[100]!)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          detail.partName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${detail.quantity} шт.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          detail.partNumber ?? '-',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: detail.partNumber == null ? Colors.grey : Colors.black,
                            fontStyle: detail.partNumber == null ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          mechanicName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ]
    );
  }

  // Форматирование описания проблемы
  List<Widget> _formatProblemDescription(String description) {
    String cleanedDescription = description.replaceAll(RegExp(r'!+$'), '');
    List<String> problems = cleanedDescription.split('!')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    
    return problems.asMap().entries.map((entry) {
      final index = entry.key;
      final problem = entry.value;
      
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            Expanded(
              child: Text(
                problem,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // Построение списка проблем
  Widget _buildProblemsList() {
    // Проверяем, есть ли данные о проблемах в формате списка
    if (request.problems?.isNotEmpty ?? false) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Перечень проблем:',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 12),
          ...request.problems!.asMap().entries.map((entry) {
            final index = entry.key;
            final problem = entry.value;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          problem['name'] ?? 'Проблема',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (problem['description'] != null && problem['description']!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              problem['description']!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      );
    }
    
    // Если данных в формате списка нет, используем текстовое описание
    final problemText = (request.problemDescription?.isNotEmpty ?? false) 
        ? request.problemDescription! 
        : request.problem;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Перечень проблем:',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 12),
        ..._formatProblemDescription(problemText),
      ],
    );
  }

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

  // НОВЫЙ МЕТОД: Получение цвета статуса механика
  Color _getMechanicStatusColor(String status) {
    switch (status) {
      case 'свободен': return Colors.green;
      case 'занят': return Colors.orange;
      case 'болеет': return Colors.red;
      case 'в отпуске': return Colors.blue;
      default: return Colors.grey;
    }
  }

  // НОВЫЙ МЕТОД: Получение иконки статуса механика
  IconData _getMechanicStatusIcon(String status) {
    switch (status) {
      case 'свободен': return Icons.check_circle;
      case 'занят': return Icons.work;
      case 'болеет': return Icons.local_hospital;
      case 'в отпуске': return Icons.beach_access;
      default: return Icons.help;
    }
  }

  // НОВЫЙ МЕТОД: Форматирование дат статуса
  String _formatMechanicStatusDates(DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) return '';
    
    final startStr = _formatDate(startDate);
    final endStr = _formatDate(endDate);
    
    return '$startStr - $endStr';
  }

  // Метод для форматирования даты
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
      )
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
          debugPrint('Ошибка декодирования JSON фото: $e');
          photoList = [photoData];
        }
      } else {
        photoList = [photoData];
      }

      return photoList;
    } catch (e) {
      debugPrint('Ошибка получения фотографий транспорта: $e');
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
            _buildDetailRow('Дата создания:', _formatDateTime(request.submittedAt)),
            if (request.closedAt != null)
              _buildDetailRow('Дата закрытия:', _formatDate(request.closedAt!)),
            _buildDetailRow('Сервисный центр:', service.address),
            if (service.workTime.isNotEmpty)
              _buildDetailRow('Время работы:', service.workTime),
            
            const SizedBox(height: 24),
            
            // Перечень проблем
            _buildProblemsList(),
            
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
            
            // Детали ремонта (добавлено для менеджера)
            _buildRepairDetailsSection(),
            
            const SizedBox(height: 24),
            
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
                final status = mechanicStatusData[mechanic.id]?['status'] ?? 'свободен';
                final statusColor = _getMechanicStatusColor(status);
                final statusIcon = _getMechanicStatusIcon(status);
                
                // Форматируем даты если есть
                String datesText = '';
                if ((status == 'болеет' || status == 'в отпуске') && 
                    mechanicStatusData[mechanic.id]?['statusStartDate'] != null &&
                    mechanicStatusData[mechanic.id]?['statusEndDate'] != null) {
                  datesText = _formatMechanicStatusDates(
                    mechanicStatusData[mechanic.id]?['statusStartDate'],
                    mechanicStatusData[mechanic.id]?['statusEndDate'],
                  );
                }
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(mechanic.name[0]),
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(mechanic.name),
                        
                        // Статус механика
                        Row(
                          children: [
                            Icon(
                              statusIcon,
                              size: 14,
                              color: statusColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 12,
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        
                        // Даты если есть
                        if (datesText.isNotEmpty)
                          Text(
                            datesText,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
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

// Модели данных
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
  final String? problemDescription;
  final List<Map<String, dynamic>>? problems;

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
    this.problemDescription,
    this.problems,
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
      problemDescription: json['problemDescription'],
      problems: json['problems'] != null && json['problems'] is List
          ? List<Map<String, dynamic>>.from(json['problems'])
          : null,
    );
  }
}

class Mechanic {
  final int id;
  final String name;
  final String email;
  final String? photo;
  final int serviceId;
  final String? status;
  final DateTime? statusStartDate;
  final DateTime? statusEndDate;

  Mechanic({
    required this.id,
    required this.name,
    required this.email,
    required this.serviceId,
    this.photo,
    this.status,
    this.statusStartDate,
    this.statusEndDate,
  });

  factory Mechanic.fromJson(Map<String, dynamic> json) {
    return Mechanic(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Неизвестно',
      email: json['email'] ?? 'Неизвестно',
      serviceId: json['serviceId'] ?? 0,
      photo: json['photo'],
      status: json['status'],
      statusStartDate: json['statusStartDate'] != null 
        ? DateTime.parse(json['statusStartDate'])
        : null,
      statusEndDate: json['statusEndDate'] != null 
        ? DateTime.parse(json['statusEndDate'])
        : null,
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

// ДОБАВЛЕННЫЙ КЛАСС для деталей ремонта
class RepairDetail {
  final int id;
  final int requestId;
  final int mechanicId;
  final String partName;
  final String? partNumber;
  final double quantity;

  RepairDetail({
    required this.id,
    required this.requestId,
    required this.mechanicId,
    required this.partName,
    this.partNumber,
    required this.quantity,
  });

  factory RepairDetail.fromJson(Map<String, dynamic> json) {
    return RepairDetail(
      id: json['id'] ?? 0,
      requestId: json['requestId'] ?? 0,
      mechanicId: json['mechanicId'] ?? 0,
      partName: json['partName'] ?? '',
      partNumber: json['partNumber'],
      quantity: (json['quantity'] as num).toDouble(),
    );
  }
}