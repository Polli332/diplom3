import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../global_config.dart';

final String baseUrl = GlobalConfig.baseUrl;

// Определяем кастомный цвет
const Color primaryColor = Color(0xFFF5BC38);
const Color primaryColorDark = Color(0xFFD4A22F); // Немного темнее для hover эффектов

// Константа для формы кнопок
const BorderRadius buttonBorderRadius = BorderRadius.all(Radius.circular(8));

class ApplicantMenu extends StatefulWidget {
  const ApplicantMenu({super.key});

  @override
  State<ApplicantMenu> createState() => _ApplicantMenuState();
}

class _ApplicantMenuState extends State<ApplicantMenu> {
  String? userName;
  String? userEmail;
  int? userId;
  String? userPhoto;
  List<Request> requests = [];
  List<Transport> transports = [];
  List<Service> services = [];
  List<Problem> problems = [];
  List<Problem> selectedProblems = [];
  final TextEditingController _customProblemController = TextEditingController();
  bool _showCustomField = false;
  bool _isLoading = true;
   DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  bool _isAccountPanelOpen = false;
  String _sortOrder = 'newest';
  String? _statusFilter;
  String? _transportFilter;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _transportNameController = TextEditingController();
  String _selectedTransportType = 'троллейбусы';
  final TextEditingController _serialController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  int? _selectedServiceId;
  
  final List<String> _selectedPhotosBase64 = [];
  String? _selectedProfilePhotoBase64;
  final ImagePicker _imagePicker = ImagePicker();

  final List<String> _transportTypes = [
    'троллейбусы',
    'электробусы',
    'трамваи',
    'электрогрузовики'
  ];

  final Map<int, List<Mechanic>> _requestMechanics = {};
  final Map<int, List<Map<String, dynamic>>> _requestProblems = {};

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserDataFromServer() async {
    try {
      print('Loading user data from server for user ID: $userId');
      final response = await http.get(
        Uri.parse('$baseUrl/user-data/applicant/$userId'),
      );

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        print('User data loaded from server: $userData');
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', userData['id']);
        await prefs.setString('user_name', userData['name']);
        await prefs.setString('user_email', userData['email']);
        if (userData['photo'] != null) {
          await prefs.setString('user_photo', userData['photo']);
        }
        
        setState(() {
          userName = userData['name'];
          userEmail = userData['email'];
          userPhoto = userData['photo'];
          _nameController.text = userName!;
          _emailController.text = userEmail!;
        });
        
        print('User data saved to SharedPreferences');
      } else {
        print('Failed to load user data from server: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading user data from server: $e');
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userId = prefs.getInt('user_id');
      userName = prefs.getString('user_name') ?? 'Пользователь';
      userEmail = prefs.getString('user_email') ?? 'Email не указан';
      userPhoto = prefs.getString('user_photo');
      
      _nameController.text = userName!;
      _emailController.text = userEmail!;
    });
    
    print('👤 Пользователь из SharedPreferences: ID=$userId, Name=$userName');
    
