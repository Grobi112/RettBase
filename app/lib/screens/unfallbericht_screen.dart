import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../models/unfallbericht_model.dart';
import '../models/fleet_model.dart';
import '../models/mitarbeiter_model.dart';
import '../services/unfallbericht_service.dart';
import '../services/fleet_service.dart';
import '../services/mitarbeiter_service.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import '../widgets/sketch_canvas.dart';
import '../widgets/signature_pad.dart';
import 'unfallbericht_druck_screen.dart';

const _inputDecoration = InputDecoration(
  filled: true,
  fillColor: Color(0xFFF5F5F5),
  border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
  isDense: true,
);

const _singleLineFieldHeight = 56.0;
const _fuehrerscheinklassen = ['A', 'A1', 'A2', 'AM', 'B', 'BE', 'C', 'CE', 'C1', 'C1E', 'D', 'DE', 'D1', 'D1E', 'L', 'T'];

class UnfallberichtScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;

  const UnfallberichtScreen({super.key, required this.companyId, required this.onBack});

  @override
  State<UnfallberichtScreen> createState() => _UnfallberichtScreenState();
}

class _UnfallberichtScreenState extends State<UnfallberichtScreen> {
  final _service = UnfallberichtService();
  final _fleetService = FleetService();
  final _mitarbeiterService = MitarbeiterService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();

  final _formKey = GlobalKey<FormState>();

  DateTime? _schadentag;
  final _schadenuhrzeitCtrl = TextEditingController();
  final _schadenortCtrl = TextEditingController();
  bool _polizeiAmUnfallort = false;
  final _dienststelleCtrl = TextEditingController();
  final _kilometerstandCtrl = TextEditingController(text: '0');
  Fahrzeug? _selectedFahrzeug;
  final _anhangerCtrl = TextEditingController();
  final _schadenhoeheCtrl = TextEditingController();
  final _schadenEigenesCtrl = TextEditingController();

  Mitarbeiter? _selectedMitarbeiter;
  final _vornameFahrerCtrl = TextEditingController();
  final _nachnameFahrerCtrl = TextEditingController();
  final _telefonFahrerCtrl = TextEditingController();
  final _strasseFahrerCtrl = TextEditingController();
  final _plzFahrerCtrl = TextEditingController();
  final _ortFahrerCtrl = TextEditingController();
  String _fuehrerscheinklasse = 'A';
  DateTime? _ausstellungsdatum;
  final _behoerdeCtrl = TextEditingController();
  bool _alkoholgenuss = false;
  bool _blutprobeEntnommen = false;
  final _blutprobeErgebnisCtrl = TextEditingController();

  final _kennzeichenGegnerCtrl = TextEditingController();
  final _versicherungsscheinCtrl = TextEditingController();
  final _schadenhoeheGegnerCtrl = TextEditingController();
  final _schadenGegnerCtrl = TextEditingController();

  final _vornameGegnerCtrl = TextEditingController();
  final _nachnameGegnerCtrl = TextEditingController();
  final _telefonGegnerCtrl = TextEditingController();
  final _strasseGegnerCtrl = TextEditingController();
  final _plzGegnerCtrl = TextEditingController();
  final _ortGegnerCtrl = TextEditingController();
  final _kurzeSchadenschilderungCtrl = TextEditingController();

  final _vornameFahrzeughalterCtrl = TextEditingController();
  final _nachnameFahrzeughalterCtrl = TextEditingController();
  final _strasseFahrzeughalterCtrl = TextEditingController();
  final _plzFahrzeughalterCtrl = TextEditingController();
  final _ortFahrzeughalterCtrl = TextEditingController();

  final _kurzeBemerkungCtrl = TextEditingController();
  final _ausfuehrlicherSchadensberichtCtrl = TextEditingController();

