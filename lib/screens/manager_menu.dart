import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
// Убрали неиспользуемый импорт
// import 'package:intl/intl.dart';
import '../global_config.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;

final String baseUrl = GlobalConfig.baseUrl;

// Определение нового цвета
const Color primaryColor = Color(0xFFf5bc38);

// Константа для формы кнопок
const BorderRadius buttonBorderRadius = BorderRadius.all(Radius.circular(8));

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

  final Map<int, List<int>> _selectedMechanicsForRequest = {};
  final Map<int, List<Mechanic>> _assignedMechanicsForRequest = {};
  final Map<int, List<RepairDetail>> _repairDetailsByRequest = {};
  final Map<int, String> _mechanicNames = {};
  
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
  
  final List<String> _mechanicStatuses = [
    'свободен',
    'занят',
    'болеет',
    'в отпуске'
  ];
  
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

  // ==================== ОСНОВНЫЕ МЕТОДЫ ====================

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

  void _setDefaultPhoto() {
    setState(() {
      userPhoto = null;
    });
  }

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
      backgroundColor: primaryColor,
      child: Icon(
        Icons.person,
        size: radius,
        color: Colors.white,
      ),
    );
  }

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

  Future<void> _loadAllData() async {
    try {
      await Future.wait([
        _loadAllRequests(),
        _loadServiceMechanics(),
        _loadTransports(),
        _loadApplicants(),
        _loadServices(),
        _loadMechanicsStatus(),
        _loadMechanicNames(),
      ]);
      
      for (var request in requests) {
        await _loadAssignedMechanicsForRequest(request.id);
        await _loadRepairDetailsForRequest(request.id);
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Ошибка загрузки всех данных: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAllRequests() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/requests'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          requests = data.map((item) => Request.fromJson(item)).toList();
        });
        
        await _checkAndFreeMechanicsFromClosedRequests();
      }
    } catch (e) {
      debugPrint('Error loading requests: $e');
    }
  }

  Future<void> _checkAndFreeMechanicsFromClosedRequests() async {
    for (final request in requests) {
      if (request.closedAt != null) {
        final assignedMechanics = _assignedMechanicsForRequest[request.id];
        
        if (assignedMechanics != null && assignedMechanics.isNotEmpty) {
          for (final mechanic in assignedMechanics) {
            final currentStatus = _mechanicStatusData[mechanic.id]?['status'] ?? 'свободен';
            
            if (currentStatus == 'занят') {
              await _updateMechanicStatusToFree(mechanic.id);
              
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

  Future<void> _loadServiceMechanics() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/mechanics'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        List<Mechanic> allMechanics = data.map((item) => Mechanic.fromJson(item)).toList();
        
        setState(() {
          if (serviceId != null) {
            mechanics = allMechanics.where((mechanic) => mechanic.serviceId == serviceId).toList();
          } else {
            mechanics = allMechanics;
          }
        });
        
        for (final mechanic in mechanics) {
          await _loadMechanicStatus(mechanic.id);
        }
      }
    } catch (e) {
      debugPrint('Error loading mechanics: $e');
    }
  }

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
        
        _checkAndUpdateSingleExpiredStatus(mechanicId);
      }
    } catch (e) {
      debugPrint('Ошибка загрузки статуса механика $mechanicId: $e');
    }
  }

  void _checkAndUpdateSingleExpiredStatus(int mechanicId) {
    final now = DateTime.now();
    final statusData = _mechanicStatusData[mechanicId];
    
    if (statusData != null) {
      final status = statusData['status'] as String?;
      final endDate = statusData['statusEndDate'] as DateTime?;
      
      if ((status == 'болеет' || status == 'в отпуске') && 
          endDate != null && 
          now.isAfter(endDate)) {
        
        setState(() {
          _mechanicStatusData[mechanicId] = {
            'status': 'свободен',
            'statusStartDate': null,
            'statusEndDate': null,
          };
        });
        
        _updateMechanicStatusToFree(mechanicId);
      }
    }
  }

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
        
        _checkAndUpdateExpiredStatuses();
      }
    } catch (e) {
      debugPrint('Ошибка загрузки статусов механиков: $e');
    }
  }

  void _checkAndUpdateExpiredStatuses() {
    final now = DateTime.now();
    
    setState(() {
      for (final entry in _mechanicStatusData.entries) {
        final mechanicId = entry.key;
        final statusData = entry.value;
        final status = statusData['status'] as String?;
        final endDate = statusData['statusEndDate'] as DateTime?;
        
        if ((status == 'болеет' || status == 'в отпуске') && 
            endDate != null && 
            now.isAfter(endDate)) {
          
          _mechanicStatusData[mechanicId] = {
            'status': 'свободен',
            'statusStartDate': null,
            'statusEndDate': null,
          };
          
          _updateMechanicStatusToFree(mechanicId);
        }
      }
    });
  }

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
          
          _selectedMechanicsForRequest[requestId] = mechanicsData
              .map((m) => m['id'] as int)
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки назначенных механиков: $e');
    }
  }

  // ==================== МЕТОДЫ ДЛЯ ОТЧЕТОВ ====================

  Future<void> _generatePartsReport() async {
  try {
    debugPrint('📝 Генерация отчета по деталям за день...');
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final todayRequests = requests.where((request) {
      if (request.closedAt == null) return false;
      final closedDate = DateTime(request.closedAt!.year, request.closedAt!.month, request.closedAt!.day);
      return closedDate == today;
    }).toList();
    
    if (todayRequests.isEmpty) {
      _showError('Нет завершенных заявок за сегодня');
      return;
    }
    
    Map<String, Map<String, dynamic>> partsSummary = {};
    
    for (final request in todayRequests) {
      final repairDetails = _repairDetailsByRequest[request.id] ?? [];
      
      for (final detail in repairDetails) {
        final key = detail.partNumber ?? detail.partName;
        
        if (!partsSummary.containsKey(key)) {
          partsSummary[key] = {
            'name': detail.partName,
            'partNumber': detail.partNumber,
            'totalQuantity': 0.0,
            'mechanics': <String>{},
            'requests': <int>{},
          };
        }
        
        partsSummary[key]!['totalQuantity'] = (partsSummary[key]!['totalQuantity'] as double) + detail.quantity;
        
        final mechanicName = _mechanicNames[detail.mechanicId] ?? 'Неизвестно';
        (partsSummary[key]!['mechanics'] as Set<String>).add(mechanicName);
        (partsSummary[key]!['requests'] as Set<int>).add(request.id);
      }
    }
    
    if (partsSummary.isEmpty) {
      _showError('Нет использованных деталей за сегодня');
      return;
    }
    
    await _generatePartsReportPDF(today, partsSummary, todayRequests.length);
    
  } catch (e) {
    debugPrint('❌ Ошибка генерации отчета: $e');
    _showError('Ошибка генерации отчета: $e');
  }
}

  Future<void> _generatePartsReportPDF(DateTime date, Map<String, Map<String, dynamic>> partsSummary, int totalRequests) async {
  final currentContext = context;
  
  try {
    // Показываем диалог загрузки
    showDialog(
      context: currentContext,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    final partsSummaryFormatted = <String, dynamic>{};
    
    partsSummary.forEach((key, value) {
      partsSummaryFormatted[key] = {
        'name': value['name'],
        'partNumber': value['partNumber'],
        'totalQuantity': value['totalQuantity'],
        'mechanics': (value['mechanics'] as Set<String>).toList(),
        'requests': (value['requests'] as Set<int>).toList(),
      };
    });

    final response = await http.post(
      Uri.parse('$baseUrl/reports/parts-daily'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'date': date.toIso8601String(),
        'serviceId': serviceId,
        'serviceAddress': serviceAddress,
        'partsSummary': partsSummaryFormatted,
        'totalRequests': totalRequests,
      }),
    );

    // Исправлено: проверка mounted перед использованием context
    if (mounted && Navigator.canPop(currentContext)) {
      Navigator.of(currentContext).pop();
    }

    if (response.statusCode == 200) {
      await _saveAndOpenPDF(response.bodyBytes, date);
    } 
    else if (response.statusCode == 400) {
      _showError('Ошибка валидации данных');
    }
    else if (response.statusCode == 404) {
      _showError('Сервис или данные не найдены');
    }
    else if (response.statusCode == 500) {
      _showError('Ошибка сервера при генерации отчета');
    }
    else {
      _showError('Ошибка генерации отчета: ${response.statusCode}');
    }
  } catch (e) {
    if (mounted && Navigator.canPop(currentContext)) {
      Navigator.of(currentContext).pop();
    }
    debugPrint('❌ Ошибка генерации отчета: $e');
    _showError('Ошибка генерации отчета: $e');
  }
}

  Future<void> _saveAndOpenPDF(List<int> bytes, DateTime date) async {
  try {
    debugPrint('💾 Сохранение PDF отчета...');
    
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'parts-report-${_formatDate(date)}.pdf';
    final filePath = '${directory.path}/$fileName';
    
    final file = io.File(filePath);
    await file.writeAsBytes(bytes);
    
    if (mounted) Navigator.of(context).pop();
    
    debugPrint('✅ PDF отчет сохранен: $filePath');

    final result = await OpenFilex.open(filePath);
    
    debugPrint('Результат открытия файла: ${result.message}');
    debugPrint('Тип: ${result.type}');

    if (result.type != ResultType.done) {
      if (mounted) {
        await _showOpenFileOptions(filePath);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF отчет успешно сгенерирован'),
          ),
        );
      }
    }
    
  } catch (e) {
    if (mounted) Navigator.of(context).pop();
    debugPrint('❌ Ошибка сохранения/открытия файла: $e');
    _showError('Ошибка сохранения/открытия файла: $e');
  }
}

