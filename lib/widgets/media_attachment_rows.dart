import 'dart:io';

import 'package:flutter/material.dart';

abstract final class MediaAttachmentRows {
  static const statusPending = 'pending';
  static const statusUploading = 'uploading';
  static const statusDone = 'done';

  static Map<String, dynamic> pendingPhoto(File file) {
    return {
      'file': file,
      'caption': TextEditingController(),
      'status': statusPending,
    };
  }

  static File file(Map<String, dynamic> row) {
    return row['file'] as File;
  }

  static bool isDone(Map<String, dynamic> row) {
    return row['status'] == statusDone;
  }

  static String? url(Map<String, dynamic> row) {
    final value = row['url']?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  static String captionText(Map<String, dynamic> row) {
    final caption = row['caption'];
    if (caption is TextEditingController) {
      return caption.text;
    }
    return '';
  }

  static TextEditingController captionController(Map<String, dynamic> row) {
    return row['caption'] as TextEditingController;
  }

  static Map<String, dynamic>? uploadedPayload(Map<String, dynamic> row) {
    final existingUrl = url(row);
    if (existingUrl == null) return null;
    return {'url': existingUrl, 'caption': captionText(row)};
  }

  static void markUploading(Map<String, dynamic> row) {
    row['status'] = statusUploading;
  }

  static void markPending(Map<String, dynamic> row) {
    row['status'] = statusPending;
  }

  static void markDone(Map<String, dynamic> row, String url) {
    row['status'] = statusDone;
    row['url'] = url;
  }

  static void disposeCaption(Map<String, dynamic> row) {
    row['caption']?.dispose();
  }

  static void disposeAll(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      disposeCaption(row);
    }
  }

  static List<Map<String, dynamic>> mergeExistingWithUploaded({
    required dynamic existing,
    required List<Map<String, dynamic>> uploaded,
  }) {
    final merged = <Map<String, dynamic>>[];
    if (existing is List) {
      merged.addAll(
        existing.whereType<Map>().map(
          (item) => Map<String, dynamic>.from(item),
        ),
      );
    }
    merged.addAll(uploaded);
    return merged;
  }
}
