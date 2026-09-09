import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/menu_item.dart';
import '../../widgets/cafe_food_image.dart';

class FoodPhotoPreset {
  final String title;
  final String category;
  final String url;

  const FoodPhotoPreset({
    required this.title,
    required this.category,
    required this.url,
  });
}

const List<FoodPhotoPreset> kDefaultFoodPresets = [
  // Hot Beverages
  FoodPhotoPreset(
    title: 'Caramel Macchiato',
    category: 'Hot Beverages',
    url: 'https://images.unsplash.com/photo-1485808191679-5f86510681a2?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Hazelnut Cappuccino',
    category: 'Hot Beverages',
    url: 'https://images.unsplash.com/photo-1572442388796-11668a67e53d?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Belgian Hot Chocolate',
    category: 'Hot Beverages',
    url: 'https://images.unsplash.com/photo-1542990253-0d0f5be5f0ed?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Espresso Single / Double',
    category: 'Hot Beverages',
    url: 'https://images.unsplash.com/photo-1510591509098-f4fdc6d0ff04?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Masala Chai / Milk Tea',
    category: 'Hot Beverages',
    url: 'https://images.unsplash.com/photo-1576092768241-dec231879fc3?w=500&auto=format&fit=crop&q=80',
  ),

  // Cold Brews & Beverages
  FoodPhotoPreset(
    title: 'Sweet Cream Cold Brew',
    category: 'Cold Brews',
    url: 'https://images.unsplash.com/photo-1517701550927-30cf4ba1dba5?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Passion Fruit Iced Tea',
    category: 'Cold Brews',
    url: 'https://images.unsplash.com/photo-1556679343-c7306c1976bc?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Mango Frappe',
    category: 'Cold Brews',
    url: 'https://images.unsplash.com/photo-1572490122747-3968b75cc699?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Mint Lime Mojito',
    category: 'Cold Brews',
    url: 'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?w=500&auto=format&fit=crop&q=80',
  ),

  // Artisanal Bites
  FoodPhotoPreset(
    title: 'Pesto Grilled Cheese',
    category: 'Artisanal Bites',
    url: 'https://images.unsplash.com/photo-1528735602780-2552fd46c7af?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Crispy Truffle Fries',
    category: 'Artisanal Bites',
    url: 'https://images.unsplash.com/photo-1576107232684-1279f3908594?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Butter Croissant',
    category: 'Artisanal Bites',
    url: 'https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Garlic Cheese Toast',
    category: 'Artisanal Bites',
    url: 'https://images.unsplash.com/photo-1573140247632-f8fd74997d5c?w=500&auto=format&fit=crop&q=80',
  ),

  // Main Course
  FoodPhotoPreset(
    title: 'Wild Mushroom Pasta',
    category: 'Main Course',
    url: 'https://images.unsplash.com/photo-1621996346565-e3d5d62817d2?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Artisan Margherita Pizza',
    category: 'Main Course',
    url: 'https://images.unsplash.com/photo-1604382355076-af4b0eb60143?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Crispy Veggie / Chicken Burger',
    category: 'Main Course',
    url: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Triple Decker Club Sandwich',
    category: 'Main Course',
    url: 'https://images.unsplash.com/photo-1550547660-d9450f859349?w=500&auto=format&fit=crop&q=80',
  ),

  // Desserts
  FoodPhotoPreset(
    title: 'New York Cheesecake',
    category: 'Desserts',
    url: 'https://images.unsplash.com/photo-1533134242443-d4fd215305ad?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Fudge Brownie Sundae',
    category: 'Desserts',
    url: 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=500&auto=format&fit=crop&q=80',
  ),
  FoodPhotoPreset(
    title: 'Belgian Chocolate Waffles',
    category: 'Desserts',
    url: 'https://images.unsplash.com/photo-1562376552-0d160a2f238d?w=500&auto=format&fit=crop&q=80',
  ),
];

class EditMenuItemDialog extends StatefulWidget {
  final MenuItem? item;
  final String cafeId;
  final List<String> existingCategories;
  final Future<bool> Function({
    String? id,
    required String cafeId,
    required String name,
    String? description,
    required String category,
    required double price,
    double? offerPrice,
    String? imageUrl,
    bool isAvailable,
  }) onSave;

  const EditMenuItemDialog({
    super.key,
    this.item,
    required this.cafeId,
    required this.existingCategories,
    required this.onSave,
  });

  @override
  State<EditMenuItemDialog> createState() => _EditMenuItemDialogState();
}

