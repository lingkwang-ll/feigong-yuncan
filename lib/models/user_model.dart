enum UserRole { employee, merchant }

class User {
  final String id;
  final String name;
  final String phone;
  final UserRole role;
  final String? avatarUrl;

  const User({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.avatarUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'role': role.name,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      };

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: (json['nickname'] as String?) ??
            (json['name'] as String?) ??
            '',
        phone: json['phone'] as String,
        role: UserRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => UserRole.employee,
        ),
        avatarUrl: json['avatarUrl'] as String?,
      );

  User copyWith({
    String? id,
    String? name,
    String? phone,
    UserRole? role,
    String? avatarUrl,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
