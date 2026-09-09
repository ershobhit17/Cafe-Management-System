class Cafe {
  final String id;
  final String name;
  final String ownerId;
  final DateTime? createdAt;

  Cafe({
    required this.id,
    required this.name,
    required this.ownerId,
    this.createdAt,
  });

  factory Cafe.fromJson(Map<String, dynamic> json) {
    return Cafe(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'My Cafe',
      ownerId: json['owner_id'] as String? ?? '',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'owner_id': ownerId,
    };
  }
}
