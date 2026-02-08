import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';

/// Profil – Anzeige und Bearbeitung von Benutzerdaten.
class ProfileScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;
  final bool hideAppBar;

  const ProfileScreen({
    super.key,
    required this.companyId,
    this.onBack,
    this.hideAppBar = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _authDataService = AuthDataService();
  bool _loading = true;
  String? _personalnummer;
  String? _vorname;
  String? _nachname;
  String? _email;
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = _authService.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final authData = await _authDataService.getAuthData(
        user.uid,
        user.email ?? '',
        widget.companyId,
      );
      final mitarbeiter = await _loadMitarbeiter(user.uid, user.email ?? '');
      if (mounted) {
        setState(() {
          _displayName = authData.displayName;
          _personalnummer = mitarbeiter?['personalnummer']?.toString();
          _vorname = mitarbeiter?['vorname']?.toString();
          _nachname = mitarbeiter?['nachname']?.toString();
          _email = mitarbeiter?['email']?.toString() ?? user.email;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _displayName = user.email;
          _email = user.email;
          _loading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _loadMitarbeiter(String uid, String email) async {
    try {
      var snap = await FirebaseFirestore.instance
          .collection('kunden')
          .doc(widget.companyId)
          .collection('mitarbeiter')
          .doc(uid)
          .get();
      if (snap.exists) return snap.data();
      final q = await FirebaseFirestore.instance
          .collection('kunden')
          .doc(widget.companyId)
          .collection('mitarbeiter')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.data();
      final qEmail = await FirebaseFirestore.instance
          .collection('kunden')
          .doc(widget.companyId)
          .collection('mitarbeiter')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (qEmail.docs.isNotEmpty) return qEmail.docs.first.data();
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primary,
              elevation: 1,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
              ),
              title: Text('Profil', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProfileRow(label: 'Name', value: _displayName ?? '–'),
                        if (_personalnummer != null) _ProfileRow(label: 'Personalnummer', value: _personalnummer!),
                        if (_vorname != null) _ProfileRow(label: 'Vorname', value: _vorname!),
                        if (_nachname != null) _ProfileRow(label: 'Nachname', value: _nachname!),
                        if (_email != null && _email!.isNotEmpty) _ProfileRow(label: 'E-Mail', value: _email!),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Profil-Daten können in der Web-App bearbeitet werden.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
    if (widget.hideAppBar && widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onBack!();
        },
        child: scaffold,
      );
    }
    return scaffold;
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