    if (userId != null && userId! > 0) {
      await _loadUserDataFromServer();
      
      await Future.wait([
        _loadUserRequests(),
        _loadTransports(),
        _loadServices(),
        _loadProblems(),
      ]);
      
      for (var request in requests) {
        await _loadMechanicsForRequest(request.id);
        await _loadProblemsForRequest(request.id);
      }
    }
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadProblems() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/problems'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          problems = data.map((item) => Problem.fromJson(item)).toList();
        });
        print('Загружено проблем: ${problems.length}');
      } else {
        print('Ошибка загрузки проблем: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading problems: $e');
    }
  }

  Future<void> _loadMechanicsForRequest(int requestId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/requests/$requestId/mechanics'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> mechanicsData = data['mechanics'];
        
        setState(() {
          _requestMechanics[requestId] = mechanicsData
              .map((m) => Mechanic.fromJson(m))
              .toList();
        });
      }
    } catch (e) {
      print('Ошибка загрузки механиков для заявки: $e');
    }
  }

  Future<void> _loadProblemsForRequest(int requestId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/requests/$requestId/problems'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> problemsData = data['problems'] ?? [];
        
        setState(() {
          _requestProblems[requestId] = problemsData
              .map((p) => Map<String, dynamic>.from(p))
              .toList();
        });
        
        print('✅ Загружено проблем для заявки $requestId: ${problemsData.length}');
      } else {
        print('⚠️ Ошибка загрузки проблем для заявки $requestId: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка загрузки проблем для заявки: $e');
    }
  }

 Future<void> _loadUserRequests() async {
  try {
    print('📋 Загрузка заявок для заявителя ID: $userId');
    
    final response = await http.get(
      Uri.parse('$baseUrl/requests/applicant/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    
    print('Статус ответа: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      if (response.body.trim().isEmpty || response.body.trim() == 'null') {
        print('⚠️ Сервер вернул пустой ответ');
        setState(() {
          requests = [];
        });
        return;
      }
      
      try {
        final dynamic decoded = json.decode(response.body);
        print('Тип декодированных данных: ${decoded.runtimeType}');
        
        List<Request> loadedRequests = [];
        
        if (decoded is List) {
          print('✅ Ответ является списком, элементов: ${decoded.length}');
          
          for (var item in decoded) {
            try {
              loadedRequests.add(Request.fromJson(item));
            } catch (e) {
              print('⚠️ Ошибка парсинга элемента: $e');
            }
          }
        } else {
          print('⚠️ Ответ не является списком: $decoded');
          loadedRequests = [];
        }
        
        print('✅ Успешно загружено заявок: ${loadedRequests.length}');
        
        setState(() {
          requests = loadedRequests;
        });
        
      } catch (e) {
        print('❌ Ошибка декодирования JSON: $e');
        setState(() {
          requests = [];
        });
      }
    } else {
      print('❌ Ошибка HTTP: ${response.statusCode}');
      setState(() {
        requests = [];
      });
    }
  } catch (e) {
    print('❌ Ошибка загрузки заявок: $e');
    setState(() {
      requests = [];
    });
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
        print('Loaded ${transports.length} transports');
      }
    } catch (e) {
      print('Ошибка загрузки транспорта: $e');
    }
  }

  Future<void> _loadServices() async {
    try {
      print('Loading services...');
      final response = await http.get(Uri.parse('$baseUrl/services'));
      
      print('Services response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('Successfully loaded ${data.length} services');
        
        setState(() {
          services = data.map((item) => Service.fromJson(item)).toList();
        });
      } else {
        print('Failed to load services: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка загрузки сервисов: $e');
    }
  }

  Widget _buildAvatar(String? photoBase64, double radius) {
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      try {
        if (photoBase64.length > 100) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: Colors.white,
            backgroundImage: MemoryImage(base64Decode(photoBase64)),
          );
        }
      } catch (e) {
        print('Error decoding base64 image: $e');
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

  Future<void> _pickMultipleImages() async {
    try {
      print('Начало выбора множественных фото...');
      
      if (kIsWeb) {
        await _pickMultipleImagesWeb();
      } else {
        await _pickMultipleImagesMobile();
      }
    } catch (e) {
      print('Ошибка выбора фото: $e');
      _showError('Ошибка выбора фото: $e');
    }
  }

  Future<void> _pickMultipleImagesWeb() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        for (var file in result.files) {
          if (file.bytes != null) {
            final bytes = file.bytes!;
            final base64Image = base64Encode(bytes);
            
            setState(() {
              _selectedPhotosBase64.add(base64Image);
            });
          }
        }
        _showSuccess('Добавлено ${result.files.length} фото');
      }
    } catch (e) {
      print('Ошибка выбора фото на веб-платформе: $e');
      _showError('Ошибка выбора фото: $e');
    }
  }

  Future<void> _pickMultipleImagesMobile() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      
      if (images.isNotEmpty) {
        for (var image in images) {
          if (kIsWeb) {
            await _pickMultipleImagesWeb();
          } else {
            final bytes = await File(image.path).readAsBytes();
            final base64Image = base64Encode(bytes);
            
            setState(() {
              _selectedPhotosBase64.add(base64Image);
            });
          }
        }
        _showSuccess('Добавлено ${images.length} фото');
      }
    } catch (e) {
      print('Ошибка выбора фото на мобильной платформе: $e');
      _showError('Ошибка выбора фото: $e');
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      print('Начало выбора фото профиля...');
      
      if (kIsWeb) {
        await _pickImageWeb('profile');
      } else {
        await _pickImageMobile('profile');
      }
    } catch (e) {
      print('Ошибка выбора фото профиля: $e');
      _showError('Ошибка выбора фото: $e');
    }
  }

  Future<void> _pickImageWeb(String type) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final base64Image = base64Encode(bytes);
        
        if (type == 'profile') {
          setState(() {
            _selectedProfilePhotoBase64 = base64Image;
          });
          _showSuccess('Фото профиля выбрано');
        }
      }
    } catch (e) {
      print('Ошибка выбора фото на веб-платформе: $e');
      _showError('Ошибка выбора фото: $e');
    }
  }

  Future<void> _pickImageMobile(String type) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      
      if (image != null) {
        if (kIsWeb) {
          await _pickImageWeb(type);
        } else {
          final bytes = await File(image.path).readAsBytes();
          final base64Image = base64Encode(bytes);
          
          if (type == 'profile') {
            setState(() {
              _selectedProfilePhotoBase64 = base64Image;
            });
            _showSuccess('Фото профиля выбрано');
          }
        }
      }
    } catch (e) {
      print('Ошибка выбора фото на мобильной платформе: $e');
      _showError('Ошибка выбора фото: $e');
    }
  }

  void _createRequest() {
    selectedProblems.clear();
    _selectedPhotosBase64.clear();
    _selectedServiceId = null;
    _customProblemController.clear();
    _transportNameController.clear();
    _serialController.clear();
    _modelController.clear();
    _selectedTransportType = 'троллейбусы';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return FractionallySizedBox(
          heightFactor: 0.95,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Создание новой заявки',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Фото транспорта:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildPhotoGrid(setDialogState),
                            const SizedBox(height: 16),
                            
                            _buildProblemsList(setDialogState),
                            const SizedBox(height: 16),
                            
                            const Text(
                              'Выберите сервис:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              initialValue: _selectedServiceId,
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Выберите сервис *'),
                                ),
                                ...services.map((Service service) {
                                  return DropdownMenuItem(
                                    value: service.id,
                                    child: Text('${service.address} (${service.workTime})'),
                                  );
                                }).toList(),
                            ],
                            onChanged: (int? newValue) {
                              setDialogState(() {
                                _selectedServiceId = newValue;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Сервисный центр *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          const Text(
                            'Данные транспорта:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _transportNameController,
                            decoration: const InputDecoration(
                              labelText: 'Название транспорта *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _selectedTransportType,
                            items: _transportTypes.map((String type) {
                              return DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setDialogState(() {
                                _selectedTransportType = newValue!;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Тип транспорта *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _serialController,
                            decoration: const InputDecoration(
                              labelText: 'Серийный номер *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              labelText: 'Модель *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '* - обязательные поля',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      border: const Border(top: BorderSide(color: Colors.grey)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _clearRequestForm();
                              Navigator.of(context).pop();
                            },
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: buttonBorderRadius,
                              ),
                              foregroundColor: Colors.black,
                            ),
                            child: const Text('Отмена'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (_validateRequestForm()) {
                                _addNewRequest();
                                Navigator.of(context).pop();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: buttonBorderRadius,
                              ),
                               foregroundColor: Colors.black,
                            ),
                            child: const Text('Создать заявку'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPhotoGrid(void Function(void Function()) setDialogState) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _selectedPhotosBase64.length + 1,
      itemBuilder: (context, index) {
        if (index == _selectedPhotosBase64.length) {
          return GestureDetector(
            onTap: () => _pickMultipleImages(),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate, color: Colors.grey, size: 40),
                  SizedBox(height: 4),
                  Text('Добавить фото', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          );
        }
        
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: MemoryImage(base64Decode(_selectedPhotosBase64[index])),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  setDialogState(() {
                    _selectedPhotosBase64.removeAt(index);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProblemsList(void Function(void Function()) setDialogState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Выберите проблемы (можно несколько):',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        
        Column(
          children: [
            ...problems.where((p) => p.isOther == false).map((problem) {
              final isSelected = selectedProblems.any((p) => p.id == problem.id);
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: CheckboxListTile(
                  title: Text(problem.name),
                  subtitle: problem.description != null ? Text(problem.description!) : null,
                  value: isSelected,
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        selectedProblems.add(problem);
                      } else {
                        selectedProblems.removeWhere((p) => p.id == problem.id);
                      }
                    });
                  },
                ),
              );
            }).toList(),
            
            // Вместо чекбокса "Другое" теперь показываем текстовое поле
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 12),
                    child: Text(
                      'Другая проблема:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: TextField(
                      controller: _customProblemController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Опишите свою проблему подробно...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        
        if (selectedProblems.isNotEmpty || _customProblemController.text.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Вы выбрали:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...selectedProblems.map((problem) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('• ${problem.name}'),
                );
              }).toList(),
              if (_customProblemController.text.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 4, top: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('• ${_customProblemController.text}'),
                ),
            ],
          ),
      ],
    );
  }

  bool _validateRequestForm() {
    if (selectedProblems.isEmpty && _customProblemController.text.isEmpty) {
      _showError('Выберите хотя бы одну проблему или опишите свою');
      return false;
    }
    if (_selectedServiceId == null) {
      _showError('Выберите сервисный центр');
      return false;
    }
    if (_transportNameController.text.trim().isEmpty) {
      _showError('Введите название транспорта');
      return false;
    }
    if (_serialController.text.trim().isEmpty) {
      _showError('Введите серийный номер');
      return false;
    }
    if (_modelController.text.trim().isEmpty) {
      _showError('Введите модель транспорта');
      return false;
    }
    return true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _addNewRequest() async {
  try {
    print('Starting to create new request with ${_selectedPhotosBase64.length} photos...');
    print('Selected service ID: $_selectedServiceId');

    if (_selectedServiceId == null) {
      _showError('Выберите сервисный центр');
      return;
    }
    if (_transportNameController.text.trim().isEmpty) {
      _showError('Введите название транспорта');
      return;
    }
    if (_serialController.text.trim().isEmpty) {
      _showError('Введите серийный номер');
      return;
    }
    if (_modelController.text.trim().isEmpty) {
      _showError('Введите модель транспорта');
      return;
    }
    
    if (selectedProblems.isEmpty && _customProblemController.text.isEmpty) {
      _showError('Выберите хотя бы одну проблему или опишите свою');
      return;
    }

    final List<int> problemIds = selectedProblems
        .where((p) => p.isOther == false)
        .map((p) => p.id)
        .toList();
    
    final customProblem = _customProblemController.text.isNotEmpty 
        ? _customProblemController.text.trim() 
        : null;
    
    String problemDescription = '';
    
    if (problemIds.isNotEmpty) {
      final selectedProblemsFromList = problems.where((p) => problemIds.contains(p.id)).toList();
      if (selectedProblemsFromList.isNotEmpty) {
        problemDescription = selectedProblemsFromList.map((p) => p.name).join('! ');
      }
    }
    
    if (customProblem != null && customProblem.isNotEmpty) {
      if (problemDescription.isNotEmpty) {
        problemDescription += '! ' + customProblem;
      } else {
        problemDescription = customProblem;
      }
    }
    
    if (problemDescription.isNotEmpty && !problemDescription.endsWith('!')) {
      problemDescription += '!';
    }

    final photosJson = json.encode(_selectedPhotosBase64);

    print('Creating transport...');
    final transportResponse = await http.post(
      Uri.parse('$baseUrl/transports'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'type': _selectedTransportType,
        'serial': _serialController.text.trim(),
        'model': _modelController.text.trim(),
        'photo': photosJson,
      }),
    );

    if (transportResponse.statusCode == 200) {
      final transportData = json.decode(transportResponse.body);
      final transportId = transportData['id'];
      print('✅ Transport created with ID: $transportId');

      print('Creating request...');
      final Map<String, dynamic> requestData = {
        'problemIds': problemIds,
        'customProblem': customProblem,
        'problemDescription': problemDescription,
        'transportId': transportId,
        'applicantId': userId,
        'serviceId': _selectedServiceId,
        'status': 'новая',
      };
      
      print('Sending request data: ${json.encode(requestData)}');
      
      final requestResponse = await http.post(
        Uri.parse('$baseUrl/requests'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestData),
      );

      print('Request response status: ${requestResponse.statusCode}');
      print('Request response body: ${requestResponse.body}');
      
      if (requestResponse.statusCode == 200) {
        try {
          final requestJson = json.decode(requestResponse.body);
          final newRequest = Request.fromJson(requestJson);
          
          // Создаем новый транспорт для этой заявки
          final newTransport = Transport(
            id: transportId,
            type: _selectedTransportType,
            serial: _serialController.text.trim(),
            model: _modelController.text.trim(),
            photo: photosJson,
          );
          
          // Получаем сервис для этой заявки
          final selectedService = services.firstWhere(
            (s) => s.id == _selectedServiceId,
            orElse: () => Service(
              id: 0, 
              address: 'Неизвестно', 
              workTime: '',
            ),
          );
          
          // Загружаем проблемы для новой заявки
          await _loadProblemsForRequest(newRequest.id);
          
          setState(() {
            // Добавляем транспорт в список транспортов
            transports.add(newTransport);
            
            // Добавляем заявку в список
            requests.insert(0, newRequest);
          });
          
          _clearRequestForm();
          _showSuccess('Заявка успешно создана!');
          
          // НЕ вызываем _loadUserRequests(), чтобы не перезагружать весь список
          // Вместо этого сразу показываем детали новой заявки
          _showRequestDetails(newRequest);
          
        } catch (e) {
          print('Error parsing response: $e');
          _showError('Ошибка обработки ответа сервера');
        }
      } else if (requestResponse.statusCode == 400) {
        try {
          final errorData = json.decode(requestResponse.body);
          _showError('Ошибка: ${errorData['error']}');
        } catch (e) {
          _showError('Ошибка валидации: ${requestResponse.body}');
        }
      } else if (requestResponse.statusCode == 404) {
        try {
          final errorData = json.decode(requestResponse.body);
          _showError('Не найдено: ${errorData['error']}');
        } catch (e) {
          _showError('Ресурс не найден');
        }
      } else {
        print('Ошибка создания заявки: ${requestResponse.statusCode}');
        print('Тело ответа: ${requestResponse.body}');
        _showError('Ошибка создания заявки: ${requestResponse.statusCode}');
      }
    } else {
      print('❌ Ошибка создания транспорта: ${transportResponse.statusCode}');
      print('Тело ответа: ${transportResponse.body}');
      _showError('Ошибка создания транспорта: ${transportResponse.statusCode}');
    }
  } catch (e) {
    print('❌ Критическая ошибка создания заявки: $e');
    _showError('Ошибка при создании заявки: ${e.toString()}');
  }
}

  Future<void> _generateInvoice(Request request) async {
    try {
      debugPrint('📝 Генерация PDF чека для заявки: ${request.id}');
      
      if (request.closedAt == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Нельзя сгенерировать чек для незакрытой заявки'),
            ),
          );
        }
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        final response = await http.get(
          Uri.parse('$baseUrl/api/requests/${request.id}/receipt'),
        );

        if (mounted) Navigator.of(context).pop();

        if (response.statusCode == 200) {
          final directory = await getApplicationDocumentsDirectory();
          final filePath = '${directory.path}/receipt-${request.id}-${DateTime.now().millisecondsSinceEpoch}.pdf';

          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);

          debugPrint('✅ PDF чек сохранен: $filePath');

          final result = await OpenFilex.open(filePath);

          debugPrint('Результат открытия файла: ${result.message}');
          debugPrint('Тип: ${result.type}');

          if (result.type != ResultType.done) {
            if (mounted) {
              await _showOpenFileOptions(context, filePath);
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PDF чек успешно сгенерирован'),
                ),
              );
            }
          }
        } 
        else if (response.statusCode == 400) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Заявка не закрыта. Невозможно сгенерировать чек.'),
              ),
            );
          }
        }
        else if (response.statusCode == 404) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Заявка не найдена'),
              ),
            );
          }
        }
        else if (response.statusCode == 500) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ошибка сервера при генерации чека'),
              ),
            );
          }
        }
        else {
          debugPrint('❌ Сервер вернул ${response.statusCode}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка генерации чека: ${response.statusCode}'),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) Navigator.of(context).pop();
        rethrow;
      }
      
    } catch (e) {
      debugPrint('❌ Ошибка генерации PDF чека: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка генерации PDF чека: ${e.toString()}'),
          ),
        );
      }
    }
  }

  Future<void> _showOpenFileOptions(BuildContext context, String filePath) async {
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

  void _showRequestDetails(Request request) {
    // Находим транспорт для этой заявки
    final transport = transports.firstWhere(
      (t) => t.id == request.transportId,
      orElse: () => Transport(id: 0, type: '', serial: '', model: ''),
    );
    
    // Находим сервис для этой заявки
    final service = request.serviceId != null 
        ? services.firstWhere(
            (s) => s.id == request.serviceId,
            orElse: () => Service(id: 0, address: 'Не указан', workTime: ''),
          )
        : Service(id: 0, address: 'Не назначен', workTime: '');
    
    final mechanics = _requestMechanics[request.id] ?? [];
    final requestProblems = _requestProblems[request.id] ?? [];
    
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => RequestDetailsScreen(
          request: request,
          transport: transport,
          service: service,
          mechanics: mechanics,
          requestProblems: requestProblems,
          onGenerateInvoice: () => _generateInvoice(request),
        ),
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

  void _clearRequestForm() {
    selectedProblems.clear();
    _selectedPhotosBase64.clear();
    _customProblemController.clear();
    _transportNameController.clear();
    _serialController.clear();
    _modelController.clear();
    _selectedTransportType = 'троллейбусы';
    _selectedServiceId = null;
    _showCustomField = false;
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

      if (_selectedProfilePhotoBase64 != null) {
        updateData['photo'] = _selectedProfilePhotoBase64;
        print('Updating profile with new photo, length: ${_selectedProfilePhotoBase64!.length}');
      }

      if (_passwordController.text.trim().isNotEmpty) {
        updateData['password'] = _passwordController.text.trim();
      }

      print('Sending update request for user $userId');
      final response = await http.put(
        Uri.parse('$baseUrl/applicants/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updateData),
      );

      print('Update response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_name', _nameController.text.trim());
        await prefs.setString('user_email', _emailController.text.trim());
        if (_selectedProfilePhotoBase64 != null) {
          await prefs.setString('user_photo', _selectedProfilePhotoBase64!);
          print('Photo saved to SharedPreferences');
        }
        
        setState(() {
          userName = _nameController.text.trim();
          userEmail = _emailController.text.trim();
          if (_selectedProfilePhotoBase64 != null) {
            userPhoto = _selectedProfilePhotoBase64;
          }
          _passwordController.clear();
          _selectedProfilePhotoBase64 = null;
        });

        _showSuccess('Профиль успешно обновлен');
      } else {
        print('Server error: ${response.statusCode}, body: ${response.body}');
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      print('Ошибка обновления профиля: $e');
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

  Widget _buildTransportPhotos(String photosJson) {
    try {
      final List<dynamic> photosList = json.decode(photosJson);
      if (photosList.isEmpty) return Container();
      
      return Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: photosList.length,
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(photosList[index]),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error, color: Colors.red, size: 40),
                            SizedBox(height: 8),
                            Text('Ошибка загрузки'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Всего фото: ${photosList.length}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      );
    } catch (e) {
      print('Error parsing transport photos: $e');
      return Container();
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
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

  String _getRequestStatus(Request request) {
    if (request.status == 'временно отклонена' || request.status == 'отклонена') {
      return 'временно отклонена';
    }
    if (request.closedAt != null) return 'закрыта';
    if (request.mechanicId != null) return 'в работе';
    return 'новая';
  }

  Color _getStatusColor(Request request) {
    final status = _getRequestStatus(request);
    switch (status) {
      case 'новая':
        return Colors.blue;
      case 'в работе':
        return Colors.orange;
      case 'закрыта':
        return Colors.green;
      case 'временно отклонена':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getFormattedProblemPreview(String description) {
    String cleanedDescription = description.replaceAll(RegExp(r'!+$'), '');
    List<String> problems = cleanedDescription.split('!').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    
    if (problems.isNotEmpty) {
      return '1. ${problems[0]}';
    }
    
    return 'Проблема не указана';
  }

  List<Request> _getFilteredAndSortedRequests() {
    List<Request> filtered = List.from(requests);

    if (_statusFilter != null) {
      filtered = filtered.where((request) => _getRequestStatus(request) == _statusFilter).toList();
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
                  // Радиокнопки в виде переключаемых кнопок
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
                        ...['новая', 'в работе', 'закрыта', 'временно отклонена'].map((String status) {
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

  Widget _buildRequestCard(Request request) {
  final transport = transports.firstWhere(
    (t) => t.id == request.transportId,
    orElse: () => Transport(id: 0, type: 'Неизвестно', serial: 'Неизвестно', model: 'Неизвестно'),
  );

  final status = _getRequestStatus(request);
  final statusColor = _getStatusColor(request);
  
  final mechanics = _requestMechanics[request.id] ?? [];
  final mechanicsCount = mechanics.length;

  // Извлекаем первое фото, если оно есть
  Uint8List? firstPhotoBytes;
  if (transport.photo != null && transport.photo!.isNotEmpty) {
    try {
      if (transport.photo!.startsWith('[')) {
        // Если фото в формате JSON массива
        final List<dynamic> photosList = json.decode(transport.photo!);
        if (photosList.isNotEmpty && photosList[0] is String) {
          firstPhotoBytes = base64Decode(photosList[0] as String);
        }
      } else {
        // Если фото в формате простой base64 строки
        firstPhotoBytes = base64Decode(transport.photo!);
      }
    } catch (e) {
      print('Error decoding transport photo: $e');
      firstPhotoBytes = null;
    }
  }

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
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
                color: Colors.grey.shade100,
              ),
              child: firstPhotoBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        firstPhotoBytes!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.error, color: Colors.red, size: 24),
                          );
                        },
                      ),
                    )
                  : const Center(
                      child: Icon(Icons.directions_bus, size: 40, color: Colors.grey),
                    ),
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
                      : request.problem.split('\n').first,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
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
                      const Spacer(),
                      if (status == 'закрыта')
                        IconButton(
                          icon: const Icon(Icons.receipt, color: Colors.green),
                          onPressed: () => _generateInvoice(request),
                          tooltip: 'Сгенерировать чек',
                          iconSize: 20,
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

// Метод для обработки выбора статуса механика
Future<void> _selectMechanicStatus(String status) async {
  // Для статусов "болеет" или "отпуск" показываем календарь
  if (status == 'болеет' || status == 'отпуск') {
    _showCalendarDialog(status);
  } else {
    // Для других статусов просто сохраняем
    await _saveMechanicStatus(status);
  }
}

// Метод для простого сохранения статуса без дат
Future<void> _saveMechanicStatus(String status) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final mechanicId = prefs.getInt('user_id');
    
    if (mechanicId == null) {
      _showError('Не удалось определить ID механика');
      return;
    }

    final Map<String, dynamic> statusData = {
      'mechanicId': mechanicId,
      'status': status,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    final response = await http.put(
      Uri.parse('$baseUrl/mechanics/$mechanicId/status'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(statusData),
    );

    if (response.statusCode == 200) {
      _showSuccess('Статус обновлен: $status');
    }
  } catch (e) {
    print('Ошибка сохранения статуса: $e');
    _showError('Ошибка сохранения статуса: $e');
  }
}

// Метод для показа диалога выбора дат
void _showCalendarDialog(String status) {
  DateTime? selectedStartDate;
  DateTime? selectedEndDate;
  
  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Выберите период для "$status"'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Дата начала
                  ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: const Text('Дата начала:'),
                    subtitle: Text(
                      selectedStartDate != null
                          ? DateFormat('dd.MM.yyyy').format(selectedStartDate!)
                          : 'Выберите дату',
                    ),
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedStartDate = picked;
                        });
                      }
                    },
                  ),
                  
                  // Дата окончания
                  ListTile(
                    leading: const Icon(Icons.event_available),
                    title: const Text('Дата окончания:'),
                    subtitle: Text(
                      selectedEndDate != null
                          ? DateFormat('dd.MM.yyyy').format(selectedEndDate!)
                          : 'Выберите дату',
                    ),
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedStartDate ?? DateTime.now(),
                        firstDate: selectedStartDate ?? DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                    
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selectedEndDate = picked;
                        });
                      }
                    },
                  ),
                  
                  // Показ выбранного периода
                  if (selectedStartDate != null && selectedEndDate != null)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Выбранный период:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${DateFormat('dd.MM.yyyy').format(selectedStartDate!)} - ${DateFormat('dd.MM.yyyy').format(selectedEndDate!)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                          Text(
                            '(${(selectedEndDate!.difference(selectedStartDate!).inDays + 1)} дней)',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
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
                onPressed: selectedStartDate != null && selectedEndDate != null
                    ? () async {
                        await _saveMechanicStatusWithPeriod(
                          status, 
                          selectedStartDate!, 
                          selectedEndDate!
                        );
                        Navigator.pop(context);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      );
    },
  );
}

