import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../global_config.dart';

final String baseUrl = GlobalConfig.baseUrl;


class MechanicMenu extends StatefulWidget {
  const MechanicMenu({super.key});

  @override
  State<MechanicMenu> createState() => _MechanicMenuState();
}

class _MechanicMenuState extends State<MechanicMenu> {
  String? userName;
  String? userEmail;
  int? userId;
  int? serviceId;
  String? userPhoto;
  String? serviceAddress;
  List<Request> requests = [];
  List<Transport> transports = [];
  List<Applicant> applicants = [];
  List<Service> services = [];
  List<Mechanic> mechanics = [];
  bool _isAccountPanelOpen = false;
  String _sortOrder = 'newest';
  String? _statusFilter;
  bool _isLoading = true;
  bool _photoLoading = false;
  final TextEditingController _searchController = TextEditingController();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Добавлен список статусов для механика
  final List<String> _statusList = ['новая', 'принята', 'в работе', 'временно отклонена', 'завершена'];
  final Map<int, String> _requestCompletionStatus = {}; // requestId -> "completed" или "not_completed"
  final Map<int, List<RepairDetail>> _repairDetailsByRequest = {}; // requestId -> список деталей ремонта

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Загрузка фото пользователя
  Future<void> _loadUserPhoto() async {
    if (userId == null) return;

    setState(() {
      _photoLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/mechanic/$userId'),
      );

      if (response.statusCode == 200) {
        final mechanicData = json.decode(response.body);

        if (mechanicData['photo'] != null && mechanicData['photo'].isNotEmpty) {
          final String photoBase64 = mechanicData['photo'];

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_photo', photoBase64);

          setState(() {
            userPhoto = photoBase64;
          });
        }
      }
    } catch (e) {
      print('Error loading mechanic photo: $e');
    } finally {
      setState(() {
        _photoLoading = false;
      });
    }
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
      backgroundColor: Colors.green,
      child: Icon(
        Icons.person,
        size: radius,
        color: Colors.white,
      ),
    );
  }

  // Выбор фото
  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final base64Image = base64Encode(bytes);

        await _updateMechanicPhoto(base64Image);
      }
    } catch (e) {
      _showError('Ошибка выбора фото: $e');
    }
  }

  // Обновление фото механика
  Future<void> _updateMechanicPhoto(String base64Image) async {
    setState(() {
      _photoLoading = true;
    });

    try {
      final response = await http.put(
        Uri.parse('$baseUrl/mechanics/$userId'),
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

  // Загрузка данных пользователя
  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        userId = prefs.getInt('user_id');
        userName = prefs.getString('user_name') ?? 'Механик';
        userEmail = prefs.getString('user_email') ?? 'Email не указан';

        _nameController.text = userName!;
        _emailController.text = userEmail!;
      });

      if (userId != null) {
        await _loadUserPhoto();
        await _loadMechanicService();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Ошибка загрузки данных пользователя: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMechanicService() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/mechanic/$userId'));

      if (response.statusCode == 200) {
        final mechanicData = json.decode(response.body);
        setState(() {
          serviceId = mechanicData['serviceId'];
        });

        if (serviceId != null) {
          await _loadServiceDetails();
        }
        await _loadAllData();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
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
      setState(() {
        serviceAddress = 'Адрес не указан';
      });
    }
  }

  Future<void> _loadAllData() async {
    try {
      await Future.wait([
        _loadMechanicRequests(),
        _loadTransports(),
        _loadApplicants(),
        _loadServices(),
        _loadServiceMechanics(),
      ]);
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // Загрузка заявок механика
  Future<void> _loadMechanicRequests() async {
    try {
      print('Загрузка заявок для механика $userId');
      
      // Пробуем два разных эндпоинта
      final urls = [
        Uri.parse('$baseUrl/requests/mechanic/$userId'),
        Uri.parse('$baseUrl/mechanics/$userId/requests'),
        Uri.parse('$baseUrl/mechanics/requests/$userId'),
      ];
      
      http.Response? successfulResponse;
      
      for (var url in urls) {
        try {
          final response = await http.get(url);
          print('Пробуем URL: $url');
          print('Статус: ${response.statusCode}');
          
          if (response.statusCode == 200) {
            successfulResponse = response;
            break;
          }
        } catch (e) {
          print('Ошибка при запросе $url: $e');
        }
      }
      
      if (successfulResponse != null) {
        final List<dynamic> data = json.decode(successfulResponse.body);
        print('Получено заявок: ${data.length}');
        
        setState(() {
          requests = data.map((item) => Request.fromJson(item)).toList();
        });
        
        // Загружаем статус завершения для каждой заявки
        await _loadCompletionStatusForRequests();
        // Загружаем детали ремонта для каждой заявки
        await _loadRepairDetailsForAllRequests();
      } else {
        // Fallback: загружаем все заявки и фильтруем по нескольким условиям
        print('Все эндпоинты не сработали, используем fallback');
        await _loadAllRequestsAndFilterMultiple();
      }
    } catch (e) {
      print('Error loading mechanic requests: $e');
      // Fallback
      await _loadAllRequestsAndFilterMultiple();
    }
  }

  // Fallback метод: загружает все заявки и фильтрует несколькими способами
  Future<void> _loadAllRequestsAndFilterMultiple() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/requests'));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        List<Request> allRequests = data.map((item) => Request.fromJson(item)).toList();

        print('Всего заявок в системе: ${allRequests.length}');
        
        // СПОСОБ 1: Фильтруем по mechanicId (старый способ)
        List<Request> filteredByMechanicId = allRequests.where((request) =>
            request.mechanicId == userId && request.status != 'завершена').toList();
        
        // СПОСОБ 2: Пробуем получить заявки через эндпоинт с механиками
        List<Request> filteredThroughMechanics = [];
        for (var request in allRequests) {
          try {
            final mechanicsResponse = await http.get(
              Uri.parse('$baseUrl/requests/${request.id}/mechanics'),
            );
            
            if (mechanicsResponse.statusCode == 200) {
              final mechanicsData = json.decode(mechanicsResponse.body);
              final List<dynamic> mechanicsList = mechanicsData['mechanics'] ?? [];
              
              bool isAssignedToMe = mechanicsList.any((mechanic) => 
                  mechanic['id'] == userId);
              
              if (isAssignedToMe && request.status != 'завершена') {
                filteredThroughMechanics.add(request);
              }
            }
          } catch (e) {
            print('Ошибка при проверке механиков для заявки ${request.id}: $e');
          }
        }
        
        print('Заявок по mechanicId: ${filteredByMechanicId.length}');
        print('Заявок через эндпоинт механиков: ${filteredThroughMechanics.length}');
        
        // Объединяем оба списка
        Set<Request> combinedSet = {};
        combinedSet.addAll(filteredByMechanicId);
        combinedSet.addAll(filteredThroughMechanics);
        
        setState(() {
          requests = combinedSet.toList();
        });
        
        print('Итоговое количество заявок: ${requests.length}');
      }
    } catch (e) {
      print('Error loading all requests: $e');
    }
  }

  // Загрузка статуса завершения для каждой заявки
  Future<void> _loadCompletionStatusForRequests() async {
    try {
      for (var request in requests) {
        try {
          // Пробуем получить статус завершения
          final response = await http.get(
            Uri.parse('$baseUrl/requests/${request.id}/mechanics/$userId/completion-status'),
          );

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            setState(() {
              _requestCompletionStatus[request.id] = data['status'];
            });
          } else {
            // Если эндпоинт не работает, проверяем по полю status
            if (request.status == 'завершена') {
              setState(() {
                _requestCompletionStatus[request.id] = "completed";
              });
            } else {
              setState(() {
                _requestCompletionStatus[request.id] = "not_completed";
              });
            }
          }
        } catch (e) {
          print('Error loading completion status for request ${request.id}: $e');
          setState(() {
            _requestCompletionStatus[request.id] = "not_completed";
          });
        }
      }
    } catch (e) {
      print('Error loading completion status: $e');
    }
  }

  // Загрузка деталей ремонта для всех заявок
  Future<void> _loadRepairDetailsForAllRequests() async {
    for (var request in requests) {
      await _loadRepairDetailsForRequest(request.id);
    }
  }

  // Загрузка деталей ремонта для конкретной заявки
  Future<void> _loadRepairDetailsForRequest(int requestId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/requests/$requestId/repair-details/mechanic/$userId'),
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
      print('Error loading repair details for request $requestId: $e');
      setState(() {
        _repairDetailsByRequest[requestId] = [];
      });
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

  // Просмотр деталей заявки
  void _showRequestDetails(Request request) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => RequestDetailsScreen(
          request: request,
          transports: transports,
          services: services,
          mechanics: mechanics,
          onCompleteRequest: () => _showCompleteWithDetailsDialog(request),
          onUpdateStatus: () => _showStatusChangeDialog(request),
          onTemporaryReject: () => _temporarilyRejectRequest(request),
          isMechanic: true,
          isCompletedByMe: _requestCompletionStatus[request.id] == "completed",
          repairDetails: _repairDetailsByRequest[request.id] ?? [],
        ),
      ),
    );
  }

  // Диалог для изменения статуса заявки
  void _showStatusChangeDialog(Request request) {
    String selectedStatus = request.status;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Сменить статус'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Выберите новый статус заявки:'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    items: _statusList.map((String status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(status),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setDialogState(() {
                        selectedStatus = newValue!;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Статус',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () {
                    _updateRequestStatus(request, selectedStatus);
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

  // Обновление статуса заявки
  Future<void> _updateRequestStatus(Request request, String newStatus) async {
    try {
      final Map<String, dynamic> updateData = {'status': newStatus};

      if (newStatus == 'завершена') {
        updateData['closedAt'] = DateTime.now().toIso8601String();
      } else if (newStatus == 'новая') {
        updateData['closedAt'] = null;
      }

      final response = await http.put(
        Uri.parse('$baseUrl/requests/${request.id}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updateData),
      );

      if (response.statusCode == 200) {
        await _loadMechanicRequests();
        _showSuccess('Статус заявки обновлен на "$newStatus"');
      } else {
        _showError('Ошибка обновления статуса: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Ошибка обновления статуса: $e');
    }
  }

  // Метод для завершения работы механика над заявкой (с деталями ремонта)
  Future<void> _completeRequest(Request request, List<RepairDetail> details) async {
    try {
      // Проверяем, не завершил ли уже механик эту заявку
      if (_requestCompletionStatus[request.id] == "completed") {
        _showSuccess('Вы уже завершили работу над этой заявкой');
        return;
      }

      // Пробуем несколько эндпоинтов
      bool success = false;
      
      final endpoints = [
        Uri.parse('$baseUrl/requests/${request.id}/mechanics/$userId/complete-with-details'),
        Uri.parse('$baseUrl/mechanic/requests/${request.id}/complete-with-details'),
        Uri.parse('$baseUrl/mechanics/$userId/requests/${request.id}/complete-with-details'),
      ];
      
      for (var endpoint in endpoints) {
        try {
          final response = await http.put(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'repairDetails': details.map((detail) => detail.toJson()).toList(),
            }),
          );

          if (response.statusCode == 200) {
            success = true;
            final data = json.decode(response.body);
            
            // Обновляем статус завершения
            setState(() {
              _requestCompletionStatus[request.id] = "completed";
            });

            // Обновляем список деталей ремонта
            await _loadRepairDetailsForRequest(request.id);

            // Проверяем, завершена ли вся заявка
            if (data['allCompleted'] == true) {
              _showSuccess('Вы завершили работу. Все механики завершили работу, заявка закрыта.');
              // Если вся заявка завершена, обновляем ее статус
              await _updateRequestStatus(request, 'завершена');
            } else {
              _showSuccess('Вы завершили работу над заявкой. Детали ремонта сохранены.');
            }

            // Обновляем список заявок
            await _loadMechanicRequests();

            // Закрываем экран деталей
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            
            break; // Выходим из цикла если успешно
          }
        } catch (e) {
          print('Ошибка при вызове эндпоинта $endpoint: $e');
          continue; // Пробуем следующий эндпоинт
        }
      }
      
      if (!success) {
        // Fallback: пробуем завершить без деталей
        await _completeRequestWithoutDetails(request);
      }
      
    } catch (e) {
      _showError('Ошибка завершения заявки: $e');
    }
  }

  // Fallback: завершение без деталей
  Future<void> _completeRequestWithoutDetails(Request request) async {
    try {
      final endpoints = [
        Uri.parse('$baseUrl/requests/${request.id}/mechanics/$userId/complete'),
        Uri.parse('$baseUrl/mechanic/requests/${request.id}/complete'),
        Uri.parse('$baseUrl/mechanics/$userId/requests/${request.id}/complete'),
      ];
      
      bool success = false;
      
      for (var endpoint in endpoints) {
        try {
          final response = await http.put(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({}),
          );

          if (response.statusCode == 200) {
            success = true;
            final data = json.decode(response.body);
            
            setState(() {
              _requestCompletionStatus[request.id] = "completed";
            });

            if (data['allCompleted'] == true) {
              _showSuccess('Вы завершили работу. Все механики завершили работу, заявка закрыта.');
              await _updateRequestStatus(request, 'завершена');
            } else {
              _showSuccess('Вы завершили работу над заявкой.');
            }

            await _loadMechanicRequests();
            
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            
            break;
          }
        } catch (e) {
          print('Ошибка при вызове эндпоинта $endpoint: $e');
          continue;
        }
      }
      
      if (!success) {
        _showError('Не удалось завершить заявку. Попробуйте еще раз.');
      }
      
    } catch (e) {
      _showError('Ошибка завершения заявки: $e');
    }
  }

  // Диалог завершения работы с деталями ремонта
  void _showCompleteWithDetailsDialog(Request request) {
    final List<RepairDetail> repairDetails = [];
    final TextEditingController partNameController = TextEditingController();
    final TextEditingController partNumberController = TextEditingController();
    final TextEditingController quantityController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Завершить работу с деталями'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Введите детали, использованные при ремонте:'),
                      const SizedBox(height: 16),
                      
                      // Форма для добавления детали
                      TextField(
                        controller: partNameController,
                        decoration: const InputDecoration(
                          labelText: 'Название детали *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: partNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Номер детали (артикул)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: quantityController,
                        decoration: const InputDecoration(
                          labelText: 'Количество *',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Кнопка добавления детали
                      ElevatedButton.icon(
                        onPressed: () {
                          if (partNameController.text.trim().isEmpty) {
                            _showError('Введите название детали');
                            return;
                          }
                          if (quantityController.text.trim().isEmpty) {
                            _showError('Введите количество');
                            return;
                          }
                          
                          final quantity = double.tryParse(quantityController.text.trim());
                          if (quantity == null || quantity <= 0) {
                            _showError('Введите корректное количество');
                            return;
                          }
                          
                          final detail = RepairDetail(
                            partName: partNameController.text.trim(),
                            partNumber: partNumberController.text.trim().isNotEmpty 
                              ? partNumberController.text.trim() 
                              : null,
                            quantity: quantity,
                          );
                          
                          setDialogState(() {
                            repairDetails.add(detail);
                          });
                          
                          // Очищаем поля
                          partNameController.clear();
                          partNumberController.clear();
                          quantityController.clear();
                          
                          _showSuccess('Деталь добавлена');
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить деталь'),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Список добавленных деталей
                      if (repairDetails.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Добавленные детали:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 150,
                              child: ListView.builder(
                                itemCount: repairDetails.length,
                                itemBuilder: (context, index) {
                                  final detail = repairDetails[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    child: ListTile(
                                      title: Text(detail.partName),
                                      subtitle: detail.partNumber != null 
                                        ? Text('Артикул: ${detail.partNumber}')
                                        : null,
                                      trailing: Text('${detail.quantity} шт.'),
                                      leading: IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                        onPressed: () {
                                          setDialogState(() {
                                            repairDetails.removeAt(index);
                                          });
                                        },
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
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (repairDetails.isEmpty) {
                      final bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Подтверждение'),
                          content: const Text('Вы не добавили детали ремонта. Завершить работу без деталей?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Отмена'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Завершить'),
                            ),
                          ],
                        ),
                      );
                      
                      if (confirm == true) {
                        Navigator.of(context).pop(); // Закрыть диалог деталей
                        await _completeRequestWithoutDetails(request);
                      }
                    } else {
                      Navigator.of(context).pop(); // Закрыть диалог деталей
                      await _completeRequest(request, repairDetails);
                    }
                  },
                  child: const Text('Завершить работу'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Метод для временного отклонения заявки
  Future<void> _temporarilyRejectRequest(Request request) async {
    final TextEditingController rejectionController = TextEditingController();

    bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Временное отклонение'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Укажите причину временного отклонения заявки:'),
              const SizedBox(height: 16),
              TextField(
                controller: rejectionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Причина отклонения...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                if (rejectionController.text.trim().isEmpty) {
                  _showError('Укажите причину отклонения');
                  return;
                }
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('Отклонить временно'),
            ),
          ],
        );
      },
    );

    if (result == true && rejectionController.text.trim().isNotEmpty) {
      try {
        final String rejectionReason = rejectionController.text.trim();

        // Пытаемся использовать специальный эндпоинт
        final response = await http.put(
          Uri.parse('$baseUrl/requests/${request.id}/temporary-reject'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'rejectionReason': rejectionReason,
            'status': 'временно отклонена',
          }),
        );

        if (response.statusCode == 200) {
          await _loadMechanicRequests();
          _showSuccess('Заявка временно отклонена');

          // Закрываем экран деталей
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        } else {
          // Пробуем через обычный эндпоинт
          await _temporarilyRejectFallback(request, rejectionReason);
        }
      } catch (e) {
        // Пробуем через обычный эндпоинт
        await _temporarilyRejectFallback(request, rejectionController.text.trim());
      }
    }
  }

  // Fallback метод для временного отклонения
  Future<void> _temporarilyRejectFallback(Request request, String reason) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/requests/${request.id}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'rejectionReason': reason,
          'status': 'временно отклонена',
        }),
      );

      if (response.statusCode == 200) {
        await _loadMechanicRequests();
        _showSuccess('Заявка временно отклонена');

        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else {
        _showError('Ошибка отклонения заявки: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Ошибка отклонения заявки: $e');
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'новая':
        return Colors.blue;
      case 'принята':
        return Colors.orange;
      case 'в работе':
        return Colors.purple;
      case 'завершена':
        return Colors.green;
      case 'временно отклонена':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getRequestStatus(Request request) {
    // Сначала проверяем статус из базы данных
    if (request.status == 'временно отклонена') {
      return 'временно отклонена';
    }
    if (request.closedAt != null) return 'закрыта';
    if (request.mechanicId != null) return 'в работе';
    return 'новая';
  }

  // Получение форматированного описания проблемы для карточки
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

    // Поиск
    if (_searchController.text.isNotEmpty) {
      final searchLower = _searchController.text.toLowerCase();
      filtered = filtered.where((request) {
        return request.problem.toLowerCase().contains(searchLower) ||
            request.status.toLowerCase().contains(searchLower) ||
            _getTransportModel(request.transportId).toLowerCase().contains(searchLower);
      }).toList();
    }

    // Фильтр по статусу
    if (_statusFilter != null) {
      filtered = filtered.where((request) => request.status == _statusFilter).toList();
    }

    // Сортировка
    filtered.sort((a, b) {
      if (_sortOrder == 'newest') {
        return b.submittedAt.compareTo(a.submittedAt);
      } else {
        return a.submittedAt.compareTo(b.submittedAt);
      }
    });

    return filtered;
  }

  String _getTransportModel(int transportId) {
    final transport = transports.firstWhere(
      (t) => t.id == transportId,
      orElse: () => Transport(id: 0, type: 'Неизвестно', model: 'Неизвестно', serial: 'Неизвестно'),
    );
    return transport.model;
  }

  // Карточка заявки
  Widget _buildRequestCard(Request request) {
    final transport = transports.firstWhere(
      (t) => t.id == request.transportId,
      orElse: () => Transport(id: 0, type: 'Неизвестно', serial: 'Неизвестно', model: 'Неизвестно'),
    );

    final status = _getRequestStatus(request);
    final statusColor = _getStatusColor(status);
    final isCompletedByMe = _requestCompletionStatus[request.id] == "completed";

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                            color: Colors.green,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // Используем тот же метод форматирования, что и у менеджера и заявителя
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
                      ],
                    ),
                  ),
                ],
              ),
              
              // Кнопка для завершения работы с деталями
              if (status != 'закрыта' && status != 'временно отклонена' && !isCompletedByMe)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ElevatedButton.icon(
                    onPressed: () => _showCompleteWithDetailsDialog(request),
                    icon: const Icon(Icons.build),
                    label: const Text('Завершить работу с деталями'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),
              
              const SizedBox(height: 8),
              
              // Статус заявки
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

  Transport? _getTransportById(int transportId) {
    try {
      return transports.firstWhere(
        (t) => t.id == transportId,
        orElse: () => Transport(id: 0, type: 'Неизвестно', serial: 'Неизвестно', model: 'Неизвестно'),
      );
    } catch (e) {
      return null;
    }
  }

  void _showSortFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Сортировка и фильтры'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Сортировка по дате:', style: TextStyle(fontWeight: FontWeight.bold)),
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

                const Text('Фильтр по статусу:', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButtonFormField<String>(
                  value: _statusFilter,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Все статусы')),
                    ..._statusList.map((status) => DropdownMenuItem(value: status, child: Text(status))),
                  ],
                  onChanged: (String? newValue) {
                    setState(() => _statusFilter = newValue);
                    Navigator.of(context).pop();
                  },
                  decoration: const InputDecoration(border: OutlineInputBorder()),
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
                  _searchController.clear();
                });
                Navigator.of(context).pop();
              },
              child: const Text('Сбросить'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Применить'),
            ),
          ],
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
        Uri.parse('$baseUrl/mechanics/$userId'),
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  // Панель профиля
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
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.green[700],
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
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
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          userName ?? 'Механик',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          userEmail ?? 'Email не указан',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _isAccountPanelOpen = false),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      onPressed: _logout,
                      tooltip: 'Выйти из аккаунта',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.business, color: Colors.green[700]),
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
                                    color: Colors.green[700],
                                  ),
                                ),
                                Text(
                                  serviceAddress ?? 'Адрес не указан',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Имя',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        )),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        )),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Новый пароль (оставьте пустым, если не хотите менять)',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true),
                    const SizedBox(height: 30),
                    SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _updateProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.green[700],
                            side: BorderSide(color: Colors.green[700]!),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Сохранить изменения',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )),
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
          appBar: AppBar(
            title: const Text('Панель механика'),
            backgroundColor: Colors.green,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadAllData().then((_) => setState(() => _isLoading = false));
                },
                tooltip: 'Обновить',
              ),
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showSortFilterDialog,
                tooltip: 'Сортировка и фильтры',
              ),
              IconButton(
                icon: const Icon(Icons.account_circle),
                onPressed: () => setState(() => _isAccountPanelOpen = true),
                tooltip: 'Профиль',
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Поиск заявок...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) => setState(() {}),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredRequests.isEmpty
                        ? const Center(child: Text('Заявок нет'))
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

