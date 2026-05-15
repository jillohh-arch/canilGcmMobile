import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

import 'occurrence_event_category.dart';
import 'occurrence_quick_action.dart';

part 'occurrence_event_catalog_approach.dart';
part 'occurrence_event_catalog_dog_search.dart';
part 'occurrence_event_catalog_forwarding.dart';
part 'occurrence_event_catalog_general.dart';
part 'occurrence_event_catalog_material.dart';

class OccurrenceEventCatalog {
  const OccurrenceEventCatalog._();

  static List<OccurrenceEventCategory> categories(Color accent) {
    return [
      _generalEventCategory(accent),
      _approachEventCategory(),
      _dogSearchEventCategory(),
      _materialEventCategory(),
      _forwardingEventCategory(),
    ];
  }
}
