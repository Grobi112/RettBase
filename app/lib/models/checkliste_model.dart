import 'package:cloud_firestore/cloud_firestore.dart';

/// Einzelner Punkt innerhalb eines Bereichs (Checkbox, Schalter oder Eingabefeld)
class ChecklisteItem {
  final String id;
  final String label;
  final String type; // 'checkbox' | 'slider' | 'text'
  final bool isRequired;

  ChecklisteItem({
    required this.id,
    required this.label,
    required this.type,
    this.isRequired = false,
  });

  Map<String, dynamic> toMap() => {'id': id, 'label': label, 'type': type, 'required': isRequired};

  factory ChecklisteItem.fromMap(Map<String, dynamic> m) => ChecklisteItem(
        id: m['id']?.toString() ?? '',
        label: m['label']?.toString() ?? '',
        type: m['type']?.toString() ?? 'checkbox',
        isRequired: m['required'] == true,
      );
}

/// Bereich (Section) mit Überschrift und Punkten
class ChecklisteSection {
  final String id;
  final String title;
  final List<ChecklisteItem> items;

  ChecklisteSection({
    required this.id,
    required this.title,
    required this.items,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'items': items.map((i) => i.toMap()).toList(),
      };

  factory ChecklisteSection.fromMap(Map<String, dynamic> m) {
    final itemsRaw = m['items'];
    final items = <ChecklisteItem>[];
    if (itemsRaw is List) {
      for (final x in itemsRaw) {
        if (x is Map) {
          items.add(ChecklisteItem.fromMap(Map<String, dynamic>.from(x)));
        }
      }
    }
    return ChecklisteSection(
      id: m['id']?.toString() ?? '',
      title: m['title']?.toString() ?? '',
      items: items,
    );
  }
}

/// Checkliste – Vorlage mit Bereichen und Punkten
class Checkliste {
  final String id;
  final String title;
  final List<ChecklisteSection> sections;
  final DateTime? createdAt;
  final String? createdBy;

  Checkliste({
    required this.id,
    required this.title,
    required this.sections,
    this.createdAt,
    this.createdBy,
  });

  /// Flache Liste aller Items (für ensureUniqueItemIds und Ausfüllen)
  List<ChecklisteItem> get items {
    final result = <ChecklisteItem>[];
    for (final s in sections) {
      result.addAll(s.items);
    }
    return result;
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'sections': sections.map((s) => s.toMap()).toList(),
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
        'createdBy': createdBy,
      };

  factory Checkliste.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime? createdAt;
    final ca = d['createdAt'];
    if (ca is Timestamp) createdAt = ca.toDate();
    if (ca is DateTime) createdAt = ca;

    final sectionsRaw = d['sections'];
    if (sectionsRaw is List && sectionsRaw.isNotEmpty) {
      final sections = <ChecklisteSection>[];
      for (final x in sectionsRaw) {
        if (x is Map) {
          sections.add(ChecklisteSection.fromMap(Map<String, dynamic>.from(x)));
        }
      }
      return Checkliste(
        id: id,
        title: d['title']?.toString() ?? '',
        sections: sections,
        createdAt: createdAt,
        createdBy: d['createdBy']?.toString(),
      );
    }

    // Rückwärtskompatibilität: alte flache items-Struktur
    final itemsRaw = d['items'];
    final items = <ChecklisteItem>[];
    if (itemsRaw is List) {
      for (final x in itemsRaw) {
        if (x is Map) {
          items.add(ChecklisteItem.fromMap(Map<String, dynamic>.from(x)));
        }
      }
    }
    final sections = _convertFlatItemsToSections(items);
    return Checkliste(
      id: id,
      title: d['title']?.toString() ?? '',
      sections: sections,
      createdAt: createdAt,
      createdBy: d['createdBy']?.toString(),
    );
  }

  static List<ChecklisteSection> _convertFlatItemsToSections(List<ChecklisteItem> flat) {
    if (flat.isEmpty) return [];
    final result = <ChecklisteSection>[];
    var currentTitle = 'Allgemein';
    var currentItems = <ChecklisteItem>[];
    var ts = DateTime.now().millisecondsSinceEpoch;
    for (final item in flat) {
      if (item.type == 'header') {
        if (currentItems.isNotEmpty) {
          result.add(ChecklisteSection(id: '${ts}_${result.length}', title: currentTitle, items: List<ChecklisteItem>.from(currentItems)));
          currentItems = [];
        }
        currentTitle = item.label.trim().isEmpty ? 'Bereich' : item.label.trim();
      } else {
        currentItems.add(item);
      }
    }
    if (currentItems.isNotEmpty || result.isEmpty) {
      result.add(ChecklisteSection(id: '${ts}_${result.length}', title: currentTitle, items: currentItems));
    }
    return result;
  }

