import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class CafeFoodImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  const CafeFoodImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();

    Widget imageWidget;
    if (url == null || url.isEmpty) {
      imageWidget = _buildPlaceholder();
    } else if (url.startsWith('data:image/')) {
      try {
        final commaIdx = url.indexOf(',');
        final base64Data = commaIdx != -1 ? url.substring(commaIdx + 1) : url;
        final Uint8List bytes = base64Decode(base64Data);
        imageWidget = Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => _buildPlaceholder(),
        );
      } catch (e) {
        imageWidget = _buildPlaceholder();
      }
    } else {
      imageWidget = Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _buildPlaceholder(),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder() {
    if (placeholder != null) return placeholder!;
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.restaurant_menu,
          color: Colors.grey.shade400,
          size: (width != null && width! < 50) ? 20 : 28,
        ),
      ),
    );
  }
}