// Метод для сохранения статуса с периодом
Future<void> _saveMechanicStatusWithPeriod(
  String status, 
  DateTime startDate, 
  DateTime endDate
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final mechanicId = prefs.getInt('user_id');
    
    if (mechanicId == null) {
      _showError('Не удалось определить ID механика');
      return;
    }

    final Map<String, dynamic> statusData = {
      'mechanicId': mechanicId,
      'status': status,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
    };

    // Сохраняем локально
    await prefs.setString('mechanic_status_$mechanicId', json.encode(statusData));
    
    // Отправляем на сервер
    final response = await http.post(
      Uri.parse('$baseUrl/mechanics/status'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(statusData),
    );

    if (response.statusCode == 200) {
      _showSuccess('Статус "$status" установлен на период '
          '${DateFormat('dd.MM.yyyy').format(startDate)} - '
          '${DateFormat('dd.MM.yyyy').format(endDate)}');
    }
  } catch (e) {
    print('Ошибка сохранения статуса с периодом: $e');
    _showError('Ошибка сохранения статуса: $e');
  }
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
              decoration: BoxDecoration(
                color: primaryColor,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        /*Text(
                          'Мои заявки',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),*/
                        if (userName != null && userName!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              userName!,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.9),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                      });
                      _loadUserData();
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
                    tooltip: 'Аккаунт',
                  ),
                ],
              ),
            ),
              Expanded(
                child: _isLoading
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
                                  'Создайте первую заявку',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _createRequest,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: buttonBorderRadius,
                                    ),
                                     foregroundColor: Colors.black,
                                  ),
                                  child: const Text('Создать заявку'),
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
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _createRequest,
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add),
          ),
        ),

        if (_isAccountPanelOpen)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 0.8,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    height: 80,
                    padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
                    decoration: BoxDecoration(
                      color: primaryColor,
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
                            onTap: _pickProfileImage,
                            child: Stack(
                              children: [
                                _buildAvatar(
                                  _selectedProfilePhotoBase64 ?? userPhoto, 
                                  50
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: primaryColor,
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
                                backgroundColor: primaryColor,
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
          ),
      ],
    );
  }
}

