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
import 'package:open_filex/open_filex.dart';  // Добавьте этот импорт
import 'package:url_launcher/url_launcher.dart';

const String baseUrl = 'https://jvvrlmfl-3000.euw.devtunnels.ms'; 

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
  bool _isAccountPanelOpen = false;
  String _sortOrder = 'newest';
  String? _statusFilter;
  String? _transportFilter;
  bool _isLoading = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _transportNameController = TextEditingController();
  String _selectedTransportType = 'троллейбусы';
  final TextEditingController _serialController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  int? _selectedServiceId;
  
  final List<String> _selectedPhotosBase64 = []; // Множественные фото
  String? _selectedProfilePhotoBase64;
  final ImagePicker _imagePicker = ImagePicker();

  // Список проблем
  final List<String> _problemList = [];
  final TextEditingController _problemController = TextEditingController();

  final List<String> _transportTypes = [
    'троллейбусы',
    'электробусы',
    'трамваи',
    'электрогрузовики'
  ];

  // НОВАЯ ПЕРЕМЕННАЯ: Механики по заявкам
  final Map<int, List<Mechanic>> _requestMechanics = {}; // requestId -> list of mechanics

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Метод для загрузки данных пользователя с сервера
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
  
  // Проверяем, что userId не null
  if (userId != null && userId! > 0) {
    // Загружаем данные с сервера
    await _loadUserDataFromServer();
    
    // Загружаем все данные параллельно
    await Future.wait([
      _loadUserRequests(),   // ← ТЕПЕРЬ ПРАВИЛЬНЫЙ МЕТОД
      _loadTransports(),
      _loadServices(),
    ]);
    
    // Загружаем механиков для каждой заявки
    for (var request in requests) {
      await _loadMechanicsForRequest(request.id);
    }
  }
  
  setState(() {
    _isLoading = false;
  });
}

  // НОВЫЙ МЕТОД: Загрузка механиков для заявки
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

 Future<void> _loadUserRequests() async {
  try {
    print('📋 Загрузка заявок для заявителя ID: $userId');
    
    // Используем правильный эндпоинт для заявок заявителя
    final response = await http.get(
      Uri.parse('$baseUrl/requests/applicant/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    
    print('Статус ответа: ${response.statusCode}');
    print('Тело ответа (первые 500 символов): ${response.body.length > 500 ? response.body.substring(0, 500) + '...' : response.body}');
    
    if (response.statusCode == 200) {
      // Проверяем, не пустой ли ответ
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
          // Ответ - массив
          print('✅ Ответ является списком, элементов: ${decoded.length}');
          
          for (var item in decoded) {
            try {
              loadedRequests.add(Request.fromJson(item));
            } catch (e) {
              print('⚠️ Ошибка парсинга элемента: $e');
            }
          }
        } else {
          // Ответ не массив
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

  // Метод для построения аватарки с обработкой ошибок
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
      backgroundColor: Colors.blue,
      child: Icon(
        Icons.person,
        size: radius,
        color: Colors.white,
      ),
    );
  }

  // Обновленный метод для выбора множественных фото
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

  // Метод для выбора множественных фото на веб-платформе
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

  // Метод для выбора множественных фото на мобильных платформах
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

  // Обновленный метод для выбора фото профиля
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

  // Вспомогательные методы для выбора одиночного фото
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

  // Обновленный метод для создания заявки (полноэкранный диалог)
  void _createRequest() {
    _problemList.clear();
    _selectedPhotosBase64.clear();
    _selectedServiceId = null;
    _problemController.clear();
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
                    // Заголовок
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue,
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
                            // Фото транспорта
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
                            
                            // Список проблем
                            const Text(
                              'Описание проблем (список):',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildProblemList(setDialogState),
                            const SizedBox(height: 16),
                            
                            // Выбор сервиса
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
                            
                            // Данные транспорта
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
                    // Кнопки действий
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        border: Border(top: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _clearRequestForm();
                                Navigator.of(context).pop();
                              },
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
                                backgroundColor: Colors.blue,
                              ),
                              child: const Text('Создать заявку'),
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
        );
      },
    );
  }

  // Виджет для отображения сетки фото
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

  // Виджет для списка проблем
  Widget _buildProblemList(void Function(void Function()) setDialogState) {
    return Column(
      children: [
        // Список добавленных проблем
        if (_problemList.isNotEmpty)
          ..._problemList.asMap().entries.map((entry) {
            final index = entry.key;
            final problem = entry.value;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${index + 1}. $problem'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setDialogState(() {
                        _problemList.removeAt(index);
                      });
                    },
                    iconSize: 20,
                  ),
                ],
              ),
            );
          }),
        
        // Поле для добавления новой проблемы
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _problemController,
                decoration: const InputDecoration(
                  hintText: 'Введите проблему...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add, color: Colors.blue),
              onPressed: () {
                if (_problemController.text.trim().isNotEmpty) {
                  setDialogState(() {
                    _problemList.add(_problemController.text.trim());
                    _problemController.clear();
                  });
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  bool _validateRequestForm() {
    if (_problemList.isEmpty) {
      _showError('Добавьте хотя бы одну проблему');
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

  // Обновленный метод для создания заявки с множественными фото
  Future<void> _addNewRequest() async {
    try {
      print('Starting to create new request with ${_selectedPhotosBase64.length} photos...');
      print('Selected service ID: $_selectedServiceId');

      // Преобразуем список проблем в одну строку
      final problemsText = _problemList.join('\n ');

      // Для множественных фото будем сохранять их в формате JSON массива
      final photosJson = json.encode(_selectedPhotosBase64);

      final transportResponse = await http.post(
        Uri.parse('$baseUrl/transports'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'type': _selectedTransportType,
          'serial': _serialController.text.trim(),
          'model': _modelController.text.trim(),
          'photo': photosJson, // Сохраняем массив фото в формате JSON
        }),
      );

      if (transportResponse.statusCode == 200) {
        final transportData = json.decode(transportResponse.body);
        final transportId = transportData['id'];
        print('Transport created with ID: $transportId');

        final requestResponse = await http.post(
          Uri.parse('$baseUrl/requests'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'problem': problemsText,
            'transportId': transportId,
            'applicantId': userId,
            'mechanicId': null,
            'serviceId': _selectedServiceId,
            'closedAt': null,
            'status': "новая"
          }),
        );

        if (requestResponse.statusCode == 200) {
          final requestData = json.decode(requestResponse.body);
          final newRequest = Request.fromJson(requestData);
          
          setState(() {
            requests.insert(0, newRequest);
          });
          
          _clearRequestForm();
          _showSuccess('Заявка успешно создана!');
          
          await _loadUserRequests();
        } else {
          throw Exception('Failed to create request: ${requestResponse.statusCode}');
        }
      } else {
        throw Exception('Failed to create transport: ${transportResponse.statusCode}');
      }
    } catch (e) {
      print('Ошибка создания заявки: $e');
      _showError('Ошибка при создании заявки: $e');
    }
  }

  // Обновленный метод для генерации чека
  Future<void> _generateInvoice(Request request) async {
    try {
      debugPrint('📝 Генерация PDF чека для заявки: ${request.id}');
      
      // Проверяем, закрыта ли заявка
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

      // Показываем индикатор загрузки
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        // Делаем запрос к серверу для генерации PDF чека
        final response = await http.get(
          Uri.parse('$baseUrl/api/requests/${request.id}/receipt'),
        );

        // Закрываем индикатор
        if (mounted) Navigator.of(context).pop();

        if (response.statusCode == 200) {
          // Сохраняем PDF в директорию документов
          final directory = await getApplicationDocumentsDirectory();
          final filePath = '${directory.path}/receipt-${request.id}-${DateTime.now().millisecondsSinceEpoch}.pdf';

          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);

          debugPrint('✅ PDF чек сохранен: $filePath');

          // Открываем файл через OpenFilex - это вызовет системное окно выбора приложения
          final result = await OpenFilex.open(filePath);

          // Отладочная информация
          debugPrint('Результат открытия файла: ${result.message}');
          debugPrint('Тип: ${result.type}');

          if (result.type != ResultType.done) {
            // Если не удалось открыть, предлагаем альтернативный способ
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
        // Закрываем индикатор в случае ошибки
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

  // Метод для показа опций открытия файла
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
              // Попробуем открыть через url_launcher
              _launchUrl(filePath);
            },
            child: const Text('Открыть в браузере'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Покажем путь к файлу для ручного открытия
              await _showFilePath(context, filePath);
            },
            child: const Text('Показать путь к файлу'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  // Метод для открытия через url_launcher
  Future<void> _launchUrl(String filePath) async {
    final uri = Uri.file(filePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint('Не удалось открыть файл через url_launcher');
    }
  }

  // Метод для показа пути к файлу
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
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  // Метод для показа деталей заявки
  void _showRequestDetails(Request request) {
    // Получаем механиков для этой заявки
    final mechanics = _requestMechanics[request.id] ?? [];
    
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => RequestDetailsScreen(
          request: request,
          transports: transports,
          services: services,
          mechanics: mechanics,
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
    _problemList.clear();
    _selectedPhotosBase64.clear();
    _problemController.clear();
    _transportNameController.clear();
    _serialController.clear();
    _modelController.clear();
    _selectedTransportType = 'троллейбусы';
    _selectedServiceId = null;
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

  // МЕТОД ДЛЯ ОТОБРАЖЕНИЯ МНОЖЕСТВЕННЫХ ФОТО ТРАНСПОРТА
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

  // Обновленная карточка заявки с кнопкой генерации чека
  Widget _buildRequestCard(Request request) {
  final transport = transports.firstWhere(
    (t) => t.id == request.transportId,
    orElse: () => Transport(id: 0, type: 'Неизвестно', serial: 'Неизвестно', model: 'Неизвестно'),
  );

  final status = _getRequestStatus(request);
  final statusColor = _getStatusColor(request);
  
  // Получаем механиков для этой заявки
  final mechanics = _requestMechanics[request.id] ?? [];
  final mechanicsCount = mechanics.length;

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
              child: transport.photo != null && transport.photo!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(transport.photo!.startsWith('[') 
                          ? json.decode(transport.photo!)[0] 
                          : transport.photo!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.error, color: Colors.red),
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
                  // Информация о механиках
                  if (mechanicsCount > 0)
                    /*Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.engineering, size: 14, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(
                            '$mechanicsCount механик${mechanicsCount == 1 ? '' : (mechanicsCount > 1 && mechanicsCount < 5 ? 'а' : 'ов')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[600],
                            ),
                          ),
                        ],
                      ),
                    ),*/
                  const SizedBox(height: 8),
                  // Статус заявки и кнопка чека
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

  @override
  Widget build(BuildContext context) {
    final filteredRequests = _getFilteredAndSortedRequests();

    return Stack(
      children: [
        Scaffold(
          appBar: null, // Убираем AppBar
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
                        'Мои заявки',
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
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add),
          ),
        ),

        // Панель аккаунта
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
                  // Кастомный заголовок для панели аккаунта
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
          ),
      ],
    );
  }
}

// КЛАСС ДЛЯ ЭКРАНА ДЕТАЛЕЙ ЗАЯВКИ ВО ВЕСЬ ЭКРАН
class RequestDetailsScreen extends StatelessWidget {
  final Request request;
  final List<Transport> transports;
  final List<Service> services;
  final List<Mechanic> mechanics;
  final VoidCallback onGenerateInvoice;

  const RequestDetailsScreen({
    super.key,
    required this.request,
    required this.transports,
    required this.services,
    required this.mechanics,
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

    final status = _getRequestStatus(request);
    final statusColor = _getStatusColor(request);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Детали заявки #${request.id}'),
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
            
            // Перечень проблем - ИЗМЕНЕНО: цифры вместо точек
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
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Причина временного отклонения (если заявка отклонена) - ДОБАВЛЕНО
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
            
            // Секция механиков
            /*if (mechanics.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  const Text(
                    'Работающие механики',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...mechanics.map((mechanic) {
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
                  }),
                ],
              ),*/
            
            // Фото транспорта (если есть)
            if (transport.photo != null && transport.photo!.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'Фото транспорта:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildTransportPhotos(transport.photo!),
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
            
            const SizedBox(height: 32),
            
            // Кнопка закрыть
            Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
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

// Обновленная модель Transport для хранения множественных фото
class Transport {
  final int id;
  final String type;
  final String serial;
  final String? photo; // Теперь хранит JSON массив фото
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

// Остальные модели
class Request {
  final int id;
  final String problem;
  final DateTime submittedAt;
  final DateTime? closedAt;
  final int transportId;
  final int applicantId;
  final int? mechanicId;
  final int? serviceId;
  final String? rejectionReason;
  final String status; 

  Request({
    required this.id,
    required this.problem,
    required this.submittedAt,
    this.closedAt,
    required this.transportId,
    required this.applicantId,
    this.mechanicId,
    this.serviceId,
    this.rejectionReason,
    required this.status,
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
      submittedAt: parseDate(json['submittedAt']),
      closedAt: json['closedAt'] != null ? parseDate(json['closedAt']) : null,
      transportId: json['transportId'] ?? 0,
      applicantId: json['applicantId'] ?? 0,
      mechanicId: json['mechanicId'],
      serviceId: json['serviceId'],
      rejectionReason: json['rejectionReason'],
      status: json['status'] ?? 'новая',
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