class _EditMenuItemDialogState extends State<EditMenuItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _categoryController;
  late TextEditingController _priceController;
  late TextEditingController _offerPriceController;
  late TextEditingController _imageController;

  bool _isAvailable = true;
  bool _isUploading = false;
  bool _isSaving = false;

  Uint8List? _pickedImageBytes;
  String? _pickedImageExt;
  String? _currentBase64Url;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _nameController = TextEditingController(text: it?.name ?? '');
    _descController = TextEditingController(text: it?.description ?? '');
    _categoryController = TextEditingController(
      text: it?.category ?? (widget.existingCategories.isNotEmpty ? widget.existingCategories.first : 'General'),
    );
    _priceController = TextEditingController(text: it != null ? it.price.toStringAsFixed(0) : '');
    _offerPriceController = TextEditingController(text: it?.offerPrice != null ? it!.offerPrice!.toStringAsFixed(0) : '');

    final existingImg = it?.imageUrl ?? '';
    if (existingImg.startsWith('data:image')) {
      _currentBase64Url = existingImg;
      _imageController = TextEditingController(text: '');
    } else {
      _currentBase64Url = null;
      _imageController = TextEditingController(text: existingImg);
    }

    _isAvailable = it?.isAvailable ?? true;

    _imageController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _offerPriceController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<Uint8List> _compressImage(Uint8List rawBytes, {int targetWidth = 600}) async {
    try {
      final codec = await ui.instantiateImageCodec(rawBytes, targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Image compression fallback: $e');
    }
    return rawBytes;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() {
        _isUploading = true;
        _uploadError = null;
      });

      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(source: source);

      if (pickedFile == null) {
        setState(() => _isUploading = false);
        return;
      }

      final rawBytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name;
      final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';

      // Compress to 600px width for smooth performance, instant rendering, and low DB footprint
      final compressed = await _compressImage(rawBytes, targetWidth: 600);

      setState(() {
        _pickedImageBytes = compressed;
        _pickedImageExt = ext == 'png' ? 'png' : 'jpeg';
        _currentBase64Url = null;
        _imageController.clear();
        _isUploading = false;
        _uploadError = null;
      });
    } catch (e) {
      debugPrint('Error selecting image: $e');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadError = 'Photo select nahi ho payi: $e';
        });
      }
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Upload Photo (Laptop / Phone)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Select a dish photo from your files or camera',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF3E0),
                  child: Icon(Icons.folder_open, color: Color(0xFFFF7A00)),
                ),
                title: const Text('Browse Files (Laptop / Phone)'),
                subtitle: const Text('Choose JPG, PNG, WebP image from your device'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF3E0),
                  child: Icon(Icons.camera_alt_outlined, color: Color(0xFFFF7A00)),
                ),
                title: const Text('Take Photo with Camera'),
                subtitle: const Text('Capture directly using webcam or phone camera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFoodPresetPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.restaurant_menu, color: Color(0xFFFF7A00)),
                      const SizedBox(width: 8),
                      const Text(
                        'Select Food Photo Preset',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: kDefaultFoodPresets.length,
                    itemBuilder: (context, index) {
                      final preset = kDefaultFoodPresets[index];
                      final isSelected = _imageController.text.trim() == preset.url;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _pickedImageBytes = null;
                            _currentBase64Url = null;
                            _imageController.text = preset.url;
                          });
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFFFF7A00) : Colors.grey.shade300,
                              width: isSelected ? 2.5 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: Image.network(
                                    preset.url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.broken_image, color: Colors.grey),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        preset.title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        preset.category,
                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _uploadError = null;
    });

    String? finalImageUrl;

    if (_pickedImageBytes != null) {
      // 1. Try uploading to Supabase Storage bucket 'menu-items' if available
      bool storageUploaded = false;
      try {
        final client = Supabase.instance.client;
        final ext = _pickedImageExt ?? 'jpeg';
        final fileName = 'cafe_${widget.cafeId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

        await client.storage.from('menu-items').uploadBinary(
          fileName,
          _pickedImageBytes!,
          fileOptions: FileOptions(
            contentType: mimeType,
            upsert: true,
          ),
        );

        finalImageUrl = client.storage.from('menu-items').getPublicUrl(fileName);
        storageUploaded = true;
      } catch (err) {
        debugPrint('Supabase Storage bucket upload bypassed: $err');
      }

      // 2. Fallback: Save compressed base64 data URI directly (zero configuration required)
      if (!storageUploaded) {
        final mime = _pickedImageExt == 'png' ? 'image/png' : 'image/jpeg';
        final b64 = base64Encode(_pickedImageBytes!);
        finalImageUrl = 'data:$mime;base64,$b64';
      }
    } else if (_currentBase64Url != null && _currentBase64Url!.isNotEmpty) {
      finalImageUrl = _currentBase64Url;
    } else if (_imageController.text.trim().isNotEmpty) {
      finalImageUrl = _imageController.text.trim();
    }

    final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
    final offerPriceText = _offerPriceController.text.trim();
    final offerPrice = offerPriceText.isNotEmpty ? double.tryParse(offerPriceText) : null;

    try {
      final success = await widget.onSave(
        id: widget.item?.id,
        cafeId: widget.cafeId,
        name: _nameController.text.trim(),
        description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
        category: _categoryController.text.trim().isNotEmpty ? _categoryController.text.trim() : 'General',
        price: price,
        offerPrice: offerPrice,
        imageUrl: finalImageUrl,
        isAvailable: _isAvailable,
      );

      if (!mounted) return;

      if (success != false) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _isSaving = false;
          _uploadError = 'Dish save karne me issue hua. Please try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _uploadError = 'Error saving dish: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;
    final manualUrl = _imageController.text.trim();

    return AlertDialog(
      title: Text(
        isEditing ? 'Edit Menu Item' : 'Add Menu Item',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Error banner if any
                if (_uploadError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _uploadError!,
                            style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Item Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Item Name *', border: OutlineInputBorder()),
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Item name required' : null,
                ),
                const SizedBox(height: 12),

                // Category
                TextFormField(
                  controller: _categoryController,
                  decoration: InputDecoration(
                    labelText: 'Category *',
                    border: const OutlineInputBorder(),
                    helperText: 'e.g. Hot Beverages, Artisanal Bites, Desserts',
                    suffixIcon: PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down),
                      onSelected: (cat) => setState(() => _categoryController.text = cat),
                      itemBuilder: (_) => widget.existingCategories.map((c) => PopupMenuItem(value: c, child: Text(c))).toList(),
                    ),
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Category required' : null,
                ),
                const SizedBox(height: 12),

                // Pricing Row
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Regular Price (₹) *', border: OutlineInputBorder()),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Price required';
                          final p = double.tryParse(val.trim());
                          if (p == null || p < 0) return 'Invalid price';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _offerPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Offer Price (₹)',
                          helperText: 'Optional discount',
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) {
                          if (val != null && val.trim().isNotEmpty) {
                            final op = double.tryParse(val.trim());
                            final rp = double.tryParse(_priceController.text.trim()) ?? 0;
                            if (op == null || op < 0) return 'Invalid offer';
                            if (op >= rp && rp > 0) return 'Must be < regular';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Short Description
                TextFormField(
                  controller: _descController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Short Description', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),

                // IMAGE SELECTION & LIVE PREVIEW
                const Text('Dish Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 6),
                Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _isUploading
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Color(0xFFFF7A00)),
                              SizedBox(height: 10),
                              Text('Processing image...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        )
                      : (_pickedImageBytes != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(_pickedImageBytes!, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.black54,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.close, color: Colors.white, size: 16),
                                      onPressed: () => setState(() => _pickedImageBytes = null),
                                      tooltip: 'Remove photo',
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Device Photo Selected',
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : (_currentBase64Url != null && _currentBase64Url!.isNotEmpty)
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CafeFoodImage(
                                      imageUrl: _currentBase64Url!,
                                      fit: BoxFit.cover,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: Colors.black54,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.close, color: Colors.white, size: 16),
                                          onPressed: () => setState(() => _currentBase64Url = null),
                                          tooltip: 'Remove photo',
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : (manualUrl.isNotEmpty
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        CafeFoodImage(
                                          imageUrl: manualUrl,
                                          fit: BoxFit.cover,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: CircleAvatar(
                                            radius: 16,
                                            backgroundColor: Colors.black54,
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              icon: const Icon(Icons.close, color: Colors.white, size: 16),
                                              onPressed: () => setState(() => _imageController.clear()),
                                              tooltip: 'Remove photo',
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_photo_alternate_outlined, size: 40, color: Colors.grey.shade400),
                                          const SizedBox(height: 6),
                                          Text(
                                            'No photo selected',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Select photo from laptop/phone, pick preset, or enter link',
                                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ))),
                ),
                const SizedBox(height: 10),

                // Photo Action Buttons (Device Upload + Presets)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.file_upload_outlined, size: 18),
                        label: const Text('Upload Photo (Laptop / Phone)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF7A00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: (_isUploading || _isSaving) ? null : _showImageSourceSheet,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.photo_library_outlined, size: 18, color: Color(0xFFFF7A00)),
                        label: const Text('Food Presets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF7A00),
                          side: const BorderSide(color: Color(0xFFFF7A00)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: (_isUploading || _isSaving) ? null : _showFoodPresetPicker,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Manual URL Input
                TextFormField(
                  controller: _imageController,
                  decoration: InputDecoration(
                    labelText: 'Or Paste Direct Image Link',
                    hintText: 'https://...',
                    helperText: 'Web image URL (Unsplash, Supabase CDN, etc.)',
                    border: const OutlineInputBorder(),
                    suffixIcon: manualUrl.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _imageController.clear()),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),

                // Stock Availability Switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available in Stock', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_isAvailable ? 'Customers can order this dish' : 'Displays "Out of Stock" on digital menu'),
                  value: _isAvailable,
                  activeThumbColor: const Color(0xFFFF7A00),
                  onChanged: (val) => setState(() => _isAvailable = val),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_isUploading || _isSaving) ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF7A00),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(isEditing ? 'Save Changes' : 'Create Item'),
        ),
      ],
    );
  }
}
