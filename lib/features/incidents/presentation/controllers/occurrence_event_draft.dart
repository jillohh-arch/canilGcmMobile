import 'dart:io';

import 'package:flutter/material.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/core/services/location_resolution_service.dart';

class OccurrenceEventChange {
  final bool delete;
  final IncidentProgressUpdate? update;

  const OccurrenceEventChange.delete() : delete = true, update = null;
  const OccurrenceEventChange.update(this.update) : delete = false;
}

class OccurrenceEventDraft {
  final IncidentProgressUpdate original;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final List<Map<String, dynamic>> attachments;
  final List<File> pendingPhotos = [];

  String location;
  double? latitude;
  double? longitude;

  OccurrenceEventDraft(this.original)
    : titleController = TextEditingController(text: original.title),
      descriptionController = TextEditingController(text: original.description),
      location = original.location ?? '',
      latitude = original.latitude,
      longitude = original.longitude,
      attachments = List<Map<String, dynamic>>.from(original.attachments);

  int get pendingPhotoCount => pendingPhotos.length;

  void addPendingPhotos(List<File> files) {
    pendingPhotos.addAll(files);
  }

  void applyLocation(ResolvedLocation resolvedLocation) {
    location = resolvedLocation.address;
    latitude = resolvedLocation.point.latitude;
    longitude = resolvedLocation.point.longitude;
  }

  void addAttachments(List<Map<String, dynamic>> uploadedAttachments) {
    attachments.addAll(uploadedAttachments);
  }

  IncidentProgressUpdate toProgressUpdate() {
    final title = titleController.text.trim();
    return IncidentProgressUpdate(
      title: title.isEmpty ? original.title : title,
      description: descriptionController.text.trim(),
      timestamp: original.timestamp,
      location: location.trim(),
      latitude: latitude,
      longitude: longitude,
      authorId: original.authorId,
      authorName: original.authorName,
      attachments: attachments,
    );
  }

  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
  }
}