Future<void> _showOpenFileOptions(String filePath) async {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Открыть файл'),
      content: const Text('Выберите способ открытия PDF файла:'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            _launchUrl(filePath);
          },
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: buttonBorderRadius,
            ),
          ),
          child: const Text('Открыть в браузере'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            await _showFilePath(context, filePath);
          },
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: buttonBorderRadius,
            ),
          ),
          child: const Text('Показать путь к файлу'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: buttonBorderRadius,
            ),
          ),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}

Future<void> _launchUrl(String filePath) async {
  final uri = Uri.file(filePath);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    debugPrint('Не удалось открыть файл через url_launcher');
  }
}

Future<void> _showFilePath(BuildContext context, String filePath) async {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Путь к файлу'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Файл сохранен по пути:'),
            const SizedBox(height: 10),
            SelectableText(
              filePath,
              style: const TextStyle(
                backgroundColor: Colors.grey,
                color: Colors.black,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            const Text('Вы можете скопировать этот путь и открыть файл вручную.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: buttonBorderRadius,
            ),
          ),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

  // ==================== МЕТОДЫ ДЛЯ МЕХАНИКОВ ====================

  void _showAddMechanicDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Добавить механика',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Text(
                      'Имя механика *',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: _mechanicNameController,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: InputBorder.none,
                          hintText: 'Введите имя',
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    Text(
                      'Email *',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: _mechanicEmailController,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: InputBorder.none,
                          hintText: 'Введите email',
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    Text(
                      'Пароль *',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: _mechanicPasswordController,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: InputBorder.none,
                          hintText: 'Введите пароль',
                        ),
                        obscureText: true,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    Text(
                      'Выбрать фото',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _pickMechanicImage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: buttonBorderRadius,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo, color: Color(0xFFf5bc38)),
                            const SizedBox(width: 8),
                            const Text('Выбрать фото'),
                          ],
                        ),
                      ),
                    ),
                    
                    if (_selectedMechanicPhotoBase64 != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Фото выбрано',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    const SizedBox(height: 8),
                    Text(
                      '* - обязательные поля',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    Row(
                       mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            _clearMechanicForm();
                            Navigator.of(context).pop();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: BorderSide(color: Colors.grey[400]!),
                            shape: RoundedRectangleBorder(
                              borderRadius: buttonBorderRadius,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          child: const Text('Отмена'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            if (_validateMechanicForm()) {
                              _createMechanic();
                              Navigator.of(context).pop();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFf5bc38),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: buttonBorderRadius,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          child: const Text('Создать'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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

  // ЗАМЕНИТЕ весь метод _showMechanicStatusDialog на этот код:

void _showMechanicStatusDialog(Mechanic mechanic) {
  final currentStatus = _mechanicStatusData[mechanic.id]?['status'] ?? 'свободен';
  DateTime? startDate = _mechanicStatusData[mechanic.id]?['statusStartDate'];
  DateTime? endDate = _mechanicStatusData[mechanic.id]?['statusEndDate'];
  
  String? selectedStatus = currentStatus;
  
  // Метод для показа календаря Flutter
  Future<DateTime?> selectDateWithCalendar(BuildContext context, bool isStartDate) async {
    final now = DateTime.now();
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate 
          ? (startDate ?? now) 
          : (endDate ?? (startDate ?? now)),
      firstDate: isStartDate 
          ? now 
          : (startDate ?? now),
      lastDate: DateTime(now.year + 1),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFf5bc38), // Основной цвет
              onPrimary: Colors.black, // Цвет текста на основном цвете
              surface: Colors.white, // Цвет поверхности
              onSurface: Colors.black, // Цвет текста на поверхности
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    
    return picked;
  }
  
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Статус механика',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color(0xFFf5bc38).withValues(alpha: 0.1),
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
                    
                    Text(
                      'Выберите статус:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontSize: 16,
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    ..._mechanicStatuses.map((status) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: selectedStatus == status ? Color(0xFFf5bc38) : Colors.grey[300]!,
                            width: selectedStatus == status ? 2 : 1,
                          ),
                        ),
                        child: ListTile(
                          leading: Radio<String>(
                            value: status,
                            groupValue: selectedStatus,
                            onChanged: (String? value) {
                              setDialogState(() {
                                selectedStatus = value;
                              });
                            },
                            activeColor: Color(0xFFf5bc38),
                          ),
                          title: Text(
                            status,
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: selectedStatus == status ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          onTap: () {
                            setDialogState(() {
                              selectedStatus = status;
                            });
                          },
                        ),
                      );
                    }).toList(),
                    
                    if (selectedStatus == 'болеет' || selectedStatus == 'в отпуске')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          Text(
                            'Период отсутствия:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              fontSize: 16,
                            ),
                          ),
                          
                          const SizedBox(height: 8),
                          
                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey[300]!),
                            ),
                            child: ListTile(
                              leading: Icon(Icons.calendar_today, color: Color(0xFFf5bc38)),
                              title: Text(
                                startDate != null 
                                  ? '${startDate!.day}.${startDate!.month}.${startDate!.year}'
                                  : 'Выберите дату начала',
                                style: TextStyle(
                                  color: startDate != null ? Colors.black : Colors.grey[600],
                                ),
                              ),
                              trailing: const Icon(Icons.arrow_drop_down),
                              onTap: () async {
                                final picked = await selectDateWithCalendar(context, true);
                                if (picked != null) {
                                  setDialogState(() {
                                    startDate = picked;
                                  });
                                }
                              },
                            ),
                          ),

                          Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey[300]!),
                            ),
                            child: ListTile(
                              leading: Icon(Icons.calendar_today, color: Color(0xFFf5bc38)),
                              title: Text(
                                endDate != null 
                                  ? '${endDate!.day}.${endDate!.month}.${endDate!.year}'
                                  : 'Выберите дату окончания',
                                style: TextStyle(
                                  color: endDate != null ? Colors.black : Colors.grey[600],
                                ),
                              ),
                              trailing: const Icon(Icons.arrow_drop_down),
                              onTap: () async {
                                final picked = await selectDateWithCalendar(context, false);
                                if (picked != null) {
                                  setDialogState(() {
                                    endDate = picked;
                                  });
                                }
                              },
                            ),
                          ),
                          
                          if (startDate != null && endDate != null && endDate!.isBefore(startDate!))
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    
                    const SizedBox(height: 24),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black,
                            side: BorderSide(color: Colors.grey[400]!),
                            backgroundColor: Colors.grey[300],
                            shape: RoundedRectangleBorder(
                              borderRadius: buttonBorderRadius,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          child: const Text('Отмена'),
                        ),
                        const SizedBox(width: 12),
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
                            
                            await _updateMechanicStatus(mechanic, selectedStatus!, startDate, endDate);
                            if (mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFf5bc38),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: buttonBorderRadius,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          child: const Text('Сохранить'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

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
        
        await _loadServiceMechanics();
      } else {
        _showError('Ошибка обновления статуса: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Ошибка обновления статуса: $e');
    }
  }

  Color _getMechanicStatusColor(String status) {
    switch (status) {
      case 'свободен': return Colors.green;
      case 'занят': return Colors.orange;
      case 'болеет': return Colors.red;
      case 'в отпуске': return Colors.blue;
      default: return Colors.grey;
    }
  }

  IconData _getMechanicStatusIcon(String status) {
    switch (status) {
      case 'свободен': return Icons.check_circle;
      case 'занят': return Icons.work;
      case 'болеет': return Icons.local_hospital;
      case 'в отпуске': return Icons.beach_access;
      default: return Icons.help;
    }
  }

  String _formatMechanicStatusDates(DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) return '';
    
    final startStr = _formatDate(startDate);
    final endStr = _formatDate(endDate);
    
    return '$startStr - $endStr';
  }

  // ==================== МЕТОДЫ ДЛЯ ЗАЯВОК ====================

  void _showAssignMechanicsDialog(Request request) async {
    await _loadAssignedMechanicsForRequest(request.id);
    
    List<int> selectedMechanicIds = List.from(_selectedMechanicsForRequest[request.id] ?? []);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Назначить механиков',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Выберите механиков для этой заявки:',
                      style: TextStyle(
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
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
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isSelected ? Color(0xFFf5bc38) : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: CheckboxListTile(
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mechanic.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  
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
                              subtitle: Text(
                                mechanic.email,
                                style: const TextStyle(color: Colors.black54),
                              ),
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
                                : null,
                              activeColor: Color(0xFFf5bc38),
                              checkColor: Colors.black,
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          );
                        },
                      ),
                    ),
                    
                    if (_assignedMechanicsForRequest[request.id]?.isNotEmpty ?? false)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          const Text(
                            'Текущие механики:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
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
                                    child: Text(
                                      '• ${mechanic.name}',
                                      style: const TextStyle(color: Colors.black),
                                    ),
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
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: BorderSide(color: Colors.grey[400]!),
                    backgroundColor: Colors.grey[400]!,
                    shape: RoundedRectangleBorder(
                      borderRadius: buttonBorderRadius,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _assignMechanicsToRequest(request, selectedMechanicIds);
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFf5bc38),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: buttonBorderRadius,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
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
        setState(() {
          _selectedMechanicsForRequest[request.id] = mechanicIds;
          _assignedMechanicsForRequest[request.id] = mechanicIds
              .map((id) => mechanics.firstWhere((m) => m.id == id))
              .toList();
        });
        
        for (final mechanicId in mechanicIds) {
          await _updateMechanicStatusToBusy(mechanicId);
        }
        
        await _loadAllRequests();
        
        _showSuccess('${mechanicIds.length} механиков назначено на заявку');
      } else {
        _showError('Ошибка назначения механиков: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Ошибка назначения механиков: $e');
    }
  }

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
        
        await _loadServiceMechanics();
      } else {
        debugPrint('Ошибка обновления статуса механика на "занят": ${response.statusCode}');
      }
    } catch (e) {
        debugPrint('Ошибка обновления статуса механика на "занят": $e');
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

  String _getFormattedProblemPreview(String description) {
    String cleanedDescription = description.replaceAll(RegExp(r'!+$'), '');
    List<String> problems = cleanedDescription.split('!').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    
    if (problems.isNotEmpty) {
      return '1. ${problems[0]}';
    }
    
    return 'Проблема не указана';
  }

  Widget _buildTransportImage(String? photoData) {
    if (photoData == null || photoData.isEmpty) {
      return const Center(
        child: Icon(Icons.directions_bus, size: 40, color: Colors.grey),
      );
    }

    try {
      List<String> photoList = [];
      
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

  Widget _buildRequestCard(Request request) {
    final transport = transports.firstWhere(
      (t) => t.id == request.transportId,
      orElse: () => Transport(id: 0, type: 'Неизвестно', serial: 'Неизвестно', model: 'Неизвестно'),
    );

    final status = _getRequestStatus(request);
    final statusColor = _getStatusColor(status);
    
    final statusBackgroundColor = statusColor.withValues(alpha: 0.1);

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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    Text(
                      transport.model,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (request.problemDescription?.isNotEmpty ?? false) 
                        ? _getFormattedProblemPreview(request.problemDescription!)
                        : _getFormattedProblemPreview(request.problem),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if ((_assignedMechanicsForRequest[request.id]?.length ?? 0) > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Row(
                              children: [
                                Icon(Icons.people, size: 14, color: primaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  '${_assignedMechanicsForRequest[request.id]?.length ?? 0}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        if ((_repairDetailsByRequest[request.id]?.length ?? 0) > 0)
                          Row(
                            children: [
                              Icon(Icons.build_circle, size: 14, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                '${_repairDetailsByRequest[request.id]?.length ?? 0}',
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusBackgroundColor,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          repairDetails: _repairDetailsByRequest[request.id] ?? [],
          mechanicNames: _mechanicNames,
        ),
      ),
    );
  }

  // ==================== МЕТОДЫ ДЛЯ КАРТОЧЕК МЕХАНИКОВ ====================

  Widget _buildMechanicCard(Mechanic mechanic) {
    final status = _mechanicStatusData[mechanic.id]?['status'] ?? 'свободен';
    final statusColor = _getMechanicStatusColor(status);
    final statusIcon = _getMechanicStatusIcon(status);
    
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
            Text(
              mechanic.name,
              style: const TextStyle(color: Colors.black),
            ),
            
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
        subtitle: Text(
          mechanic.email,
          style: const TextStyle(color: Colors.black54),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit, color: Color(0xFFf5bc38)),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFf5bc38),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: buttonBorderRadius,
                    ),
                  ),
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

  // ==================== МЕТОДЫ ДЛЯ СОРТИРОВКИ И ФИЛЬТРАЦИИ ====================

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
                    const SizedBox(height: 8),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _sortOrder = 'newest';
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _sortOrder == 'newest' 
                                ? primaryColor 
                                : Colors.grey[300],
                              foregroundColor: _sortOrder == 'newest' 
                                ? Colors.black 
                                : Colors.grey[700],
                              shape: RoundedRectangleBorder(
                                borderRadius: buttonBorderRadius,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: _sortOrder == 'newest' ? 2 : 0,
                            ),
                            child: const Text('Сначала новые'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _sortOrder = 'oldest';
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _sortOrder == 'oldest' 
                                ? primaryColor 
                                : Colors.grey[300],
                              foregroundColor: _sortOrder == 'oldest' 
                                ? Colors.black 
                                : Colors.grey[700],
                              shape: RoundedRectangleBorder(
                                borderRadius: buttonBorderRadius,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: _sortOrder == 'oldest' ? 2 : 0,
                            ),
                            child: const Text('Сначала старые'),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    
                    const Text(
                      'Фильтр по статусу:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
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
                        },
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    const Text(
                      'Фильтр по механику:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _mechanicFilter,
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
                        },
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    const Text(
                      'Фильтр по типу транспорта:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _transportFilter,
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
                        },
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _sortOrder = 'newest';
                            _statusFilter = null;
                            _mechanicFilter = null;
                            _transportFilter = null;
                          });
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: buttonBorderRadius,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Сбросить'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: buttonBorderRadius,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Закрыть'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==================== МЕТОДЫ ДЛЯ ПРОФИЛЯ ====================

  void _openStatisticsScreen() {
    setState(() {
      _isAccountPanelOpen = false;
    });
    
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StatisticsScreen(
          requests: requests,
        ),
      ),
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

  Widget _buildProfilePanel() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 80,
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFFf5bc38),
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
                                color: Color(0xFFf5bc38),
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
                    if (serviceAddress != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Color(0xFFf5bc38).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.business, color: Color(0xFFf5bc38)),
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
                                      color: Color(0xFFf5bc38),
                                    ),
                                  ),
                                  Text(
                                    serviceAddress!,
                                    style: const TextStyle(fontSize: 14, color: Colors.black),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _openStatisticsScreen,
                          icon: const Icon(Icons.bar_chart),
                          label: const Text('Статистика поломок'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFf5bc38),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: buttonBorderRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _generatePartsReport,
                          icon: const Icon(Icons.assignment),
                          label: const Text('Отчет по деталям за день'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFf5bc38),
                            foregroundColor: const Color.fromARGB(255, 0, 0, 0),
                            shape: RoundedRectangleBorder(
                              borderRadius: buttonBorderRadius,
                            ),
                          ),
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFf5bc38),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: buttonBorderRadius,
                          ),
                        ),
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

  // ==================== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ====================

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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  // Убрали неиспользуемый метод
  // String _formatDateTime(DateTime date) {
  //   return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  // }

  // ==================== BUILD METHOD ====================

  @override
  Widget build(BuildContext context) {
    final filteredRequests = _getFilteredAndSortedRequests();

    return Stack(
      children: [
        Scaffold(
          appBar: null,
          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
                decoration: BoxDecoration(
                  color: Color(0xFFf5bc38),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (userName != null && userName!.isNotEmpty)
                            Text(
                              userName!,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 4),
                          
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                        });
                        _loadAllData().then((_) {
                          if (mounted) {
                            setState(() => _isLoading = false);
                          }
                        });
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
                Container(
                  color: Color(0xFFf5bc38).withValues(alpha: 0.1),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Color(0xFFf5bc38),
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Color(0xFFf5bc38),
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
                      _buildMechanicsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_isAccountPanelOpen)
            Container(
              color: Colors.black54,
            ),

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

// ==================== ОСТАЛЬНЫЕ КЛАССЫ ====================

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
  late Map<String, int> _problemStatistics;
  late Map<String, List<Request>> _problemToRequestsMap;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateProblemStatistics();
  }

  void _calculateProblemStatistics() {
    final problemStatistics = <String, int>{};
    final problemToRequestsMap = <String, List<Request>>{};
    
    for (final request in widget.requests) {
      if (request.problems?.isNotEmpty ?? false) {
        for (final problem in request.problems!) {
          final problemName = problem['name'] ?? 'Неизвестная проблема';
          
          problemStatistics[problemName] = (problemStatistics[problemName] ?? 0) + 1;
          
          if (!problemToRequestsMap.containsKey(problemName)) {
            problemToRequestsMap[problemName] = [];
          }
          problemToRequestsMap[problemName]!.add(request);
        }
      } else {
        final problemText = (request.problemDescription?.isNotEmpty ?? false) 
            ? request.problemDescription! 
            : request.problem;
        
        String cleanedDescription = problemText.replaceAll(RegExp(r'!+$'), '');
        List<String> problems = cleanedDescription.split('!')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        
        if (problems.isNotEmpty) {
          final mainProblem = problems[0];
          problemStatistics[mainProblem] = (problemStatistics[mainProblem] ?? 0) + 1;
          
          if (!problemToRequestsMap.containsKey(mainProblem)) {
            problemToRequestsMap[mainProblem] = [];
          }
          problemToRequestsMap[mainProblem]!.add(request);
        } else {
          final fallbackProblem = 'Общая проблема';
          problemStatistics[fallbackProblem] = (problemStatistics[fallbackProblem] ?? 0) + 1;
          
          if (!problemToRequestsMap.containsKey(fallbackProblem)) {
            problemToRequestsMap[fallbackProblem] = [];
          }
          problemToRequestsMap[fallbackProblem]!.add(request);
        }
      }
    }
    
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Color _getCountColor(int count) {
    if (count == 0) return Colors.grey;
    if (count <= 3) return Colors.green;
    if (count <= 10) return Colors.orange;
    return Colors.red;
  }

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
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: buttonBorderRadius,
                ),
              ),
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
        backgroundColor: Color(0xFFf5bc38),
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _calculateProblemStatistics();
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: buttonBorderRadius,
              ),
            ),
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Color(0xFFf5bc38).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bar_chart, color: Color(0xFFf5bc38)),
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
                                  color: Colors.black,
                                ),
                              ),
                              Text(
                                'Всего различных проблем: ${_problemStatistics.length}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
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
                                          color: Colors.black,
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
                  
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Color(0xFFf5bc38).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.summarize, color: Color(0xFFf5bc38)),
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
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Всего заявок: ${widget.requests.length}',
                                style: const TextStyle(fontSize: 14, color: Colors.black),
                              ),
                              Text(
                                'Уникальных проблем: ${_problemStatistics.length}',
                                style: const TextStyle(fontSize: 14, color: Colors.black),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  if (_problemStatistics.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Гистограмма проблем',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFf5bc38),
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
                                      color: Colors.black,
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
                                        color: Colors.black,
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

// Класс для экрана деталей заявки
class RequestDetailsScreen extends StatelessWidget {
  final Request request;
  final List<Transport> transports;
  final List<Service> services;
  final List<Mechanic> mechanics;
  final List<Mechanic> assignedMechanics;
  final VoidCallback onAssignMechanics;
  final Map<int, Map<String, dynamic>> mechanicStatusData;
  final List<RepairDetail> repairDetails;
  final Map<int, String> mechanicNames;

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
        Text(
          'Детали ремонта',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0xFFf5bc38).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color(0xFFf5bc38).withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Деталь',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Кол-во',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
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
                        color: Colors.black,
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
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.orange),
              ...repairDetails.map((detail) {
                final mechanicName = mechanicNames[detail.mechanicId] ?? 'Неизвестно';
                
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFf5bc38).withValues(alpha: 0.2))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          detail.partName,
                          style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${detail.quantity} шт.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
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
                          style: const TextStyle(fontSize: 12, color: Colors.black),
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
          color: Color(0xFFf5bc38).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Color(0xFFf5bc38).withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Color(0xFFf5bc38),
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
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildProblemsList() {
    if (request.problems?.isNotEmpty ?? false) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Перечень проблем:',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFFf5bc38),
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
                color: Color(0xFFf5bc38).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Color(0xFFf5bc38).withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Color(0xFFf5bc38),
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
                            color: Colors.black,
                          ),
                        ),
                        if (problem['description'] != null && problem['description']!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              problem['description']!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
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
    
    final problemText = (request.problemDescription?.isNotEmpty ?? false) 
        ? request.problemDescription! 
        : request.problem;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Перечень проблем:',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
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

  Color _getMechanicStatusColor(String status) {
    switch (status) {
      case 'свободен': return Colors.green;
      case 'занят': return Colors.orange;
      case 'болеет': return Colors.red;
      case 'в отпуске': return Colors.blue;
      default: return Colors.grey;
    }
  }

  IconData _getMechanicStatusIcon(String status) {
    switch (status) {
      case 'свободен': return Icons.check_circle;
      case 'занят': return Icons.work;
      case 'болеет': return Icons.local_hospital;
      case 'в отпуске': return Icons.beach_access;
      default: return Icons.help;
    }
  }

  String _formatMechanicStatusDates(DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) return '';
    
    final startStr = _formatDate(startDate);
    final endStr = _formatDate(endDate);
    
    return '$startStr - $endStr';
  }

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
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, color: Colors.black),
            ),
          ),
        ],
      )
    );
  }

  List<String> _getTransportPhotos(String? photoData) {
    if (photoData == null || photoData.isEmpty) {
      return [];
    }

    try {
      List<String> photoList = [];
      
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
    
    final transportPhotos = _getTransportPhotos(transport.photo);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Детали заявки #${request.id}',
          style: const TextStyle(color: Colors.black),
        ),
        backgroundColor: Color(0xFFf5bc38),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
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
            
            Text(
              'Основная информация',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
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
            
            _buildProblemsList(),
            
            const SizedBox(height: 24),
            
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
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          request.rejectionReason!,
                          style: const TextStyle(fontSize: 16, color: Colors.black),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            
            _buildRepairDetailsSection(),
            
            const SizedBox(height: 24),
            
            Text(
              'Данные транспорта',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Тип транспорта:', transport.type),
            _buildDetailRow('Модель:', transport.model),
            _buildDetailRow('Серийный номер:', transport.serial),
            
            if (transportPhotos.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    'Фотографии транспорта:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
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
            
            const SizedBox(height: 24),
            Text(
              'Назначенные механики',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            
            if (assignedMechanics.isNotEmpty)
              ...assignedMechanics.map((mechanic) {
                final status = mechanicStatusData[mechanic.id]?['status'] ?? 'свободен';
                final statusColor = _getMechanicStatusColor(status);
                final statusIcon = _getMechanicStatusIcon(status);
                
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
                        Text(
                          mechanic.name,
                          style: const TextStyle(color: Colors.black),
                        ),
                        
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
                    subtitle: Text(
                      mechanic.email,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                );
              }).toList()
            else
              const Text(
                'Механики не назначены',
                style: TextStyle(color: Colors.black),
              ),
            
            const SizedBox(height: 24),
            
            Center(
              child: ElevatedButton(
                onPressed: onAssignMechanics,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFf5bc38),
                  shape: RoundedRectangleBorder(
                    borderRadius: buttonBorderRadius,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text(
                  'Назначить механиков',
                  style: TextStyle(fontSize: 16, color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 16),
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