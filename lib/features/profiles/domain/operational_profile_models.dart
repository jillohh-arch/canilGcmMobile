import 'package:flutter/material.dart';

class K9ProfileData {
  final String id;
  final String name;
  final String breed;
  final String sex;
  final int age;
  final double weight;
  final String operationalStatus;
  final String photoUrl;
  final List<String> specialties;
  final List<StatusLineData> healthItems;
  final List<DocumentData> documents;
  final List<MiniTimelineEntry> recentActivities;
  final List<MetricData> metrics;

  const K9ProfileData({
    required this.id,
    required this.name,
    required this.breed,
    required this.sex,
    required this.age,
    required this.weight,
    required this.operationalStatus,
    required this.photoUrl,
    required this.specialties,
    required this.healthItems,
    required this.documents,
    required this.recentActivities,
    required this.metrics,
  });
}

class HandlerProfileData {
  final String id;
  final String name;
  final String ra;
  final String role;
  final String unit;
  final String status;
  final String photoUrl;
  final List<String> chips;
  final List<MetricData> metrics;
  final List<LinkedDogData> linkedDogs;
  final List<StatusLineData> permissions;
  final List<MiniTimelineEntry> recentActivities;
  final List<StatusLineData> auditInfo;

  const HandlerProfileData({
    required this.id,
    required this.name,
    required this.ra,
    required this.role,
    required this.unit,
    required this.status,
    required this.photoUrl,
    required this.chips,
    required this.metrics,
    required this.linkedDogs,
    required this.permissions,
    required this.recentActivities,
    required this.auditInfo,
  });
}

class MetricData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const MetricData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class StatusLineData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final IconData? statusIcon;

  const StatusLineData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.statusIcon,
  });
}

class DocumentData {
  final IconData icon;
  final String name;

  const DocumentData({required this.icon, required this.name});
}

class MiniTimelineEntry {
  final String time;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? trailing;

  const MiniTimelineEntry({
    required this.time,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle = '',
    this.trailing,
  });
}

class LinkedDogData {
  final String name;
  final String specialty;
  final String status;
  final String photoUrl;

  const LinkedDogData({
    required this.name,
    required this.specialty,
    required this.status,
    required this.photoUrl,
  });
}
