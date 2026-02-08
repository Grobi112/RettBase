class AppModule {
  final String id;
  final String label;
  final String url;
  final String icon;
  final List<String> roles;
  final int order;
  final bool active;
  final List<AppModule>? submenu;

  const AppModule({
    required this.id,
    required this.label,
    required this.url,
    this.icon = 'default',
    this.roles = const ['user'],
    this.order = 999,
    this.active = true,
    this.submenu,
  });

  factory AppModule.fromMap(String id, Map<String, dynamic> map) {
    final rolesRaw = map['roles'];
    List<String> roles = ['user'];
    if (rolesRaw is List) {
      roles = rolesRaw.map((r) => r.toString().toLowerCase()).toList();
    }

    final submenuRaw = map['submenu'];
    List<AppModule>? submenu;
    if (submenuRaw is List) {
      submenu = submenuRaw.map((s) {
        final m = s is Map ? Map<String, dynamic>.from(s) : <String, dynamic>{};
        return AppModule.fromMap(m['id']?.toString() ?? '', m);
      }).toList();
    }

    return AppModule(
      id: id,
      label: map['label']?.toString() ?? id,
      url: map['url']?.toString() ?? '',
      icon: map['icon']?.toString() ?? 'default',
      roles: roles,
      order: (map['order'] as num?)?.toInt() ?? 999,
      active: map['active'] != false,
      submenu: submenu,
    );
  }
}
