class CafeTable {
  final String id;
  final String cafeId;
  final int tableNumber;
  final String qrToken;
  final DateTime? createdAt;

  CafeTable({
    required this.id,
    required this.cafeId,
    required this.tableNumber,
    required this.qrToken,
    this.createdAt,
  });

  factory CafeTable.fromJson(Map<String, dynamic> json) {
    return CafeTable(
      id: json['id'] as String,
      cafeId: json['cafe_id'] as String? ?? '',
      tableNumber: (json['table_number'] as num?)?.toInt() ?? 1,
      qrToken: json['qr_token'] as String? ?? '',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'table_number': tableNumber,
      'qr_token': qrToken,
    };
  }

  String getCustomerUrl(String baseUrl) {
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$cleanBase/index.html?cafe=$cafeId&table=$qrToken';
  }
}
