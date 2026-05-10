// ignore_for_file: invalid_use_of_protected_member

part of 'dynamic_activity_sheet.dart';

extension _DynamicActivitySheetMediaStatus on _DynamicActivitySheetState {
  void _markMediaUploading(Map<String, dynamic> attachment) {
    if (mounted) {
      setState(() => MediaAttachmentRows.markUploading(attachment));
    }
  }

  void _markMediaUploaded(Map<String, dynamic> attachment, String url) {
    if (mounted) {
      setState(() => MediaAttachmentRows.markDone(attachment, url));
    }
  }

  void _markMediaPending(Map<String, dynamic> attachment) {
    if (mounted) {
      setState(() => MediaAttachmentRows.markPending(attachment));
    }
  }
}