  /// Stellt sicher, dass jedes Item eine eindeutige ID hat.
  Checkliste ensureUniqueItemIds() {
    final newSections = <ChecklisteSection>[];
    var globalIdx = 0;
    for (final s in sections) {
      final newItems = <ChecklisteItem>[];
      final ids = s.items.map((i) => i.id).toList();
      final hasDuplicates = ids.length != ids.toSet().length;
      for (var i = 0; i < s.items.length; i++) {
        final item = s.items[i];
        final newId = hasDuplicates ? '${item.id}_$globalIdx' : item.id;
        globalIdx++;
        newItems.add(ChecklisteItem(id: newId, label: item.label, type: item.type, isRequired: item.isRequired));
      }
      newSections.add(ChecklisteSection(id: s.id, title: s.title, items: newItems));
    }
    return Checkliste(id: id, title: title, sections: newSections, createdAt: createdAt, createdBy: createdBy);
  }
}

/// Gespeicherte Ausfüllung einer Checkliste
class ChecklisteAusfuellung {
  final String id;
  final String checklisteId;
  final String checklisteTitel;
  final Map<String, dynamic> values; // itemId -> value (bool, double, String)
  final String? fahrer;
  final String? beifahrer;
  final String? praktikantAzubi;
  final String? kennzeichen;
  final String? standort;
  final String? wachbuchSchicht;
  final int? kmStand;
  /// Snapshot der offenen Mängel zum Zeitpunkt der Ausfüllung
  final List<Map<String, dynamic>>? maengelSnapshot;
  final DateTime? createdAt;
  final String? createdBy;
  final String? createdByName;

  ChecklisteAusfuellung({
    required this.id,
    required this.checklisteId,
    required this.checklisteTitel,
    required this.values,
    this.fahrer,
    this.beifahrer,
    this.praktikantAzubi,
    this.kennzeichen,
    this.standort,
    this.wachbuchSchicht,
    this.kmStand,
    this.maengelSnapshot,
    this.createdAt,
    this.createdBy,
    this.createdByName,
  });

  Map<String, dynamic> toFirestore() => {
        'checklisteId': checklisteId,
        'checklisteTitel': checklisteTitel,
        'values': values,
        if (fahrer != null) 'fahrer': fahrer,
        if (beifahrer != null) 'beifahrer': beifahrer,
        if (praktikantAzubi != null) 'praktikantAzubi': praktikantAzubi,
        if (kennzeichen != null) 'kennzeichen': kennzeichen,
        if (standort != null) 'standort': standort,
        if (wachbuchSchicht != null) 'wachbuchSchicht': wachbuchSchicht,
        if (kmStand != null) 'kmStand': kmStand,
        if (maengelSnapshot != null && maengelSnapshot!.isNotEmpty) 'maengelSnapshot': maengelSnapshot,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'createdByName': createdByName,
      };

  factory ChecklisteAusfuellung.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime? createdAt;
    final ca = d['createdAt'];
    if (ca is Timestamp) createdAt = ca.toDate();
    if (ca is DateTime) createdAt = ca;

    final valuesRaw = d['values'];
    final values = <String, dynamic>{};
    if (valuesRaw is Map) {
      for (final e in valuesRaw.entries) {
        values[e.key.toString()] = e.value;
      }
    }

    return ChecklisteAusfuellung(
      id: id,
      checklisteId: d['checklisteId']?.toString() ?? '',
      checklisteTitel: d['checklisteTitel']?.toString() ?? '',
      values: values,
      fahrer: d['fahrer']?.toString(),
      beifahrer: d['beifahrer']?.toString(),
      praktikantAzubi: d['praktikantAzubi']?.toString(),
      kennzeichen: d['kennzeichen']?.toString(),
      standort: d['standort']?.toString(),
      wachbuchSchicht: d['wachbuchSchicht']?.toString(),
      kmStand: (d['kmStand'] as num?)?.toInt(),
      maengelSnapshot: () {
        final raw = d['maengelSnapshot'];
        if (raw is! List) return null;
        return raw.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
      }(),
      createdAt: createdAt,
      createdBy: d['createdBy']?.toString(),
      createdByName: d['createdByName']?.toString(),
    );
  }
}
