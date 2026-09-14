class MenuItem {
  final String id;
  final String cafeId;
  final String name;
  final String? description;
  final String category;
  final double price;
  final double? offerPrice;
  final String? imageUrl;
  final bool isAvailable;
  final DateTime? createdAt;

  MenuItem({
    required this.id,
    required this.cafeId,
    required this.name,
    this.description,
    required this.category,
    required this.price,
    this.offerPrice,
    this.imageUrl,
    this.isAvailable = true,
    this.createdAt,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    final double price = rawPrice is num
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '') ?? 0.0);

    final rawOffer = json['offer_price'];
    final double? offerPrice = rawOffer != null
        ? (rawOffer is num ? rawOffer.toDouble() : double.tryParse(rawOffer.toString()))
        : null;

    return MenuItem(
      id: json['id'] as String? ?? '',
      cafeId: json['cafe_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled Item',
      description: json['description'] as String?,
      category: json['category'] as String? ?? 'General',
      price: price,
      offerPrice: offerPrice,
      imageUrl: json['image_url'] as String?,
      isAvailable: json['is_available'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cafe_id': cafeId,
      'name': name,
      'description': description,
      'category': category,
      'price': price,
      'offer_price': offerPrice,
      'image_url': imageUrl,
      'is_available': isAvailable,
    };
  }

  MenuItem copyWith({
    String? name,
    String? description,
    String? category,
    double? price,
    double? offerPrice,
    bool clearOfferPrice = false,
    String? imageUrl,
    bool? isAvailable,
  }) {
    return MenuItem(
      id: id,
      cafeId: cafeId,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      price: price ?? this.price,
      offerPrice: clearOfferPrice ? null : (offerPrice ?? this.offerPrice),
      imageUrl: imageUrl ?? this.imageUrl,
      isAvailable: isAvailable ?? this.isAvailable,
      createdAt: createdAt,
    );
  }

  double get effectivePrice => (offerPrice != null && offerPrice! < price) ? offerPrice! : price;

  bool get hasOffer => offerPrice != null && offerPrice! < price;

  int get discountPercentage {
    if (!hasOffer || price <= 0) return 0;
    return (((price - offerPrice!) / price) * 100).round();
  }
}