// Класс для экрана деталей заявки
class RequestDetailsScreen extends StatelessWidget {
  final Request request;
  final List<Transport> transports;
  final List<Service> services;
  final List<Mechanic> mechanics;
  final VoidCallback onCompleteRequest;
  final VoidCallback onUpdateStatus;
  final VoidCallback onTemporaryReject;
  final bool isMechanic;
  final bool isCompletedByMe;
  final List<RepairDetail> repairDetails;

  const RequestDetailsScreen({
    super.key,
    required this.request,
    required this.transports,
    required this.services,
    required this.mechanics,
    required this.onCompleteRequest,
    required this.onUpdateStatus,
    required this.onTemporaryReject,
    required this.isMechanic,
    required this.isCompletedByMe,
    required this.repairDetails,
  });

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
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green,
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
            color: Colors.green,
          ),
        ),
        const SizedBox(height: 12),
        ..._formatProblemDescription(problemText),
      ],
    );
  }

  // Построение секции с деталями ремонта
  Widget _buildRepairDetailsSection() {
    if (repairDetails.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Использованные детали',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 12),
        ...repairDetails.map((detail) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        detail.partName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      '${detail.quantity} шт.',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                if (detail.partNumber != null && detail.partNumber!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Артикул: ${detail.partNumber}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  String _getRequestStatus(Request request) {
    if (request.status == 'временно отклонена') {
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

    final status = _getRequestStatus(request);
    final statusColor = _getStatusColor(request);

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
                color: Colors.green,
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

            // Перечень проблем
            _buildProblemsList(),

            const SizedBox(height: 24),

            // Детали ремонта (показываем только если есть детали)
            _buildRepairDetailsSection(),

            const SizedBox(height: 24),

            // Причина отклонения (если заявка временно отклонена)
            if (request.status == 'временно отклонена' && request.rejectionReason != null && request.rejectionReason!.isNotEmpty)
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
                      color: Colors.green,
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
                                      Icon(Icons.error, color: Colors.red, size: 40),
                                      SizedBox(height: 8),
                                      Text('Фото ${index + 1}',
                                        style: TextStyle(color: Colors.grey),
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

            // Данные транспорта
            const Text(
              'Данные транспорта',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Тип транспорта:', transport.type),
            _buildDetailRow('Модель:', transport.model),
            _buildDetailRow('Серийный номер:', transport.serial),

            const SizedBox(height: 32),

            // Кнопки действий для механика
            if (isMechanic)
              Column(
                children: [
                  // Индикатор завершения работы
                  if (isCompletedByMe)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Вы уже завершили работу над этой заявкой',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  if (status != 'закрыта' && status != 'временно отклонена' && !isCompletedByMe)
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: onUpdateStatus,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text(
                                  'Сменить статус',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: onTemporaryReject,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text(
                                  'Временно отклонить',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: onCompleteRequest,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text(
                                  'Завершить мою работу',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  if ((status == 'закрыта' || status == 'временно отклонена') && !isCompletedByMe)
                    Column(
                      children: [
                        Center(
                          child: ElevatedButton(
                            onPressed: onUpdateStatus,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            ),
                            child: const Text(
                              'Сменить статус',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                ],
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
  final List<RepairDetail>? repairDetails;

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
    this.repairDetails,
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
      repairDetails: json['repairDetails'] != null
          ? List<RepairDetail>.from(json['repairDetails'].map((x) => RepairDetail.fromJson(x)))
          : null,
    );
  }
}

// Класс для деталей ремонта
class RepairDetail {
  final String partName;
  final String? partNumber;
  final double quantity;
  
  RepairDetail({
    required this.partName,
    this.partNumber,
    required this.quantity,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'partName': partName,
      'partNumber': partNumber,
      'quantity': quantity,
    };
  }
  
  factory RepairDetail.fromJson(Map<String, dynamic> json) {
    return RepairDetail(
      partName: json['partName'] ?? '',
      partNumber: json['partNumber'],
      quantity: (json['quantity'] as num).toDouble(),
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