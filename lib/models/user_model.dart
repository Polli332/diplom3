class UserModel {
  final int id;
  final String name;
  final String email;
  final String? photo;
  final String role;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.photo,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: _parseInt(json['id']),
      name: _parseString(json['name']),
      email: _parseString(json['email']),
      photo: _parseNullableString(json['photo']),
      role: _parseString(json['role']),
    );
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String role) {
    return UserModel(
      id: _parseInt(map['id']),
      name: _parseString(map['name']),
      email: _parseString(map['email']),
      photo: _parseNullableString(map['photo']),
      role: _parseString(role),
    );
  }

  // Вспомогательные методы для безопасного парсинга
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }

  static String _parseString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    return value.toString().trim();
  }

  static String? _parseNullableString(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final stringValue = value.toString().trim();
    return stringValue.isEmpty ? null : stringValue;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'photo': photo,
        'role': role,
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'photo': photo,
        'role': role,
      };

  // Методы для копирования объекта с изменениями
  UserModel copyWith({
    int? id,
    String? name,
    String? email,
    String? photo,
    String? role,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      photo: photo ?? this.photo,
      role: role ?? this.role,
    );
  }

  // Метод для проверки равенства объектов
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel &&
        other.id == id &&
        other.name == name &&
        other.email == email &&
        other.photo == photo &&
        other.role == role;
  }

  @override
  int get hashCode {
    return Object.hash(id, name, email, photo, role);
  }

  // Метод для проверки роли пользователя
  bool get isManager => role.toLowerCase() == 'manager';
  bool get isMechanic => role.toLowerCase() == 'mechanic';
  bool get isApplicant => role.toLowerCase() == 'applicant';

  // Метод для получения инициалов (для аватарок)
  String get initials {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  // Метод для проверки валидности пользователя
  bool get isValid => id > 0 && name.isNotEmpty && email.isNotEmpty && role.isNotEmpty;

  @override
  String toString() {
    return 'UserModel{id: $id, name: "$name", email: "$email", role: "$role", photo: ${photo != null ? "[exists]" : "null"}}';
  }
}