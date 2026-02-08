import 'package:cloud_firestore/cloud_firestore.dart';

/// Ordner im Dokumentenmanager
/// Firestore: kunden/{companyId}/dokumente_ordner/{folderId}
class DokumenteOrdner {
  final String id;
  final String name;
  final String? parentId; // null = Root
  final String companyId;
  final DateTime createdAt;
  final String createdBy;
  final int order; // Sortierreihenfolge (niedriger = weiter oben)

  DokumenteOrdner({
    required this.id,
    required this.name,
    this.parentId,
    required this.companyId,
    required this.createdAt,
    required this.createdBy,
    this.order = 0,
  });

  factory DokumenteOrdner.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime createdAt = DateTime.now();
    final c = d['createdAt'];
    if (c is Timestamp) createdAt = c.toDate();
    else if (c is String) createdAt = DateTime.tryParse(c) ?? createdAt;
    final raw = d['order'];
    final order = (raw is int)
        ? raw
        : (raw is num)
            ? raw.toInt()
            : (int.tryParse(raw?.toString() ?? '0') ?? 0);

    return DokumenteOrdner(
      id: id,
      name: d['name']?.toString() ?? '',
      parentId: d['parentId']?.toString(),
      companyId: d['companyId']?.toString() ?? '',
      createdAt: createdAt,
      createdBy: d['createdBy']?.toString() ?? '',
      order: order,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'parentId': parentId,
        'companyId': companyId,
        'createdAt': Timestamp.fromDate(createdAt),
        'createdBy': createdBy,
        'order': order,
      };
}

/// Dokument (Datei) in einem Ordner
/// Firestore: kunden/{companyId}/dokumente/{docId}
class DokumenteDatei {
  final String id;
  final String folderId;
  final String name;
  final String fileUrl; // Firebase Storage URL
  final String filePath; // Storage path
  final String priority; // 'wichtig' | 'mittel' | 'niedrig'
  final bool lesebestaetigungNoetig;
  final String companyId;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  DokumenteDatei({
    required this.id,
    required this.folderId,
    required this.name,
    required this.fileUrl,
    required this.filePath,
    required this.priority,
    required this.lesebestaetigungNoetig,
    required this.companyId,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
  });

  factory DokumenteDatei.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime createdAt = DateTime.now();
    final c = d['createdAt'];
    if (c is Timestamp) createdAt = c.toDate();
    else if (c is String) createdAt = DateTime.tryParse(c) ?? createdAt;

    return DokumenteDatei(
      id: id,
      folderId: d['folderId']?.toString() ?? '',
      name: d['name']?.toString() ?? '',
      fileUrl: d['fileUrl']?.toString() ?? '',
      filePath: d['filePath']?.toString() ?? '',
      priority: d['priority']?.toString() ?? 'mittel',
      lesebestaetigungNoetig: d['lesebestaetigungNoetig'] == true,
      companyId: d['companyId']?.toString() ?? '',
      createdAt: createdAt,
      createdBy: d['createdBy']?.toString() ?? '',
      createdByName: d['createdByName']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'folderId': folderId,
        'name': name,
        'fileUrl': fileUrl,
        'filePath': filePath,
        'priority': priority,
        'lesebestaetigungNoetig': lesebestaetigungNoetig,
        'companyId': companyId,
        'createdAt': Timestamp.fromDate(createdAt),
        'createdBy': createdBy,
        'createdByName': createdByName,
      };
}