  List<XFile> _pickedFiles = [];
  final _sketchKey = GlobalKey<SketchCanvasState>();
  final _signatureKey = GlobalKey<SignaturePadState>();
  List<Fahrzeug> _fahrzeuge = [];
  List<Mitarbeiter> _mitarbeiter = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _schadentag = DateTime.now();
    _load();
  }

  Future<void> _load() async {
    final fahrzeuge = await _fleetService.streamFahrzeuge(widget.companyId).first;
    final mitarbeiter = await _mitarbeiterService.streamMitarbeiter(widget.companyId).first;
    final activeMitarbeiter = mitarbeiter.where((m) => m.active).toList();

    // Erstelle automatisch vor – Fahrer = Ersteller des Unfallberichts
    final user = _authService.currentUser;
    if (user != null) {
      final authData = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
      Mitarbeiter? creator = activeMitarbeiter.where((m) => m.uid == user.uid).firstOrNull;
      creator ??= activeMitarbeiter.where((m) => m.email == user.email || m.pseudoEmail == user.email).firstOrNull;
      if (creator != null) {
        _selectedMitarbeiter = creator;
        _fillFromMitarbeiter(creator);
      } else if (authData.displayName != null && authData.displayName!.isNotEmpty) {
        // Fallback: Name aus AuthData (z.B. "Nachname, Vorname")
        final parts = authData.displayName!.split(',').map((s) => s.trim()).toList();
        if (parts.length >= 2) {
          _nachnameFahrerCtrl.text = parts[0];
          _vornameFahrerCtrl.text = parts[1];
        } else {
          _vornameFahrerCtrl.text = authData.vorname ?? authData.displayName!;
        }
      }
    }

    if (mounted) {
      setState(() {
        _fahrzeuge = fahrzeuge;
        _mitarbeiter = activeMitarbeiter;
        _loading = false;
      });
    }
  }

  void _fillFromMitarbeiter(Mitarbeiter? m) {
    if (m == null) return;
    _vornameFahrerCtrl.text = m.vorname ?? '';
    _nachnameFahrerCtrl.text = m.nachname ?? '';
    _telefonFahrerCtrl.text = m.telefon ?? m.handynummer ?? '';
    _strasseFahrerCtrl.text = m.strasse != null && m.hausnummer != null
        ? '${m.strasse} ${m.hausnummer}'.trim()
        : (m.strasse ?? '');
    _plzFahrerCtrl.text = m.plz ?? '';
    _ortFahrerCtrl.text = m.ort ?? '';
    _fuehrerscheinklasse = m.fuehrerschein ?? 'A';
  }

  @override
  void dispose() {
    _schadenuhrzeitCtrl.dispose();
    _schadenortCtrl.dispose();
    _dienststelleCtrl.dispose();
    _kilometerstandCtrl.dispose();
    _anhangerCtrl.dispose();
    _schadenhoeheCtrl.dispose();
    _schadenEigenesCtrl.dispose();
    _vornameFahrerCtrl.dispose();
    _nachnameFahrerCtrl.dispose();
    _telefonFahrerCtrl.dispose();
    _strasseFahrerCtrl.dispose();
    _plzFahrerCtrl.dispose();
    _ortFahrerCtrl.dispose();
    _behoerdeCtrl.dispose();
    _blutprobeErgebnisCtrl.dispose();
    _kennzeichenGegnerCtrl.dispose();
    _versicherungsscheinCtrl.dispose();
    _schadenhoeheGegnerCtrl.dispose();
    _schadenGegnerCtrl.dispose();
    _vornameGegnerCtrl.dispose();
    _nachnameGegnerCtrl.dispose();
    _telefonGegnerCtrl.dispose();
    _strasseGegnerCtrl.dispose();
    _plzGegnerCtrl.dispose();
    _ortGegnerCtrl.dispose();
    _kurzeSchadenschilderungCtrl.dispose();
    _vornameFahrzeughalterCtrl.dispose();
    _nachnameFahrzeughalterCtrl.dispose();
    _strasseFahrzeughalterCtrl.dispose();
    _plzFahrzeughalterCtrl.dispose();
    _ortFahrzeughalterCtrl.dispose();
    _kurzeBemerkungCtrl.dispose();
    _ausfuehrlicherSchadensberichtCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedFahrzeug == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Fahrzeug auswählen.')));
      return;
    }
    final km = int.tryParse(_kilometerstandCtrl.text.trim()) ?? 0;

    setState(() => _saving = true);
    try {
      final u = Unfallbericht(
        id: '',
        createdBy: _authService.currentUser?.uid,
        schadentag: _schadentag,
        schadenuhrzeit: _schadenuhrzeitCtrl.text.trim().isEmpty ? null : _schadenuhrzeitCtrl.text.trim(),
        schadenort: _schadenortCtrl.text.trim().isEmpty ? null : _schadenortCtrl.text.trim(),
        polizeiAmUnfallort: _polizeiAmUnfallort,
        dienststelleTagebuchnummer: _dienststelleCtrl.text.trim().isEmpty ? null : _dienststelleCtrl.text.trim(),
        kilometerstand: km,
        fahrzeugId: _selectedFahrzeug!.id,
        fahrzeugDisplay: _selectedFahrzeug!.kennzeichen ?? _selectedFahrzeug!.rufname ?? _selectedFahrzeug!.displayName,
        anhangerKennzeichen: _anhangerCtrl.text.trim().isEmpty ? null : _anhangerCtrl.text.trim(),
        schadenhoehe: _schadenhoeheCtrl.text.trim().isEmpty ? null : _schadenhoeheCtrl.text.trim(),
        schadenEigenesFahrzeug: _schadenEigenesCtrl.text.trim().isEmpty ? null : _schadenEigenesCtrl.text.trim(),
        mitarbeiterId: _selectedMitarbeiter?.id,
        vornameFahrer: _vornameFahrerCtrl.text.trim().isEmpty ? null : _vornameFahrerCtrl.text.trim(),
        nachnameFahrer: _nachnameFahrerCtrl.text.trim().isEmpty ? null : _nachnameFahrerCtrl.text.trim(),
        telefonFahrer: _telefonFahrerCtrl.text.trim().isEmpty ? null : _telefonFahrerCtrl.text.trim(),
        strasseFahrer: _strasseFahrerCtrl.text.trim().isEmpty ? null : _strasseFahrerCtrl.text.trim(),
        plzFahrer: _plzFahrerCtrl.text.trim().isEmpty ? null : _plzFahrerCtrl.text.trim(),
        ortFahrer: _ortFahrerCtrl.text.trim().isEmpty ? null : _ortFahrerCtrl.text.trim(),
        fuehrerscheinklasse: _fuehrerscheinklasse,
        ausstellungsdatum: _ausstellungsdatum,
        behoerde: _behoerdeCtrl.text.trim().isEmpty ? null : _behoerdeCtrl.text.trim(),
        alkoholgenuss: _alkoholgenuss,
        blutprobeEntnommen: _blutprobeEntnommen,
        blutprobeErgebnis: _blutprobeErgebnisCtrl.text.trim().isEmpty ? null : _blutprobeErgebnisCtrl.text.trim(),
        kennzeichenGegner: _kennzeichenGegnerCtrl.text.trim().isEmpty ? null : _kennzeichenGegnerCtrl.text.trim(),
        versicherungsscheinNr: _versicherungsscheinCtrl.text.trim().isEmpty ? null : _versicherungsscheinCtrl.text.trim(),
        geschaetzteSchadenhoeheGegner: _schadenhoeheGegnerCtrl.text.trim().isEmpty ? null : _schadenhoeheGegnerCtrl.text.trim(),
        schadenGegner: _schadenGegnerCtrl.text.trim().isEmpty ? null : _schadenGegnerCtrl.text.trim(),
        vornameGegner: _vornameGegnerCtrl.text.trim().isEmpty ? null : _vornameGegnerCtrl.text.trim(),
        nachnameGegner: _nachnameGegnerCtrl.text.trim().isEmpty ? null : _nachnameGegnerCtrl.text.trim(),
        telefonGegner: _telefonGegnerCtrl.text.trim().isEmpty ? null : _telefonGegnerCtrl.text.trim(),
        strasseGegner: _strasseGegnerCtrl.text.trim().isEmpty ? null : _strasseGegnerCtrl.text.trim(),
        plzGegner: _plzGegnerCtrl.text.trim().isEmpty ? null : _plzGegnerCtrl.text.trim(),
        ortGegner: _ortGegnerCtrl.text.trim().isEmpty ? null : _ortGegnerCtrl.text.trim(),
        kurzeSchadenschilderung: _kurzeSchadenschilderungCtrl.text.trim().isEmpty ? null : _kurzeSchadenschilderungCtrl.text.trim(),
        vornameFahrzeughalter: _vornameFahrzeughalterCtrl.text.trim().isEmpty ? null : _vornameFahrzeughalterCtrl.text.trim(),
        nachnameFahrzeughalter: _nachnameFahrzeughalterCtrl.text.trim().isEmpty ? null : _nachnameFahrzeughalterCtrl.text.trim(),
        strasseFahrzeughalter: _strasseFahrzeughalterCtrl.text.trim().isEmpty ? null : _strasseFahrzeughalterCtrl.text.trim(),
        plzFahrzeughalter: _plzFahrzeughalterCtrl.text.trim().isEmpty ? null : _plzFahrzeughalterCtrl.text.trim(),
        ortFahrzeughalter: _ortFahrzeughalterCtrl.text.trim().isEmpty ? null : _ortFahrzeughalterCtrl.text.trim(),
        kurzeBemerkung: _kurzeBemerkungCtrl.text.trim().isEmpty ? null : _kurzeBemerkungCtrl.text.trim(),
        ausfuehrlicherSchadensbericht: _ausfuehrlicherSchadensberichtCtrl.text.trim().isEmpty ? null : _ausfuehrlicherSchadensberichtCtrl.text.trim(),
      );

      final docId = await _service.create(widget.companyId, u);

      String? unterschriftUrl;
      final signatureBytes = await _signatureKey.currentState?.captureImage();
      if (signatureBytes != null && signatureBytes.isNotEmpty) {
        final urls = await _service.uploadAnhaenge(widget.companyId, docId, [signatureBytes], ['unterschrift.png'], ['image/png']);
        if (urls.isNotEmpty) unterschriftUrl = urls.first;
      }

      final bytesList = <Uint8List>[];
      final namesList = <String>[];
      final mimeList = <String>[];
      final sketchBytes = await _sketchKey.currentState?.captureImage();
      if (sketchBytes != null && sketchBytes.isNotEmpty) {
        bytesList.add(sketchBytes);
        namesList.add('unfallskizze.png');
        mimeList.add('image/png');
      }
      for (final x in _pickedFiles) {
        bytesList.add(await x.readAsBytes());
        namesList.add(x.name);
        mimeList.add(x.mimeType ?? 'image/jpeg');
      }
      List<String> bilderUrls = [];
      if (bytesList.isNotEmpty) {
        bilderUrls = await _service.uploadAnhaenge(widget.companyId, docId, bytesList, namesList, mimeList);
      }

      Unfallbericht finalReport = u;
      if (bilderUrls.isNotEmpty || unterschriftUrl != null) {
        final updated = Unfallbericht(
          id: docId,
          createdBy: u.createdBy,
          schadentag: u.schadentag,
          schadenuhrzeit: u.schadenuhrzeit,
          schadenort: u.schadenort,
          polizeiAmUnfallort: u.polizeiAmUnfallort,
          dienststelleTagebuchnummer: u.dienststelleTagebuchnummer,
          kilometerstand: u.kilometerstand,
          fahrzeugId: u.fahrzeugId,
          fahrzeugDisplay: u.fahrzeugDisplay,
          anhangerKennzeichen: u.anhangerKennzeichen,
          schadenhoehe: u.schadenhoehe,
          schadenEigenesFahrzeug: u.schadenEigenesFahrzeug,
          mitarbeiterId: u.mitarbeiterId,
          vornameFahrer: u.vornameFahrer,
          nachnameFahrer: u.nachnameFahrer,
          telefonFahrer: u.telefonFahrer,
          strasseFahrer: u.strasseFahrer,
          plzFahrer: u.plzFahrer,
          ortFahrer: u.ortFahrer,
          fuehrerscheinklasse: u.fuehrerscheinklasse,
          ausstellungsdatum: u.ausstellungsdatum,
          behoerde: u.behoerde,
          alkoholgenuss: u.alkoholgenuss,
          blutprobeEntnommen: u.blutprobeEntnommen,
          blutprobeErgebnis: u.blutprobeErgebnis,
          kennzeichenGegner: u.kennzeichenGegner,
          versicherungsscheinNr: u.versicherungsscheinNr,
          geschaetzteSchadenhoeheGegner: u.geschaetzteSchadenhoeheGegner,
          schadenGegner: u.schadenGegner,
          vornameGegner: u.vornameGegner,
          nachnameGegner: u.nachnameGegner,
          telefonGegner: u.telefonGegner,
          strasseGegner: u.strasseGegner,
          plzGegner: u.plzGegner,
          ortGegner: u.ortGegner,
          kurzeSchadenschilderung: u.kurzeSchadenschilderung,
          vornameFahrzeughalter: u.vornameFahrzeughalter,
          nachnameFahrzeughalter: u.nachnameFahrzeughalter,
          strasseFahrzeughalter: u.strasseFahrzeughalter,
          plzFahrzeughalter: u.plzFahrzeughalter,
          ortFahrzeughalter: u.ortFahrzeughalter,
          kurzeBemerkung: u.kurzeBemerkung,
          ausfuehrlicherSchadensbericht: u.ausfuehrlicherSchadensbericht,
          bilderDokumente: bilderUrls,
          unterschriftUrl: unterschriftUrl,
        );
        await _service.update(widget.companyId, updated);
        finalReport = updated;
      }
      finalReport = Unfallbericht(
        id: docId,
        createdBy: u.createdBy,
        schadentag: u.schadentag,
        schadenuhrzeit: u.schadenuhrzeit,
        schadenort: u.schadenort,
        polizeiAmUnfallort: u.polizeiAmUnfallort,
        dienststelleTagebuchnummer: u.dienststelleTagebuchnummer,
        kilometerstand: u.kilometerstand,
        fahrzeugId: u.fahrzeugId,
        fahrzeugDisplay: u.fahrzeugDisplay,
        anhangerKennzeichen: u.anhangerKennzeichen,
        schadenhoehe: u.schadenhoehe,
        schadenEigenesFahrzeug: u.schadenEigenesFahrzeug,
        mitarbeiterId: u.mitarbeiterId,
        vornameFahrer: u.vornameFahrer,
        nachnameFahrer: u.nachnameFahrer,
        telefonFahrer: u.telefonFahrer,
        strasseFahrer: u.strasseFahrer,
        plzFahrer: u.plzFahrer,
        ortFahrer: u.ortFahrer,
        fuehrerscheinklasse: u.fuehrerscheinklasse,
        ausstellungsdatum: u.ausstellungsdatum,
        behoerde: u.behoerde,
        alkoholgenuss: u.alkoholgenuss,
        blutprobeEntnommen: u.blutprobeEntnommen,
        blutprobeErgebnis: u.blutprobeErgebnis,
        kennzeichenGegner: u.kennzeichenGegner,
        versicherungsscheinNr: u.versicherungsscheinNr,
        geschaetzteSchadenhoeheGegner: u.geschaetzteSchadenhoeheGegner,
        schadenGegner: u.schadenGegner,
        vornameGegner: u.vornameGegner,
        nachnameGegner: u.nachnameGegner,
        telefonGegner: u.telefonGegner,
        strasseGegner: u.strasseGegner,
        plzGegner: u.plzGegner,
        ortGegner: u.ortGegner,
        kurzeSchadenschilderung: u.kurzeSchadenschilderung,
        vornameFahrzeughalter: u.vornameFahrzeughalter,
        nachnameFahrzeughalter: u.nachnameFahrzeughalter,
        strasseFahrzeughalter: u.strasseFahrzeughalter,
        plzFahrzeughalter: u.plzFahrzeughalter,
        ortFahrzeughalter: u.ortFahrzeughalter,
        kurzeBemerkung: u.kurzeBemerkung,
        ausfuehrlicherSchadensbericht: u.ausfuehrlicherSchadensbericht,
        bilderDokumente: bilderUrls,
        unterschriftUrl: unterschriftUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unfallbericht gespeichert.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Öffnet PDF-Vorschau mit aktuellen (ggf. ungespeicherten) Formulardaten
  Future<void> _openDruckVorschau() async {
    if (_selectedFahrzeug == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Fahrzeug auswählen.')));
      return;
    }
    final km = int.tryParse(_kilometerstandCtrl.text.trim()) ?? 0;
    final u = Unfallbericht(
      id: '',
      createdBy: _authService.currentUser?.uid,
      schadentag: _schadentag,
      schadenuhrzeit: _schadenuhrzeitCtrl.text.trim().isEmpty ? null : _schadenuhrzeitCtrl.text.trim(),
      schadenort: _schadenortCtrl.text.trim().isEmpty ? null : _schadenortCtrl.text.trim(),
      polizeiAmUnfallort: _polizeiAmUnfallort,
      dienststelleTagebuchnummer: _dienststelleCtrl.text.trim().isEmpty ? null : _dienststelleCtrl.text.trim(),
      kilometerstand: km,
      fahrzeugId: _selectedFahrzeug!.id,
      fahrzeugDisplay: _selectedFahrzeug!.kennzeichen ?? _selectedFahrzeug!.rufname ?? _selectedFahrzeug!.displayName,
      anhangerKennzeichen: _anhangerCtrl.text.trim().isEmpty ? null : _anhangerCtrl.text.trim(),
      schadenhoehe: _schadenhoeheCtrl.text.trim().isEmpty ? null : _schadenhoeheCtrl.text.trim(),
      schadenEigenesFahrzeug: _schadenEigenesCtrl.text.trim().isEmpty ? null : _schadenEigenesCtrl.text.trim(),
      mitarbeiterId: _selectedMitarbeiter?.id,
      vornameFahrer: _vornameFahrerCtrl.text.trim().isEmpty ? null : _vornameFahrerCtrl.text.trim(),
      nachnameFahrer: _nachnameFahrerCtrl.text.trim().isEmpty ? null : _nachnameFahrerCtrl.text.trim(),
      telefonFahrer: _telefonFahrerCtrl.text.trim().isEmpty ? null : _telefonFahrerCtrl.text.trim(),
      strasseFahrer: _strasseFahrerCtrl.text.trim().isEmpty ? null : _strasseFahrerCtrl.text.trim(),
      plzFahrer: _plzFahrerCtrl.text.trim().isEmpty ? null : _plzFahrerCtrl.text.trim(),
      ortFahrer: _ortFahrerCtrl.text.trim().isEmpty ? null : _ortFahrerCtrl.text.trim(),
      fuehrerscheinklasse: _fuehrerscheinklasse,
      ausstellungsdatum: _ausstellungsdatum,
      behoerde: _behoerdeCtrl.text.trim().isEmpty ? null : _behoerdeCtrl.text.trim(),
      alkoholgenuss: _alkoholgenuss,
      blutprobeEntnommen: _blutprobeEntnommen,
      blutprobeErgebnis: _blutprobeErgebnisCtrl.text.trim().isEmpty ? null : _blutprobeErgebnisCtrl.text.trim(),
      kennzeichenGegner: _kennzeichenGegnerCtrl.text.trim().isEmpty ? null : _kennzeichenGegnerCtrl.text.trim(),
      versicherungsscheinNr: _versicherungsscheinCtrl.text.trim().isEmpty ? null : _versicherungsscheinCtrl.text.trim(),
      geschaetzteSchadenhoeheGegner: _schadenhoeheGegnerCtrl.text.trim().isEmpty ? null : _schadenhoeheGegnerCtrl.text.trim(),
      schadenGegner: _schadenGegnerCtrl.text.trim().isEmpty ? null : _schadenGegnerCtrl.text.trim(),
      vornameGegner: _vornameGegnerCtrl.text.trim().isEmpty ? null : _vornameGegnerCtrl.text.trim(),
      nachnameGegner: _nachnameGegnerCtrl.text.trim().isEmpty ? null : _nachnameGegnerCtrl.text.trim(),
      telefonGegner: _telefonGegnerCtrl.text.trim().isEmpty ? null : _telefonGegnerCtrl.text.trim(),
      strasseGegner: _strasseGegnerCtrl.text.trim().isEmpty ? null : _strasseGegnerCtrl.text.trim(),
      plzGegner: _plzGegnerCtrl.text.trim().isEmpty ? null : _plzGegnerCtrl.text.trim(),
      ortGegner: _ortGegnerCtrl.text.trim().isEmpty ? null : _ortGegnerCtrl.text.trim(),
      kurzeSchadenschilderung: _kurzeSchadenschilderungCtrl.text.trim().isEmpty ? null : _kurzeSchadenschilderungCtrl.text.trim(),
      vornameFahrzeughalter: _vornameFahrzeughalterCtrl.text.trim().isEmpty ? null : _vornameFahrzeughalterCtrl.text.trim(),
      nachnameFahrzeughalter: _nachnameFahrzeughalterCtrl.text.trim().isEmpty ? null : _nachnameFahrzeughalterCtrl.text.trim(),
      strasseFahrzeughalter: _strasseFahrzeughalterCtrl.text.trim().isEmpty ? null : _strasseFahrzeughalterCtrl.text.trim(),
      plzFahrzeughalter: _plzFahrzeughalterCtrl.text.trim().isEmpty ? null : _plzFahrzeughalterCtrl.text.trim(),
      ortFahrzeughalter: _ortFahrzeughalterCtrl.text.trim().isEmpty ? null : _ortFahrzeughalterCtrl.text.trim(),
      kurzeBemerkung: _kurzeBemerkungCtrl.text.trim().isEmpty ? null : _kurzeBemerkungCtrl.text.trim(),
      ausfuehrlicherSchadensbericht: _ausfuehrlicherSchadensberichtCtrl.text.trim().isEmpty ? null : _ausfuehrlicherSchadensberichtCtrl.text.trim(),
    );

    Uint8List? unterschriftBytes;
    final sig = await _signatureKey.currentState?.captureImage();
    if (sig != null && sig.isNotEmpty) unterschriftBytes = sig;

    final bilderBytes = <Uint8List>[];
    final sketchBytes = await _sketchKey.currentState?.captureImage();
    if (sketchBytes != null && sketchBytes.isNotEmpty) bilderBytes.add(sketchBytes);
    for (final x in _pickedFiles) {
      bilderBytes.add(await x.readAsBytes());
    }

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UnfallberichtDruckScreen(
            bericht: u,
            onBack: () => Navigator.of(context).pop(),
            unterschriftBytes: unterschriftBytes,
            bilderBytes: bilderBytes.isEmpty ? null : bilderBytes,
          ),
        ),
      );
    }
  }

  Future<void> _pickFiles() async {
    try {
      final files = await ImagePicker().pickMultiImage();
      if (files.isEmpty) return;
      if (mounted) {
        setState(() {
          final remaining = 10 - _pickedFiles.length;
          _pickedFiles.addAll(files.take(remaining));
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _selectDate(Function(DateTime) onSelect) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) onSelect(picked);
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Text(
          title,
          style: TextStyle(
            color: AppTheme.primary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _row3(List<Widget> children) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 12 : 0),
                child: children.length > i ? children[i] : const SizedBox.shrink(),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppTheme.buildModuleAppBar(
          title: 'Unfallbericht',
          onBack: widget.onBack,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Unfallbericht',
        onBack: widget.onBack,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _openDruckVorschau,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 1. Eigenes Fahrzeug
            _sectionTitle('Eigenes Fahrzeug'),
            _row3([
              _dateField('Schadentag', _schadentag, (d) => setState(() => _schadentag = d)),
              _textField(_schadenuhrzeitCtrl, 'Schadenuhrzeit'),
              _textField(_schadenortCtrl, 'Schadenort'),
            ]),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _textField(_dienststelleCtrl, 'Dienststelle/Tagebuchnummer'),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Polizei am Unfallort', style: TextStyle(fontSize: 14)),
                    value: _polizeiAmUnfallort,
                    onChanged: (v) => setState(() => _polizeiAmUnfallort = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row3([
              _textField(_kilometerstandCtrl, 'Kilometerstand', keyboardType: TextInputType.number),
              _fahrzeugDropdown(),
              _textField(_anhangerCtrl, 'Anhänger Kennzeichen'),
            ]),
            const SizedBox(height: 12),
            _row3([
              _textField(_schadenhoeheCtrl, 'Schadenhöhe'),
              const SizedBox.shrink(),
              const SizedBox.shrink(),
            ]),
            const SizedBox(height: 12),
            _textArea(_schadenEigenesCtrl, 'Schaden (eigenes Fahrzeug)', maxLength: 315),

            // 2. Fahrer eigenes Fahrzeug
            _sectionTitle('Fahrer eigenes Fahrzeug'),
            _row3([
              _textField(_vornameFahrerCtrl, 'Vorname'),
              _textField(_nachnameFahrerCtrl, 'Nachname'),
              _textField(_telefonFahrerCtrl, 'Telefon'),
            ]),
            const SizedBox(height: 12),
            _row3([
              _textField(_strasseFahrerCtrl, 'Strasse'),
              _textField(_plzFahrerCtrl, 'Plz'),
              _textField(_ortFahrerCtrl, 'Ort'),
            ]),
            const SizedBox(height: 12),
            _row3([
              _fuehrerscheinDropdown(),
              _dateField('Ausstellungsdatum', _ausstellungsdatum, (d) => setState(() => _ausstellungsdatum = d)),
              _textField(_behoerdeCtrl, 'Behörde'),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Alkoholgenuss oder andere berauschende Mittel',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey.shade800),
                            ),
                          ),
                          Switch(
                            value: _alkoholgenuss,
                            onChanged: (v) => setState(() => _alkoholgenuss = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Wurde eine Blutprobe entnommen?',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey.shade800),
                            ),
                          ),
                          Switch(
                            value: _blutprobeEntnommen,
                            onChanged: (v) => setState(() => _blutprobeEntnommen = v ?? false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _textField(_blutprobeErgebnisCtrl, 'Ergebnis'),

            // 3. Gegnerisches Fahrzeug
            _sectionTitle('Gegnerisches Fahrzeug'),
            _row3([
              _textField(_kennzeichenGegnerCtrl, 'Kennzeichen Gegner'),
              _textField(_versicherungsscheinCtrl, 'Versicherungsschein-Nr'),
              _textField(_schadenhoeheGegnerCtrl, 'geschätzte Schadenhöhe Gegner'),
            ]),
            const SizedBox(height: 12),
            _textArea(_schadenGegnerCtrl, 'Schaden Gegner', maxLength: 315),

            // 4. Fahrer gegnerisches Fahrzeug
            _sectionTitle('Fahrer gegnerisches Fahrzeug'),
            _row3([
              _textField(_vornameGegnerCtrl, 'Vorname Gegner'),
              _textField(_nachnameGegnerCtrl, 'Nachname Gegner'),
              _textField(_telefonGegnerCtrl, 'Telefon Gegner'),
            ]),
            const SizedBox(height: 12),
            _row3([
              _textField(_strasseGegnerCtrl, 'Strasse Gegner'),
              _textField(_plzGegnerCtrl, 'Plz Gegner'),
              _textField(_ortGegnerCtrl, 'Ort Gegner'),
            ]),
            const SizedBox(height: 12),
            _textArea(_kurzeSchadenschilderungCtrl, 'Kurze Schadenschilderung', maxLength: 420),

            // 5. Fahrzeughalter
            _sectionTitle('Fahrzeughalter'),
            _row3([
              _textField(_vornameFahrzeughalterCtrl, 'Vorname Fahrzeughalter'),
              _textField(_nachnameFahrzeughalterCtrl, 'Nachname Fahrzeughalter'),
              const SizedBox.shrink(),
            ]),
            const SizedBox(height: 12),
            _row3([
              _textField(_strasseFahrzeughalterCtrl, 'Straße Fahrzeughalter'),
              _textField(_plzFahrzeughalterCtrl, 'PLZ Fahrzeughalter'),
              _textField(_ortFahrzeughalterCtrl, 'Ort Fahrzeughalter'),
            ]),

            // 6. Bilder / Dokumente
            _sectionTitle('Bilder / Dokumente'),
            Text(
              'Maximal 10 Bilder oder Dokumente.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            _buildUploadSection(),

            const SizedBox(height: 24),
            _sectionTitle('Skizze'),
            Text(
              'Zeichnen Sie optional eine Unfallskizze.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            SketchCanvas(key: _sketchKey, height: 240),

            // 7. Abschließend
            const SizedBox(height: 24),
            _sectionTitle('Abschließend'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      height: 190,
                      child: TextFormField(
                        controller: _kurzeBemerkungCtrl,
                        maxLines: null,
                        maxLength: 260,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: _inputDecoration.copyWith(
                          labelText: 'Kurze Bemerkung (max. 260 Zeichen)',
                          alignLabelWithHint: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: SignaturePad(key: _signatureKey, height: 140),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _textArea(_ausfuehrlicherSchadensberichtCtrl, 'Ausführlicher Schadensbericht (detailliert, optional Seite 2)', maxLength: 2000),

            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Wird gespeichert...' : 'Unfallbericht speichern'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateField(String label, DateTime? value, Function(DateTime) onSelect) {
    return SizedBox(
      height: _singleLineFieldHeight,
      child: InkWell(
        onTap: () => _selectDate(onSelect),
        child: InputDecorator(
          decoration: _inputDecoration.copyWith(labelText: label),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              value != null
                  ? '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}'
                  : '–',
              style: TextStyle(fontSize: 16, color: value != null ? null : Colors.grey[600]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String label, {TextInputType? keyboardType}) {
    return SizedBox(
      height: _singleLineFieldHeight,
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        decoration: _inputDecoration.copyWith(labelText: label),
      ),
    );
  }

  Widget _textArea(TextEditingController ctrl, String label, {int maxLength = 315}) {
    return TextFormField(
      controller: ctrl,
      maxLines: 4,
      maxLength: maxLength,
      decoration: _inputDecoration.copyWith(
        labelText: '$label (max. $maxLength Zeichen)',
        alignLabelWithHint: true,
      ),
    );
  }

  Widget _fahrzeugDropdown() {
    return SizedBox(
      height: _singleLineFieldHeight,
      child: InputDecorator(
        decoration: _inputDecoration.copyWith(labelText: 'Fahrzeug *'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Fahrzeug?>(
            value: _selectedFahrzeug,
            isExpanded: true,
            hint: const Text('bitte wählen'),
            items: [
              const DropdownMenuItem<Fahrzeug?>(value: null, child: Text('bitte wählen')),
              ..._fahrzeuge.map((f) => DropdownMenuItem<Fahrzeug?>(
                    value: f,
                    child: Text(f.kennzeichen ?? f.rufname ?? f.displayName),
                  )),
            ],
            onChanged: (v) => setState(() => _selectedFahrzeug = v),
          ),
        ),
      ),
    );
  }

  Widget _fuehrerscheinDropdown() {
    return SizedBox(
      height: _singleLineFieldHeight,
      child: InputDecorator(
        decoration: _inputDecoration.copyWith(labelText: 'Führerscheinklasse'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _fuehrerscheinklassen.contains(_fuehrerscheinklasse) ? _fuehrerscheinklasse : 'A',
            isExpanded: true,
            items: _fuehrerscheinklassen.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
            onChanged: (v) => setState(() => _fuehrerscheinklasse = v ?? 'A'),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadSection() {
    final totalCount = _pickedFiles.length;
    final canAdd = totalCount < 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pickedFiles.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              _pickedFiles.length,
              (i) => _buildPickedThumbnail(
                _pickedFiles[i],
                () => setState(() => _pickedFiles.removeAt(i)),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (canAdd)
          GestureDetector(
            onTap: _pickFiles,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 8),
                  Text(
                    'Hier können sie weitere Bilder und Dokumente hinterlegen',
                    style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Diese werden nach dem Speichern hochgeladen',
                    style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Achtung! Die Dateien dürfen die Größe von 32 MB nicht überschreiten.',
                    style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.red[700]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.add_photo_alternate, size: 18),
                    label: const Text('Dateien auswählen'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPickedThumbnail(XFile file, VoidCallback onRemove) {
    return Stack(
      children: [
        FutureBuilder<Uint8List>(
          future: file.readAsBytes(),
          builder: (ctx, snap) {
            if (!snap.hasData) return const SizedBox(width: 80, height: 80, child: Center(child: CircularProgressIndicator()));
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snap.data!,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            );
          },
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