class RequestDetailsScreen extends StatelessWidget {
  final Request request;
  final Transport transport;
  final Service service;
  final List<Mechanic> mechanics;
  final List<Map<String, dynamic>> requestProblems;
  final VoidCallback onGenerateInvoice;

  const RequestDetailsScreen({
    super.key,
    required this.request,
    required this.transport,
    required this.service,
    required this.mechanics,
    required this.requestProblems,
    required this.onGenerateInvoice,
  });

  String _getRequestStatus(Request request) {
    if (request.closedAt != null) return 'закрыта';
    if (request.mechanicId != null) return 'в работе';
    
    return 'новая';
  }

  Color _getStatusColor(Request request) {
    final status = _getRequestStatus(request);
    switch (status) {
      case 'новая':
        return Colors.blue;
      case 'в работе':
        return Colors.orange;
      case 'закрыта':
        return Colors.green;
      case 'временно отклонена':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  List<Widget> _formatProblemDescription(String description) {
    String cleanedDescription = description.replaceAll(RegExp(r'!+$'), '');
    
    List<String> problems = cleanedDescription.split('!').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    
    return problems.asMap().entries.map((entry) {
      final index = entry.key;
      final problem = entry.value;
      
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: primaryColor.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: primaryColor,
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

  Widget _buildProblemsList() {
    if (requestProblems.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Перечень проблем:',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          ...requestProblems.asMap().entries.map((entry) {
            final index = entry.key;
            final problem = entry.value;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryColor.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: primaryColor,
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
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        ..._formatProblemDescription(problemText),
      ],
    );
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

  

  @override
  Widget build(BuildContext context) {
    final status = _getRequestStatus(request);
    final statusColor = _getStatusColor(request);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Детали заявки #${request.id}'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (status == 'закрыта')
            IconButton(
              icon: const Icon(Icons.receipt),
              onPressed: onGenerateInvoice,
              tooltip: 'Сгенерировать чек',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                        : status == 'временно отклонена'
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
            
            const Text(
              'Основная информация',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
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
                            color: Colors.black87,
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
            
            // ИЗМЕНЕНИЕ: Показываем фото транспорта только если они есть и не пустые
            if (transport.photo != null && transport.photo!.isNotEmpty && transport.photo != '[]')
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'Фото транспорта:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildTransportPhotos(transport.photo!),
                ],
              ),
            
            const Text(
              'Данные транспорта',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Тип транспорта:', transport.type),
            _buildDetailRow('Модель:', transport.model),
            _buildDetailRow('Серийный номер:', transport.serial),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportPhotos(String photosJson) {
    try {
      final List<dynamic> photosList = json.decode(photosJson);
      if (photosList.isEmpty) return Container();
      
      return Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: photosList.length,
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(photosList[index]),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error, color: Colors.red, size: 40),
                            SizedBox(height: 8),
                            Text('Ошибка загрузки'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      );
    } catch (e) {
      print('Error parsing transport photos: $e');
      return Container();
    }
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

class Problem {
  final int id;
  final String name;
  final String? description;
  final bool isActive;
  final bool isOther;
  
  Problem({
    required this.id,
    required this.name,
    this.description,
    required this.isActive,
    required this.isOther,
  });
  
  factory Problem.fromJson(Map<String, dynamic> json) {
    return Problem(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Неизвестно',
      description: json['description'],
      isActive: json['isActive'] ?? true,
      isOther: json['isOther'] ?? false,
    );
  }
  
  static Problem get empty => Problem(
    id: 0,
    name: '',
    isActive: false,
    isOther: false,
  );
}

class Request {
  final int id;
  final String problem;
  final String? problemDescription;
  final DateTime submittedAt;
  final DateTime? closedAt;
  final int transportId;
  final int applicantId;
  final int? mechanicId;
  final int? serviceId;
  final String? rejectionReason;
  final String status;
  final List<Map<String, dynamic>>? problems;

  Request({
    required this.id,
    required this.problem,
    this.problemDescription,
    required this.submittedAt,
    this.closedAt,
    required this.transportId,
    required this.applicantId,
    this.mechanicId,
    this.serviceId,
    this.rejectionReason,
    required this.status,
    this.problems,
  });

  factory Request.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic date) {
      if (date == null) return DateTime.now();
      try {
        if (date is String) {
          return DateTime.parse(date);
        }
        return DateTime.now();
      } catch (e) {
        print('Error parsing date: $date, error: $e');
        return DateTime.now();
      }
    }

    return Request(
      id: json['id'] ?? 0,
      problem: json['problem'] ?? 'Описание не указано',
      problemDescription: json['problemDescription'],
      submittedAt: parseDate(json['submittedAt']),
      closedAt: json['closedAt'] != null ? parseDate(json['closedAt']) : null,
      transportId: json['transportId'] ?? 0,
      applicantId: json['applicantId'] ?? 0,
      mechanicId: json['mechanicId'],
      serviceId: json['serviceId'],
      rejectionReason: json['rejectionReason'],
      status: json['status'] ?? 'новая',
      problems: json['problems'] != null 
        ? List<Map<String, dynamic>>.from(json['problems'])
        : null,
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
    return Service(
      id: json['id'] ?? 0,
      address: json['address'] ?? 'Адрес не указан',
      workTime: json['workTime'] ?? 'Время работы не указано',
      manager: json['manager'] != null ? Manager.fromJson(json['manager']) : null,
      mechanics: json['mechanics'] != null && json['mechanics'] is List
          ? (json['mechanics'] as List).map((i) => Mechanic.fromJson(i)).toList()
          : null,
    );
  }
}

class Manager {
  final int id;
  final String name;

  Manager({required this.id, required this.name});

  factory Manager.fromJson(Map<String, dynamic> json) {
    return Manager(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Неизвестно',
    );
  }
}

class Mechanic {
  final int id;
  final String name;
  final String email;

  Mechanic({required this.id, required this.name, required this.email});

  factory Mechanic.fromJson(Map<String, dynamic> json) {
    return Mechanic(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Неизвестно',
      email: json['email'] ?? 'Неизвестно',
    );
  }  
}