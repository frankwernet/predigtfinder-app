import 'package:flutter/foundation.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'predigtfinder_config.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  runApp(const PredigtFinderApp());
}

class PredigtFinderApp extends StatelessWidget {
  const PredigtFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PredigtFinder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const OneDriveTestPage(),
    );
  }
}

class OneDriveTestPage extends StatefulWidget {
  const OneDriveTestPage({super.key});

  @override
  State<OneDriveTestPage> createState() => _OneDriveTestPageState();
}

class _OneDriveTestPageState extends State<OneDriveTestPage> {
  bool suchmenueAnzeigen = false;
  final List<String> predigtDateien = [];
  final List<String> suchErgebnisse = [];
  final Map<String, int> suchTrefferzahlen = {};

  final Map<String, DateTime> predigtDatum = {};
  bool sortierungNeuesteZuerst = true;
  bool sortierungNachTreffern = true;



List<String> sortiertePredigtDateien() {
  final dateien = List<String>.from(
    sucheAktiv ? suchErgebnisse : predigtDateien,
  );

  // Bei aktiver Suche standardmaessig nach Treffern sortieren.
  if (sucheAktiv && sortierungNachTreffern) {
    dateien.sort((a, b) {
      final trefferA = suchTrefferzahlen[a] ?? 0;
      final trefferB = suchTrefferzahlen[b] ?? 0;

      final vergleich = trefferB.compareTo(trefferA);

      return vergleich != 0
          ? vergleich
          : a.toLowerCase().compareTo(b.toLowerCase());
    });

    return dateien;
  }

  if (sortierungNeuesteZuerst) {
    dateien.sort((a, b) {
      final datumA = predigtDatum[a];
      final datumB = predigtDatum[b];

      if (datumA == null && datumB == null) {
        return a.toLowerCase().compareTo(b.toLowerCase());
      }
      if (datumA == null) return 1;
      if (datumB == null) return -1;

      final vergleich = datumB.compareTo(datumA);

      return vergleich != 0
          ? vergleich
          : a.toLowerCase().compareTo(b.toLowerCase());
    });
  } else {
    dateien.sort(
      (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );
  }

  return dateien;
}



  bool sucheAktiv = false;
  bool hintergrundErfassungAktiv = false;
  bool automatischeSynchronisierungAktiv = false;
  bool erfassungAbbrechen = false;
  bool dateilisteWirdErfasst = false;
  Completer<List<String>>? dateilisteCompleter;
  int dateilisteLaufnummer = 0;
  int dateilisteGefunden = 0;
  String? markierteDatei;
  bool predigtVorschauAnzeigen = false;
  bool videoAnsichtAnzeigen = false;
  String aktuellerVideoTitel = '';
  String aktuellerVideoDateiname = '';
  bool videoWirdGeladen = false;
  bool testmenueFreigeschaltet = false;
  bool testfunktionenAnzeigen = false;

  // Synchronisierungsdiagnose
  final Map<String, String> synchronisierungsFehler = {};

  // Temporäre iOS-Synchronisierungsdiagnose
  final List<String> syncDiagnose = [];

  void protokolliereSyncDiagnose(String meldung) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;

    final zeit = DateTime.now();
    final eintrag = '${zeit.toIso8601String()} | $meldung';

    syncDiagnose.add(eintrag);

    // Maximal 200 aktuelle Diagnoseeinträge behalten.
    if (syncDiagnose.length > 200) {
      syncDiagnose.removeRange(0, syncDiagnose.length - 200);
    }
    debugPrint('PREDIGTFINDER IOS-DIAGNOSE: $eintrag');
  }

  DateTime? letzteSynchronisierung;
  int letzteAnzahlGefunden = 0;
  int letzteAnzahlErfolgreich = 0;

  // Administratorbereich
  bool adminAngemeldet = false;
  bool adminBereichAnzeigen = false;

  // Geschützter lokaler Speicher für die Administrator-PIN.
  final FlutterSecureStorage adminSpeicher = const FlutterSecureStorage();

  static const String adminPinSchluessel = 'predigtfinder_admin_pin';

  Future<bool> adminPinVorhanden() async {
    final pin = await adminSpeicher.read(key: adminPinSchluessel);

    return pin != null && pin.length == 4;
  }

  Future<bool> adminPinPruefen(String eingabe) async {
    final gespeichertePin = await adminSpeicher.read(key: adminPinSchluessel);

    return gespeichertePin != null && gespeichertePin == eingabe;
  }

  Future<void> adminPinSpeichern(String neuePin) async {
    if (!RegExp(r'^[0-9]{4}$').hasMatch(neuePin)) {
      throw ArgumentError(
        'Die Administrator-PIN muss genau vier Ziffern haben.',
      );
    }

    await adminSpeicher.write(key: adminPinSchluessel, value: neuePin);
  }

  Future<void> adminPinAendern() async {
    if (!adminAngemeldet) return;

    final altePinController = TextEditingController();
    final neuePinController = TextEditingController();
    final bestaetigungController = TextEditingController();

    try {
      final speichern = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Administrator-PIN ändern'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final feld in [
                  (altePinController, 'Bisherige PIN'),
                  (neuePinController, 'Neue PIN'),
                  (bestaetigungController, 'Neue PIN bestätigen'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: feld.$1,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: feld.$2,
                        counterText: '',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('PIN ändern'),
            ),
          ],
        ),
      );

      if (speichern != true || !mounted) return;

      String meldung;

      if (!await adminPinPruefen(altePinController.text)) {
        meldung = 'Die bisherige PIN ist falsch.';
      } else if (!RegExp(r'^[0-9]{4}$').hasMatch(neuePinController.text)) {
        meldung = 'Die neue PIN muss genau vier Ziffern haben.';
      } else if (neuePinController.text != bestaetigungController.text) {
        meldung = 'Die neuen PIN-Eingaben stimmen nicht überein.';
      } else {
        await adminPinSpeichern(neuePinController.text);
        meldung = 'Administrator-PIN erfolgreich geändert.';
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(meldung)));
    } catch (e) {
      debugPrint('PREDIGTFINDER PIN-ÄNDERUNG FEHLER: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN konnte nicht geändert werden.')),
        );
      }
    } finally {
      altePinController.dispose();
      neuePinController.dispose();
      bestaetigungController.dispose();
    }
  }

  Future<void> syncBerichtAnzeigen() async {
    if (!adminAngemeldet || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Synchronisierungsbericht'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Letzte Synchronisierung: '
                  '${letzteSynchronisierung?.toLocal().toString().substring(0, 16) ?? "Noch keine"}',
                ),
                const SizedBox(height: 12),
                Text(
                  'OneDrive-Dateien gefunden: '
                  '$letzteAnzahlGefunden',
                ),
                Text(
                  'Predigten beim letzten Sync gespeichert: '
                  '$letzteAnzahlErfolgreich',
                ),
                Text(
                  'Aktuell lokal gespeichert: '
                  '${predigtTexte.length}',
                ),
                const Divider(),
                const Text(
                  'iOS-Synchronisierungsdiagnose',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (syncDiagnose.isEmpty)
                  const Text('Noch keine Diagnoseeinträge.')
                else
                  SelectableText(syncDiagnose.join('\n')),
                const Divider(),
                Text(
                  'Protokollierte Fehler: '
                  '${synchronisierungsFehler.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (synchronisierungsFehler.isEmpty)
                  const Text('Keine Fehler protokolliert.')
                else
                  ...synchronisierungsFehler.entries.map(
                    (eintrag) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eintrag.key,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            eintrag.value,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Future<void> adminMenueAnzeigen() async {
    if (!adminAngemeldet || !mounted) return;

    final auswahl = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('PredigtFinder – Administration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.key),
              title: const Text('Administrator-PIN ändern'),
              onTap: () => Navigator.pop(dialogContext, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Abmelden'),
              onTap: () => Navigator.pop(dialogContext, 'logout'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    switch (auswahl) {
      case 'pin':
        await adminPinAendern();
        break;
      case 'logout':
        setState(() {
          adminAngemeldet = false;
          adminBereichAnzeigen = false;
        });
        break;
    }
  }
  Future<void> adminAnmelden() async {
    final pinVorhanden = await adminPinVorhanden();

    if (!mounted) return;

    final pinController = TextEditingController();

    try {
      final eingabe = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            pinVorhanden
                ? 'Administrator-Anmeldung'
                : 'Administrator-PIN festlegen',
          ),
          content: TextField(
            controller: pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Vierstellige PIN',
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, pinController.text);
              },
              child: Text(pinVorhanden ? 'Anmelden' : 'PIN speichern'),
            ),
          ],
        ),
      );

      if (!mounted || eingabe == null) return;

      if (!RegExp(r'^[0-9]{4}$').hasMatch(eingabe)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte genau vier Ziffern eingeben.')),
        );
        return;
      }

      if (!pinVorhanden) {
        await adminPinSpeichern(eingabe);
      } else if (!await adminPinPruefen(eingabe)) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falsche Administrator-PIN')),
        );
        return;
      }

      if (!mounted) return;

      setState(() {
        adminAngemeldet = true;
        adminBereichAnzeigen = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Administrator erfolgreich angemeldet')),
      );
      await adminMenueAnzeigen();
    } finally {
      pinController.dispose();
    }
  }

  final TextEditingController suchfeld1 = TextEditingController();
  final TextEditingController suchfeld2 = TextEditingController();
  final TextEditingController suchfeld3 = TextEditingController();

  @override
  void dispose() {
    githubKonfigurationsTimer?.cancel();

    suchfeld1.dispose();
    suchfeld2.dispose();
    suchfeld3.dispose();

    super.dispose();
  }

  String verknuepfung1 = 'ODER';
  String verknuepfung2 = 'ODER';

  final Map<String, String> predigtTexte = {};
  final Map<String, String> videoDateinamen = {};
  final Map<String, String> videoDirektlinks = {};
  final Map<String, int> videoDauern = {};
  DateTime? letzterKlickZeitpunkt;
  String? letzteAngeklickteDatei;
  static const String oneDriveUrl =
      'https://1drv.ms/f/c/55f4c0791e5c3652/'
      'IgA7jv5ZNKNOQY3PRgsV_fwPAQjygP70ICDa1YIsbH7U7Ck?e=kFds2v';

  late String aktiveOneDriveUrl = oneDriveUrl;

  late final WebViewController controller;
  late final WebViewController videoController;

  static const String oneDriveVideoUrl =
      'https://1drv.ms/f/c/55f4c0791e5c3652/'
      'IgBSNlweecD0IIBVkpcAAAAAAWh1wjm7IlYSikuoIEchb_Y?e=hN8J7c';
  String aktiveOneDriveVideoUrl = oneDriveVideoUrl;
  bool isLoading = false;
  bool isOpened = false;
  String status = 'Bereit zum Verbindungstest';
  Timer? githubKonfigurationsTimer;

  Future<void> ladeVideoDirektlinks() async {
    // Lokale Videolinks als Rückfalllösung laden.
    try {
      final jsonText = await rootBundle.loadString(
        'assets/data/videolinks_start.json',
      );

      final daten = jsonDecode(jsonText);

      if (daten is Map) {
        final links = Map<String, String>.from(daten);

        if (!mounted) return;

        setState(() {
          videoDirektlinks
            ..clear()
            ..addAll(links);
        });

        debugPrint(
          'PREDIGTFINDER VIDEOLINKS LOKAL: ${links.length}',
        );
      }
    } catch (e) {
      debugPrint('PREDIGTFINDER VIDEOLINKS LOKAL FEHLER: $e');
    }

    // Aktuelle Videolinks zentral von GitHub laden.
    try {
      final antwort = await http.get(
        Uri.parse(
          'https://frankwernet.github.io/predigtfinder/videolinks.json',
        ),
      ).timeout(const Duration(seconds: 20));

      if (antwort.statusCode != 200) {
        throw Exception('GitHub HTTP ${antwort.statusCode}');
      }

      final daten = jsonDecode(utf8.decode(antwort.bodyBytes));

      if (daten is! Map) {
        throw const FormatException('Ungültige Videolinkliste');
      }

      final links = Map<String, String>.from(daten);

      if (links.isEmpty ||
          links.values.any(
            (link) =>
                !link.startsWith('https://'),
          )) {
        throw const FormatException('Ungültige Videolinks');
      }

      if (!mounted) return;

      setState(() {
        videoDirektlinks
          ..clear()
          ..addAll(links);
      });

      debugPrint(
        'PREDIGTFINDER VIDEOLINKS GITHUB ERFOLG: ${links.length}',
      );
    } catch (e) {
      debugPrint(
        'PREDIGTFINDER VIDEOLINKS GITHUB FEHLER: $e',
      );
    }
  }
  String formatiereVideoDauer(int sekunden) {
    final dauer = Duration(seconds: sekunden);
    final stunden = dauer.inHours;
    final minuten = dauer.inMinutes.remainder(60);
    final restSekunden = dauer.inSeconds.remainder(60);

    final mm = minuten.toString().padLeft(2, '0');
    final ss = restSekunden.toString().padLeft(2, '0');

    if (stunden > 0) {
      return '$stunden:$mm:$ss';
    }

    return '$minuten:$ss';
  }
  Future<void> ladeVideoDauern() async {
    try {
      final antwort = await http.get(
        Uri.parse(
          'https://frankwernet.github.io/predigtfinder/videodauern.json',
        ),
      ).timeout(const Duration(seconds: 20));

      if (antwort.statusCode != 200) {
        throw Exception('GitHub HTTP ${antwort.statusCode}');
      }

      final daten = jsonDecode(utf8.decode(antwort.bodyBytes));

      if (daten is! Map) {
        throw const FormatException('Ungültige Videolängen');
      }

      final dauern = <String, int>{};

      for (final eintrag in daten.entries) {
        if (eintrag.key is String &&
            eintrag.value is int &&
            eintrag.value > 0) {
          dauern[eintrag.key as String] = eintrag.value as int;
        }
      }

      if (!mounted) return;

      setState(() {
        videoDauern
          ..clear()
          ..addAll(dauern);
      });

      debugPrint(
        'PREDIGTFINDER VIDEOLÄNGEN GELADEN: ${dauern.length}',
      );
    } catch (e) {
      debugPrint('PREDIGTFINDER VIDEOLÄNGEN FEHLER: $e');
    }
  }
  Future<void> initialisierePredigtSpeicher() async {
    // Zuerst die gesicherten Startpredigten laden.
    await ladeStartPredigten();

    // Danach lokale Daten ergänzen.
    // Lokale Fassungen haben Vorrang.
    await ladePredigtenLokal();
    // Gespeicherten Synchronisierungsbericht laden.
    await ladeSyncBericht();

    if (!mounted) return;

    // Zusammengeführten Bestand dauerhaft speichern.
    try {
      await speicherePredigtenLokal();

      debugPrint(
        'PREDIGTFINDER INITIALISIERUNG ABGESCHLOSSEN: '
        '${predigtTexte.length} Predigten',
      );
    } catch (e) {
      debugPrint('PREDIGTFINDER INITIALISIERUNGSFEHLER: $e');
    }
  }

  Future<File> lokalePredigtDatei() async {
    final verzeichnis = await getApplicationDocumentsDirectory();

    return File('${verzeichnis.path}/predigtfinder_texte.json');
  }

  Future<File> lokaleSyncBerichtDatei() async {
    final verzeichnis = await getApplicationDocumentsDirectory();

    return File('${verzeichnis.path}/predigtfinder_sync_report.json');
  }

  Future<void> speichereSyncBericht() async {
    try {
      final datei = await lokaleSyncBerichtDatei();
      final tempDatei = File('${datei.path}.tmp');

      final bericht = {
        'version': 1,
        'zeitpunkt': DateTime.now().toIso8601String(),
        'dateienGefunden': letzteAnzahlGefunden,
        'dateienErfolgreich': letzteAnzahlErfolgreich,
        'predigtenGespeichert': predigtTexte.length,
        'diagnose': List<String>.from(syncDiagnose),
        'fehler': Map<String, String>.from(synchronisierungsFehler),
      };

      await tempDatei.writeAsString(jsonEncode(bericht), flush: true);

      if (await datei.exists()) {
        await datei.delete();
      }

      await tempDatei.rename(datei.path);

      debugPrint(
        'PREDIGTFINDER SYNC-BERICHT GESPEICHERT: '
        '${synchronisierungsFehler.length} Fehlereinträge',
      );
    } catch (e) {
      debugPrint('PREDIGTFINDER SYNC-BERICHT SPEICHERFEHLER: $e');
    }
  }

  Future<void> ladeSyncBericht() async {
    try {
      final datei = await lokaleSyncBerichtDatei();

      if (!await datei.exists()) {
        debugPrint('PREDIGTFINDER SYNC-BERICHT: Noch nicht vorhanden');
        return;
      }

      final inhalt = await datei.readAsString();
      final daten = jsonDecode(inhalt);

      if (daten is! Map) {
        throw const FormatException(
          'Ungültiges Synchronisierungsbericht-Format',
        );
      }

      final fehler = Map<String, String>.from(
        daten['fehler'] ?? <String, String>{},
      );

      // Veralteten Timeout aus früherer Dateilisten-Erfassung entfernen.
      fehler.removeWhere(
        (schluessel, meldung) =>
            (schluessel == 'Synchronisierung' || schluessel == 'OneDrive') &&
            meldung.contains('TimeoutException after 0:01:30.000000'),
      );

      final zeitpunkt = daten['zeitpunkt'];

      if (!mounted) return;

      setState(() {
        synchronisierungsFehler
          ..clear()
          ..addAll(fehler);

        letzteAnzahlGefunden = (daten['dateienGefunden'] as num?)?.toInt() ?? 0;

        letzteAnzahlErfolgreich =
            (daten['dateienErfolgreich'] as num?)?.toInt() ?? 0;

        letzteSynchronisierung = zeitpunkt is String
            ? DateTime.tryParse(zeitpunkt)
            : null;
      });

      debugPrint(
        'PREDIGTFINDER SYNC-BERICHT GELADEN: '
        '${synchronisierungsFehler.length} Fehlereinträge',
      );
    } catch (e) {
      debugPrint('PREDIGTFINDER SYNC-BERICHT LADEFEHLER: $e');
    }
  }

  Future<void> _letzterSpeichervorgang = Future.value();

  Future<void> speicherePredigtenLokal() {

final snapshot = <String, dynamic>{
  'version': 1,
  'predigtTexte': Map<String, String>.from(predigtTexte),
  'videoDateinamen': Map<String, String>.from(videoDateinamen),
  'predigtDatum': predigtDatum.map(
    (dateiname, datum) => MapEntry(
      dateiname,
      '${datum.year.toString().padLeft(4, '0')}-'
      '${datum.month.toString().padLeft(2, '0')}-'
      '${datum.day.toString().padLeft(2, '0')}',
    ),
  ),
};


    final vorgang = _letzterSpeichervorgang.catchError((Object _) {}).then((
      _,
    ) async {
      final datei = await lokalePredigtDatei();
      final tempDatei = File('${datei.path}.tmp');

      await tempDatei.writeAsString(jsonEncode(snapshot), flush: true);

      await tempDatei.rename(datei.path);

      debugPrint(
        'PREDIGTFINDER LOKAL GESPEICHERT: '
        '${(snapshot['predigtTexte'] as Map).length} Predigten',
      );
    });

    _letzterSpeichervorgang = vorgang;
    return vorgang;
  }


Future<void> ladePredigtDatumsangaben() async {
  try {
    final url = Uri.parse(
      'https://frankwernet.github.io/predigtfinder/predigt_daten.json',
    ).replace(
      queryParameters: {
        'v': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    final antwort = await http
        .get(url)
        .timeout(const Duration(seconds: 30));

    if (antwort.statusCode != 200) {
      throw Exception('HTTP ${antwort.statusCode}');
    }

    final daten = jsonDecode(utf8.decode(antwort.bodyBytes));

    if (daten is! Map) {
      throw const FormatException('Ungueltige Datumsdatei');
    }

    final geladeneDaten = <String, DateTime>{};

    for (final eintrag in daten.entries) {
      if (eintrag.key is String && eintrag.value is String) {
        final datum = DateTime.tryParse(eintrag.value as String);

        if (datum != null) {
          geladeneDaten[eintrag.key as String] = datum;
        }
      }
    }

    if (!mounted) return;

    setState(() {
      predigtDatum
        ..clear()
        ..addAll(geladeneDaten);
    });

    debugPrint(
      'PREDIGTFINDER DATUM: ${predigtDatum.length} Datumsangaben geladen',
    );

debugPrint(
  'PREDIGTFINDER DATUM TEST: '
  'Dateien=${predigtDateien.length}, '
  'mit Datum=${predigtDateien.where((name) => predigtDatum.containsKey(name)).length}',
);

debugPrint(
  'PREDIGTFINDER DATUM BEISPIEL: '
  '${predigtDatum["WER IST GOTT und WAS IST ER WIRKLICH GUT oder BÖSE.txt"]}',
);

  } catch (e) {
    debugPrint('PREDIGTFINDER DATUM LADEFEHLER: $e');
  }
}


  Future<void> synchronisiereVonGitHub() async {
    if (automatischeSynchronisierungAktiv) {
      debugPrint('PREDIGTFINDER GITHUB: Synchronisierung läuft bereits');
      return;
    }

    setState(() {
  automatischeSynchronisierungAktiv = true;
});

    try {
    const basis = 'https://frankwernet.github.io/predigtfinder';

    final antwort = await http
        .get(Uri.parse('$basis/predigten.json'))
        .timeout(const Duration(seconds: 30));

    if (antwort.statusCode != 200) {
      throw Exception('GitHub HTTP ${antwort.statusCode}');
    }

    final daten = jsonDecode(utf8.decode(antwort.bodyBytes));

    if (daten is! Map || daten['predigten'] is! List) {
      throw const FormatException('Ungültiges Predigtverzeichnis');
    }

    final eintraege = daten['predigten'] as List;
    final neueTexte = <String, String>{};
    final neueVideos = <String, String>{};
    final fehler = <String>[];

    for (final eintrag in eintraege) {
      try {
        if (eintrag is! Map) {
          throw const FormatException('Ungültiger Eintrag');
        }

        final name = eintrag['datei'];
        final video = eintrag['video'];

        if (name is! String ||
            !name.toLowerCase().endsWith('.txt') ||
            name.contains('/') ||
            name.contains(r'\') ||
            video is! String ||
            !video.toLowerCase().endsWith('.mp4')) {
          throw const FormatException('Ungültiger Datei- oder Videoname');
        }

        final url = Uri.parse(
          '$basis/texte/${Uri.encodeComponent(name)}',
        ).replace(
          queryParameters: {
            'v': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        );

        final textAntwort = await http
            .get(url)
            .timeout(const Duration(seconds: 30));

        if (textAntwort.statusCode != 200) {
          throw Exception('HTTP ${textAntwort.statusCode}');
        }

        final inhalt = utf8.decode(textAntwort.bodyBytes);

        if (inhalt.trim().isEmpty) {
          throw const FormatException('Leerer Predigttext');
        }

        final ersteZeile = inhalt
            .split(RegExp(r'\r?\n'))
            .first
            .replaceFirst('\uFEFF', '')
            .trim();

        if (ersteZeile != video) {
          throw const FormatException('Videozuordnung stimmt nicht');
        }

        neueTexte[name] = inhalt;
        neueVideos[name] = video;
      } catch (e) {
        fehler.add('${eintrag is Map ? eintrag['datei'] : '?'}: $e');
      }
    }

    if (fehler.isNotEmpty) {
      for (final eintrag in fehler) {
        debugPrint('PREDIGTFINDER GITHUB FEHLER: $eintrag');
      }
    }

    if (fehler.isNotEmpty) {
      throw StateError(
        'GitHub-Synchronisierung unvollständig: ${fehler.length} Fehler',
      );
    }

    if (neueTexte.isEmpty) {
      throw StateError('Keine Predigten von GitHub geladen');
    }

    if (!mounted) return;

    setState(() {
      predigtTexte
        ..clear()
        ..addAll(neueTexte);

      videoDateinamen
        ..clear()
        ..addAll(neueVideos);

      predigtDateien
        ..clear()
        ..addAll(predigtTexte.keys.toList()..sort());

      status = '${neueTexte.length} GitHub-Predigten geladen';
    });

    await speicherePredigtenLokal();

    await ladePredigtDatumsangaben();


    debugPrint(
      'PREDIGTFINDER GITHUB ERFOLG: '
      '${neueTexte.length} Texte, ${fehler.length} Fehler',
    );
    } finally {
      if (mounted) {
  setState(() {
    automatischeSynchronisierungAktiv = false;
  });
} else {
  automatischeSynchronisierungAktiv = false;
}
    }
  }

  Future<bool> ladePredigtenLokal() async {
    try {
      final datei = await lokalePredigtDatei();

      if (!await datei.exists()) {
        return false;
      }

      final daten = jsonDecode(await datei.readAsString());

      if (daten is! Map) return false;

      final texte = daten['predigtTexte'];
      final videos = daten['videoDateinamen'];

      if (texte is! Map) return false;

      if (!mounted) return false;

      setState(() {
        predigtTexte.addAll(Map<String, String>.from(texte));

        if (videos is Map) {
          videoDateinamen.addAll(Map<String, String>.from(videos));
        }

        predigtDateien
          ..clear()
          ..addAll(predigtTexte.keys.toList()..sort());

        status = '${predigtTexte.length} Predigten lokal geladen';
      });

      debugPrint(
        'PREDIGTFINDER LOKAL GELADEN: '
        '${predigtTexte.length} Predigten',
      );

      return true;
    } catch (e) {
      debugPrint('PREDIGTFINDER LOKALER LADEFEHLER: $e');
      return false;
    }
  }

  Future<void> ladeStartPredigten() async {
    try {
      final jsonText = await rootBundle.loadString(
        'assets/data/predigttexte_start.json',
      );

      final daten = jsonDecode(jsonText);

      if (daten is! Map) {
        throw Exception('Ungültiges Predigtformat');
      }

      final geladeneTexte = <String, String>{};

      for (final eintrag in daten.entries) {
        if (eintrag.key is String &&
            eintrag.value is String &&
            (eintrag.value as String).isNotEmpty) {
          geladeneTexte[eintrag.key as String] = eintrag.value as String;
        }
      }

      if (!mounted) return;

      setState(() {
        predigtTexte.addAll(geladeneTexte);

        for (final eintrag in geladeneTexte.entries) {
          final ersteZeile = eintrag.value.split(RegExp(r'\r?\n')).first.trim();

          if (ersteZeile.toLowerCase().endsWith('.mp4')) {
            videoDateinamen[eintrag.key] = ersteZeile;
          }
        }

        predigtDateien
          ..clear()
          ..addAll(predigtTexte.keys.toList()..sort());

        status = '${predigtTexte.length} Predigten lokal geladen';
      });

      debugPrint(
        'PREDIGTFINDER LOKAL GELADEN: '
        '${geladeneTexte.length} Predigten',
      );
    } catch (e) {
      debugPrint('PREDIGTFINDER LADEFEHLER: $e');
    }
  }

  Future<void> pruefeGitHubKonfiguration() async {
    // Zuerst die zuletzt gespeicherte Konfiguration laden.
    try {
      final lokal = await PredigtFinderConfig.lokalLaden();

      if (lokal != null) {
        aktiveOneDriveUrl = lokal.predigttexteUrl;
        aktiveOneDriveVideoUrl = lokal.predigtvideosUrl;

        debugPrint(
          'PREDIGTFINDER KONFIGURATION LOKAL GELADEN: '
          'Version ${lokal.version}',
        );
      } else {
        debugPrint(
          'PREDIGTFINDER KONFIGURATION: '
          'Noch kein lokaler Cache vorhanden',
        );
      }
    } catch (e) {
      debugPrint('PREDIGTFINDER KONFIGURATION CACHEFEHLER: $e');
    }

    // Anschließend GitHub Pages abrufen.
    try {
      final config = await PredigtFinderConfig.laden();

      aktiveOneDriveUrl = config.predigttexteUrl;
      aktiveOneDriveVideoUrl = config.predigtvideosUrl;

      await config.lokalSpeichern();

      debugPrint(
        'PREDIGTFINDER KONFIGURATION: GitHub Pages erfolgreich geladen',
      );
      debugPrint('PREDIGTFINDER KONFIGURATION VERSION: ${config.version}');
      debugPrint('PREDIGTFINDER KONFIGURATION LOKAL GESPEICHERT');
    } catch (e) {
      debugPrint('PREDIGTFINDER KONFIGURATION FEHLER: $e');
    }
  }

  Future<bool> warteAufPredigtDateiliste() async {
    for (var versuch = 0; versuch < 30; versuch++) {
      if (!mounted) return false;

      try {
        final ergebnis = await controller.runJavaScriptReturningResult(r'''
          (() => {
            const liste = Array.from(
              document.querySelectorAll('[id^="html-list_"]')
            ).find(el => el.scrollHeight > el.clientHeight);

            return liste !== undefined;
          })();
        ''');

        if (ergebnis == true || ergebnis.toString() == 'true') {
          debugPrint('PREDIGTFINDER AUTOSYNC: OneDrive-Dateiliste bereit');
          return true;
        }
      } catch (e) {
        debugPrint('PREDIGTFINDER AUTOSYNC WARTEFEHLER: $e');
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    debugPrint('PREDIGTFINDER AUTOSYNC: Dateiliste nicht bereit');

    try {
      final diagnose = await controller.runJavaScriptReturningResult(r'''
        (() => {
          return JSON.stringify({
            url: window.location.href,
            titel: document.title,
            status: document.readyState,
            htmlListen: document.querySelectorAll(
              '[id^="html-list_"]'
            ).length,
            zeilen: document.querySelectorAll(
              '[role="row"]'
            ).length,
            textLaenge: document.body?.innerText.length ?? 0
          });
        })();
      ''');

      debugPrint('PREDIGTFINDER AUTOSYNC DIAGNOSE: $diagnose');
    } catch (e) {
      debugPrint('PREDIGTFINDER AUTOSYNC DIAGNOSEFEHLER: $e');
    }

    return false;
  }

  Future<void> starteAutomatischeSynchronisierung() async {
    if (automatischeSynchronisierungAktiv ||
        hintergrundErfassungAktiv ||
        dateilisteWirdErfasst) {
      debugPrint('PREDIGTFINDER AUTOSYNC: Bereits aktiv');
      return;
    }

    automatischeSynchronisierungAktiv = true;
    String syncSchritt = 'Initialisierung';
    syncDiagnose.clear();
    protokolliereSyncDiagnose('01 Synchronisierung gestartet');
    try {
      debugPrint('PREDIGTFINDER AUTOSYNC: Gestartet');

      if (!mounted) return;

      // OneDrive-WebView in den Widget-Baum aufnehmen.
      if (!isOpened) {
        setState(() {
          isOpened = true;
        });

        await WidgetsBinding.instance.endOfFrame;
      }

      if (!mounted) return;

      syncSchritt = 'OneDrive-Seite laden';
      protokolliereSyncDiagnose('02 OneDrive-Seite laden');
      // Zentral konfigurierten Textordner laden.
      await controller.loadRequest(Uri.parse(aktiveOneDriveUrl));
      syncSchritt = 'Auf OneDrive-Dateiliste warten';
      protokolliereSyncDiagnose('03 Warte auf OneDrive-Dateiliste');
      // Auf die dynamische OneDrive-Dateiliste warten.
      final bereit = await warteAufPredigtDateiliste();

      if (!mounted) return;

      if (!bereit) {
        debugPrint(
          'PREDIGTFINDER AUTOSYNC: OneDrive-Dateiliste nicht verfügbar',
        );

        letzteSynchronisierung = DateTime.now();
        letzteAnzahlGefunden = 0;
        letzteAnzahlErfolgreich = predigtTexte.length;

        synchronisierungsFehler['OneDrive'] =
            'OneDrive-Dateiliste konnte nicht geladen werden.';

        await speichereSyncBericht();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Synchronisierung abgebrochen: '
                'OneDrive-Dateiliste konnte nicht geladen werden.',
              ),
              duration: Duration(seconds: 15),
            ),
          );
        }

        return;
      }

      debugPrint('PREDIGTFINDER AUTOSYNC: OneDrive bereit für Dateierfassung');

      syncSchritt = 'OneDrive-Dateiliste erfassen';
      protokolliereSyncDiagnose('04 JavaScript-Dateierfassung starten');
      final dateien = await erfasseDateilisteMitTimeout();

      if (!mounted) return;

      final gespeicherteNamen = predigtTexte.keys
          .map((name) => name.replaceAll(RegExp(r'\s+'), ' ').trim())
          .toSet();

      final neueDateien = dateien.where((name) {
        final normalisiert = name.replaceAll(RegExp(r'\s+'), ' ').trim();

        return !gespeicherteNamen.contains(normalisiert);
      }).toList();

      for (final dateiname in neueDateien) {
        debugPrint('PREDIGTFINDER AUTOSYNC FEHLT: $dateiname');
      }

      if (neueDateien.isNotEmpty) {
        debugPrint(
          'PREDIGTFINDER AUTOSYNC: '
          'Starte Erfassung von ${neueDateien.length} fehlenden Predigten',
        );

        syncSchritt = 'Predigttexte erfassen';
        await erfassePredigten(predigtDateien.length);

        debugPrint(
          'PREDIGTFINDER AUTOSYNC: '
          'Texterfassung beendet, ${predigtTexte.length} Predigten gespeichert',
        );
      }

      debugPrint(
        'PREDIGTFINDER AUTOSYNC ERGEBNIS: '
        '${dateien.length} TXT-Dateien gefunden, '
        '${predigtTexte.length} Predigten gespeichert, '
        '${neueDateien.length} neue Dateien',
      );

      // Ein früherer Timeout ist nach einem erfolgreichen Lauf nicht aktuell.
      synchronisierungsFehler.remove('Synchronisierung');
      synchronisierungsFehler.remove('OneDrive');
      // Synchronisierungsbericht aktualisieren.
      letzteSynchronisierung = DateTime.now();
      letzteAnzahlGefunden = dateien.length;
      letzteAnzahlErfolgreich = predigtTexte.length;

      // Bericht dauerhaft speichern.
      await speichereSyncBericht();

      debugPrint(
        'PREDIGTFINDER AUTOSYNC: '
        'Synchronisierungsbericht aktualisiert',
      );
    } catch (e) {
      debugPrint('PREDIGTFINDER AUTOSYNC FEHLER: $e');

      letzteSynchronisierung = DateTime.now();
      letzteAnzahlGefunden = predigtDateien.length;
      letzteAnzahlErfolgreich = predigtTexte.length;

      synchronisierungsFehler['Synchronisierung'] =
          'Schritt: $syncSchritt | Fehler: $e';

      await speichereSyncBericht();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synchronisierung fehlgeschlagen: $e'),
            duration: const Duration(seconds: 15),
          ),
        );
      }
    } finally {
      automatischeSynchronisierungAktiv = false;
    }
  }

  Future<void> initialisiereStartdaten() async {
    await initialisierePredigtSpeicher();
    if (!mounted) return;

    await ladeVideoDirektlinks();
    await ladeVideoDauern();
    if (!mounted) return;

    await pruefeGitHubKonfiguration();
    if (!mounted) return;

    debugPrint(
      'PREDIGTFINDER STARTDATEN BEREIT: '
      '${predigtTexte.length} Predigten',
    );

    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) return;

    try {
      await synchronisiereVonGitHub();
    } catch (e) {
      debugPrint('PREDIGTFINDER GITHUB STARTFEHLER: $e');

      if (!mounted) return;

      setState(() {
        status = 'GitHub nicht erreichbar – gespeicherte Predigten verfügbar';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(initialisiereStartdaten());
    githubKonfigurationsTimer = Timer.periodic(const Duration(minutes: 30), (
      _,
    ) async {
      if (!mounted) return;

      if (automatischeSynchronisierungAktiv ||
          hintergrundErfassungAktiv ||
          dateilisteWirdErfasst ||
          videoAnsichtAnzeigen ||
          videoWirdGeladen ||
          predigtVorschauAnzeigen) {
        debugPrint(
          'PREDIGTFINDER AUTOSYNC: '
          '30-Minuten-Abgleich wegen aktiver Nutzung verschoben',
        );
        return;
      }

      await pruefeGitHubKonfiguration();

      if (!mounted) return;

      try {
        await synchronisiereVonGitHub();
      } catch (e) {
        debugPrint('PREDIGTFINDER GITHUB AUTOSYNC FEHLER: $e');
        if (mounted) {
          setState(() {
            status = 'GitHub-Abgleich fehlgeschlagen. Gespeicherte Predigten bleiben erhalten.';
          });
        }
      }
    });

    videoController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'PredigtFinderVideo',
        onMessageReceived: (message) {
          try {
            final daten = jsonDecode(message.message);

            if (daten is Map && daten['typ'] == 'videoOeffnen') {
              debugPrint('PREDIGTFINDER VIDEO ÖFFNEN: ${message.message}');

              // Alte OneDrive-Videoansicht deaktiviert.
              // Videos werden ausschließlich extern über YouTube geöffnet.
            }

            if (daten is Map && daten['typ'] == 'videoSuche') {
              debugPrint(
                'PREDIGTFINDER VIDEOSUCHE: '
                '${message.message}',
              );
            }

            if (daten is Map && daten['typ'] == 'videoListe') {
              debugPrint(
                'PREDIGTFINDER VIDEOS GESAMT: '
                '${daten['anzahl']} MP4-Dateien, '
                '${daten['schritte']} Scrollschritte',
              );
            }
          } catch (e) {
            debugPrint('PREDIGTFINDER VIDEO-DATENFEHLER: $e');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            videoController
                .runJavaScript(r'''
          (() => {
            if (window.predigtFinderCloseObserver) return;

            const hideCloseButton = () => {
              const buttons = document.querySelectorAll(
                'button[aria-label], [role="button"][aria-label]'
              );

              for (const button of buttons) {
                const label = (
                  button.getAttribute('aria-label') || ''
                ).trim().toLowerCase();

                if (label === 'close' || label === 'schließen') {
                  button.style.setProperty(
                    'display', 'none', 'important'
                  );
                }
              }
            };

            hideCloseButton();

            window.predigtFinderCloseObserver =
              new MutationObserver(hideCloseButton);

            window.predigtFinderCloseObserver.observe(
              document.documentElement,
              { childList: true, subtree: true }
            );
          })();
        ''')
                .catchError((error) {
                  debugPrint('PREDIGTFINDER X AUSBLENDEN FEHLER: $error');
                });

            if (!mounted || !videoWirdGeladen) return;

            setState(() {
              videoWirdGeladen = false;
              status = 'Videoseite geladen';
            });

            debugPrint('PREDIGTFINDER VIDEOSEITE GELADEN: $url');
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;

            debugPrint(
              'PREDIGTFINDER VIDEO-NAVIGATIONSFEHLER: '
              '${error.description}',
            );

            if (!mounted || !videoWirdGeladen) return;

            setState(() {
              videoWirdGeladen = false;
              status = 'Videoseite konnte nicht geladen werden';
            });
          },
        ),
      )
      ..loadHtmlString('<html><body></body></html>');
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'PredigtFinder',
        onMessageReceived: (message) {
          debugPrint(
            'PREDIGTFINDER NACHRICHT: '
            '${message.message.length} Zeichen empfangen',
          );
          try {
            final daten = jsonDecode(message.message);

            if (daten is Map && daten['typ'] == 'iosEditorFehlt') {
              if (defaultTargetPlatform == TargetPlatform.iOS) {
                final dateiname = daten['dateiname']?.toString() ?? '';
                final meldung = 'iOS Editor fehlt: $dateiname';

                if (!syncDiagnose.any((eintrag) => eintrag.contains(meldung))) {
                  protokolliereSyncDiagnose(meldung);
                }
              }
            }
            if (daten is Map && daten['typ'] == 'modellPruefung') {
              if (defaultTargetPlatform == TargetPlatform.iOS) {
                final erwartet = daten['erwartet']?.toString() ?? '';
                final aktuell = daten['aktuell']?.toString() ?? '';
                final zeichen = daten['textZeichen'];

                if (zeichen is num) {
                  protokolliereSyncDiagnose(
                    'iOS Textpruefung: erwartet=$erwartet | '
                    'aktuell=$aktuell | Zeichen=$zeichen',
                  );
                }
              }
              debugPrint(
                'PREDIGTFINDER MODELLPRÜFUNG: '
                'erwartet=${daten['erwartet']} | '
                'aktuell=${daten['aktuell']} | '
                'modellUri=${daten['modellUri']} | '
                'ersteZeile=${daten['ersteZeile']} | '
                'zeichen=${daten['textZeichen']}',
              );
            }

            if (daten is Map && daten['typ'] == 'dateinameTest') {
              if (defaultTargetPlatform == TargetPlatform.iOS) {
                protokolliereSyncDiagnose(
                  'iOS DATEITEST: '
                  'Datei=${daten['dateiname']} | '
                  'TXT=${daten['dateinameGueltig']} | '
                  'Video=${daten['videoDateiname']} | '
                  'MP4=${daten['videoGueltig']} | '
                  'Zeichen=${daten['textZeichen']}',
                );
              }
            }
            if (daten is Map && daten['typ'] == 'predigtInhalt') {
              final video = daten['videoDateiname'];

              if (!hintergrundErfassungAktiv &&
                  video is String &&
                  video.toLowerCase().endsWith('.mp4')) {
                debugPrint('PREDIGTFINDER VIDEOZUORDNUNG: $video');

                oeffneVideoDirekt(video);
              }
            }
            if (daten is Map && daten['typ'] == 'iosSchliessDiagnose') {
              if (defaultTargetPlatform == TargetPlatform.iOS) {
                final anzahl = daten['kandidaten'];
                final schaltflaechen = daten['schaltflaechen'];

                protokolliereSyncDiagnose(
                  'iOS Vorschau: $anzahl Schliess-Kandidaten | '
                  'Buttons: $schaltflaechen',
                );
              }
            }
            if (daten is Map && daten['typ'] == 'dateiOeffnen') {
              if (daten['erfolg'] == true && mounted) {
                setState(() {
                  predigtVorschauAnzeigen = false;
                  status = 'Ermittle zugehöriges Video ...';
                });

                final dateiname = daten['dateiname'];

                if (dateiname is String) {
                  waitForPredigtText(dateiname);
                }
              }
            }

            if (daten is Map && daten['typ'] == 'dateilisteFehler') {
              if (daten['laufId'] == dateilisteLaufnummer &&
                  dateilisteCompleter != null &&
                  !dateilisteCompleter!.isCompleted) {
                final meldung =
                    daten['meldung']?.toString() ?? 'Unbekannter Fehler';
                protokolliereSyncDiagnose('FEHLER: $meldung');
                dateilisteCompleter!.completeError(StateError(meldung));
              }
              return;
            }

            if (daten is Map && daten['typ'] == 'syncDiagnose') {
              final meldung = daten['meldung'];
              final laufId = daten['laufId'];

              if (laufId == dateilisteLaufnummer &&
                  dateilisteCompleter != null &&
                  !dateilisteCompleter!.isCompleted &&
                  meldung is String) {
                protokolliereSyncDiagnose(meldung);

                if (meldung == 'iOS-Scrolllimit nach 60 Sekunden erreicht' &&
                    dateilisteCompleter != null &&
                    !dateilisteCompleter!.isCompleted) {
                  dateilisteCompleter!.completeError(
                    StateError(
                      'iOS-Dateierfassung: 60-Sekunden-Limit erreicht',
                    ),
                  );
                }
              }
            }

            if (daten is Map && daten['typ'] == 'dateilisteFortschritt') {
              final anzahl = daten['anzahl'];
              final schritte = daten['schritte'];

              protokolliereSyncDiagnose(
                'Fortschritt: $anzahl Dateien, $schritte Scrollschritte',
              );
              if (mounted) {
                setState(() {
                  dateilisteGefunden = (daten['anzahl'] as num?)?.toInt() ?? 0;
                  status = '$dateilisteGefunden TXT-Dateien gefunden ...';
                });
              }
            }
            if (daten is Map && daten['dateien'] is List) {
              final empfangeneLaufnummer = daten['laufId'];

              if (empfangeneLaufnummer != dateilisteLaufnummer ||
                  dateilisteCompleter == null ||
                  dateilisteCompleter!.isCompleted) {
                debugPrint(
                  'PREDIGTFINDER DATEILISTE VERALTET: '
                  '$empfangeneLaufnummer',
                );
                return;
              }

              final dateien =
                  (daten['dateien'] as List)
                      .whereType<String>()
                      .where((name) => name.toLowerCase().endsWith('.txt'))
                      .toSet()
                      .toList()
                    ..sort();

              if (!mounted) return;

              setState(() {
                predigtDateien
                  ..clear()
                  ..addAll(dateien);

                // Dateiliste vollständig empfangen
                dateilisteGefunden = dateien.length;
                dateilisteWirdErfasst = false;

                markierteDatei = null;

                status = '${predigtDateien.length} Predigtdateien erfasst';
              });

              if (dateilisteCompleter != null &&
                  !dateilisteCompleter!.isCompleted) {
                dateilisteCompleter!.complete(dateien);
              }
            }
            if (daten is Map && daten['typ'] == 'predigtInhalt') {
              final dateiname = daten['dateiname'];
              final inhalt = daten['inhalt'];
              final video = daten['videoDateiname'];

              if (dateiname is String &&
                  dateiname.toLowerCase().endsWith('.txt') &&
                  inhalt is String &&
                  inhalt.isNotEmpty &&
                  video is String &&
                  video.toLowerCase().endsWith('.mp4')) {
                if (!mounted) return;

                setState(() {
                  predigtTexte[dateiname] = inhalt;
                  videoDateinamen[dateiname] = video;

                  status = '${predigtTexte.length} Predigttexte gespeichert';
                });

                unawaited(
                  speicherePredigtenLokal().catchError((Object fehler) {
                    debugPrint('PREDIGTFINDER SPEICHERFEHLER: $fehler');
                  }),
                );

                debugPrint(
                  'PREDIGTFINDER GESPEICHERT: '
                  '$dateiname | ${inhalt.length} Zeichen | $video',
                );
              }
            }
          } catch (e) {
            debugPrint('PREDIGTFINDER DATENFEHLER: $e');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('PREDIGTFINDER ONEDRIVE1 NAVIGATION START: $url');

            if (!mounted) return;

            setState(() {
              isLoading = true;
              status = 'OneDrive wird geladen ...';
            });
          },

          onPageFinished: (url) {
            debugPrint('PREDIGTFINDER ONEDRIVE1 NAVIGATION ENDE: $url');

            if (!mounted) return;

            setState(() {
              isLoading = false;
              status = 'Seite geladen – Ordnerinhalt prüfen';
            });
          },
        ),
      );
  }

  Future<bool> stelleOneDriveDateilisteWiederHer() async {
    debugPrint('PREDIGTFINDER WIEDERHERSTELLUNG: Starte');

    try {
      await controller.loadRequest(Uri.parse(aktiveOneDriveUrl));

      final bereit = await warteAufPredigtDateiliste();

      if (!bereit) {
        debugPrint(
          'PREDIGTFINDER WIEDERHERSTELLUNG: '
          'Dateiliste nicht bereit',
        );
        return false;
      }

      debugPrint('PREDIGTFINDER WIEDERHERSTELLUNG: Erfolgreich');

      return true;
    } catch (e) {
      debugPrint('PREDIGTFINDER WIEDERHERSTELLUNG FEHLER: $e');
      return false;
    }
  }

  Future<bool> testClosePreview() async {
    try {
      final result = await controller.runJavaScriptReturningResult(r'''
      (() => {
        const buttons = Array.from(
          document.querySelectorAll(
            'button, [role="button"]'
          )
        );

       
const kandidaten = buttons.filter(el => {
  const label = (
    el.getAttribute('aria-label') ||
    el.getAttribute('title') ||
    ''
  ).trim().toLowerCase();

  return [
    'close',
    'schließen',
    'schliessen',
    'close preview',
    'vorschau schließen'
  ].includes(label);
});


        // iOS-Diagnose: Schaltflächen erfassen, Verhalten unverändert.
        if (kandidaten.length !== 1) {
          const details = buttons.map(el => ({
            label: el.getAttribute('aria-label') || '',
            title: el.getAttribute('title') || ''
          })).filter(e => e.label || e.title).slice(0, 20);

          PredigtFinder.postMessage(JSON.stringify({
            typ: 'iosSchliessDiagnose',
            kandidaten: kandidaten.length,
            schaltflaechen: details
          }));
        }
        if (kandidaten.length !== 1) {
          return false;
        }

        kandidaten[0].click();

        return true;
      })();
    ''');

      final erfolg = result == true || result.toString() == 'true';

      debugPrint('PREDIGTFINDER TXT SCHLIESSEN: $erfolg');

      return erfolg;
    } catch (e) {
      debugPrint('PREDIGTFINDER SCHLIESSEN-FEHLER: $e');
      return false;
    }
  }

  Future<void> waitForPredigtText(String erwarteterDateiname) async {
    try {
      for (int versuch = 0; versuch < 20; versuch++) {
        final result = await controller.runJavaScriptReturningResult('''
        (() => {
          const erwarteterName = ${jsonEncode(erwarteterDateiname)};

          const dateiPfad = new URL(
            window.location.href
          ).searchParams.get('id') || '';

          const aktuellerName =
            ${defaultTargetPlatform == TargetPlatform.iOS ? 'decodeURIComponent(' : ''}dateiPfad.split('/').pop() || ''${defaultTargetPlatform == TargetPlatform.iOS ? ')' : ''};

          if (
            typeof window.monaco === 'undefined' ||
            !window.monaco.editor
          ) {
            PredigtFinder.postMessage(JSON.stringify({
              typ: 'iosEditorFehlt',
              dateiname: erwarteterName
            }));
            return false;
          }

          const models = window.monaco.editor.getModels();

          const modellText = models.length > 0
            ? models[0].getValue()
            : '';

          const modellUri = models.length > 0
            ? models[0].uri.toString()
            : '';

          PredigtFinder.postMessage(JSON.stringify({
            typ: 'modellPruefung',
            erwartet: erwarteterName,
            aktuell: aktuellerName,
            modellUri: modellUri,
            textZeichen: modellText.length,
            ersteZeile:
              modellText.split(String.fromCharCode(10))[0].trim()
          }));

          const normalisieren = name =>
  name.normalize('NFC')
      .replace(/\\s+/g, ' ')
      .trim();

return normalisieren(aktuellerName) ===
       normalisieren(erwarteterName) &&
                 modellText.length > 0;
        })();
      ''');

        if (result == true || result.toString() == 'true') {
          debugPrint('PREDIGTFINDER TEXT BEREIT');

          await testTextPreview();
          return;
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }

      debugPrint('PREDIGTFINDER FEHLER: Predigttext nicht geladen');
    } catch (e) {
      debugPrint('PREDIGTFINDER WARTEFEHLER: $e');
    }
  }

  Future<void> testTextPreview() async {
    try {
      await controller.runJavaScript(r'''
      (() => {
        if (
          typeof window.monaco === 'undefined' ||
          !window.monaco.editor
        ) {
          PredigtFinder.postMessage(JSON.stringify({
            typ: 'textFehler',
            fehler: 'Monaco nicht verfügbar'
          }));
          return;
        }

        const models = window.monaco.editor.getModels();

        if (models.length === 0) {
          PredigtFinder.postMessage(JSON.stringify({
            typ: 'textFehler',
            fehler: 'Kein Textmodell gefunden'
          }));
          return;
        }

        const text = models[0].getValue();
const dateiPfad = new URL(
  window.location.href
).searchParams.get('id') || '';

const dateiname = decodeURIComponent(
  dateiPfad.split('/').pop() || ''
);

const videoDateiname = (
  text.split(/\r?\n/)[0] || ''
).trim();

PredigtFinder.postMessage(JSON.stringify({
  typ: 'dateinameTest',
  dateiname: dateiname,
  dateinameGueltig: dateiname.toLowerCase().endsWith('.txt'),
  videoDateiname: videoDateiname,
  videoGueltig: videoDateiname.toLowerCase().endsWith('.mp4'),
  textZeichen: text.length
}));

if (
  dateiname.toLowerCase().endsWith('.txt') &&
  videoDateiname.toLowerCase().endsWith('.mp4')
) {
  PredigtFinder.postMessage(JSON.stringify({
    typ: 'predigtInhalt',
    dateiname: dateiname,
    videoDateiname: videoDateiname,
    inhalt: text
  }));
}

        const zeilen = text.split(/\r?\n/);

        PredigtFinder.postMessage(JSON.stringify({
          typ: 'predigtAnalyse',
          videoDateiname: videoDateiname,
          videoGueltig: /\.mp4$/i.test(videoDateiname),
          textZeichen: text.length,
          textZeilen: zeilen.length
        }));
      })();
    ''');
    } catch (e) {
      debugPrint('PREDIGTFINDER TEXTFEHLER: $e');
    }
  }

  Future<void> testVideoFileList() async {
    try {
      await videoController.runJavaScript(r'''
      (async () => {
        const liste = Array.from(
          document.querySelectorAll('[id^="html-list_"]')
        ).find(el => el.scrollHeight > el.clientHeight);

        if (!liste) {
          console.log('PREDIGTFINDER: Videoliste nicht gefunden');
          return;
        }

        const videos = new Set();

        const sammeln = () => {
          const zeilen = document.querySelectorAll('[role="row"]');

          for (const zeile of zeilen) {
            const name = (zeile.innerText || '')
              .split(String.fromCharCode(10))[0]
              .trim();

            if (name.toLowerCase().endsWith('.mp4')) {
              videos.add(name);
            }
          }
        };

        const warten = ms =>
          new Promise(resolve => setTimeout(resolve, ms));

        liste.scrollTop = 0;
        await warten(1000);

        let schritte = 0;
        let stillstand = 0;

        while (schritte < 600) {
          sammeln();

          const vorher = liste.scrollTop;
          const maximum =
            liste.scrollHeight - liste.clientHeight;

if (vorher >= maximum - 2) {
  await warten(5000);
  sammeln();

  const neuesMaximum =
    liste.scrollHeight - liste.clientHeight;

  if (neuesMaximum <= maximum + 2) {
    break;
  }

  continue;
}
          liste.scrollTop = Math.min(
            vorher + Math.max(100, liste.clientHeight / 2),
            maximum
          );

          await warten(1200);
          schritte++;

          if (liste.scrollTop <= vorher) {
            stillstand++;
            if (stillstand >= 3) break;
          } else {
            stillstand = 0;
          }
        }

        await warten(700);
        sammeln();

PredigtFinderVideo.postMessage(JSON.stringify({
  typ: 'videoListe',
  anzahl: videos.size,
  schritte: schritte,
  scrollHoehe: liste.scrollHeight,
  sichtHoehe: liste.clientHeight,
  endPosition: liste.scrollTop,
  dateien: Array.from(videos).sort()
}));      })();
    ''');
    } catch (e) {
      debugPrint('PREDIGTFINDER VIDEO-FEHLER: $e');
    }
  }

  Future<void> testFileElement() async {
    try {
      final result = await controller.runJavaScriptReturningResult(r'''
(() => {
  const markierteZeilen = Array.from(
    document.querySelectorAll('[role="row"][aria-selected="true"]')
  );

  if (markierteZeilen.length !== 1) {
    return JSON.stringify({
      erfolg: false,
      meldung: 'Bitte genau eine Datei markieren',
      anzahl: markierteZeilen.length
    });
  }

  const zeile = markierteZeilen[0];

  const dateiname = (zeile.innerText || '')
    .split(String.fromCharCode(10))[0]
    .trim();

  if (!dateiname.toLowerCase().endsWith('.txt')) {
    return JSON.stringify({
      erfolg: false,
      meldung: 'Die markierte Datei ist keine TXT-Datei'
    });
  }

  zeile.dispatchEvent(
    new MouseEvent('dblclick', {
      bubbles: true,
      cancelable: true,
      view: window
    })
  );

  return JSON.stringify({
    erfolg: true,
    dateiname: dateiname,
    meldung: 'Öffnen der markierten Datei ausgelöst'
  });
})();
    ''');

      debugPrint('PREDIGTFINDER ÖFFNEN: $result');
    } catch (e) {
      debugPrint('PREDIGTFINDER ÖFFNEN FEHLER: $e');
    }
  }

  Future<List<String>> erfasseDateilisteMitTimeout() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return erfasseIosDateilisteSchrittweise();
    }
    if (dateilisteWirdErfasst) {
      throw StateError('Dateilisten-Erfassung läuft bereits');
    }

    final completer = Completer<List<String>>();
    dateilisteCompleter = completer;

    try {
      unawaited(testFileList());

      final dateien = await completer.future.timeout(
        const Duration(seconds: 90),
      );

      debugPrint(
        'PREDIGTFINDER AUTOSYNC DATEILISTE: '
        '${dateien.length} TXT-Dateien',
      );

      return dateien;
    } finally {
      if (identical(dateilisteCompleter, completer)) {
        dateilisteCompleter = null;
      }

      if (mounted) {
        setState(() {
          dateilisteWirdErfasst = false;
        });
      }
    }
  }

  // iOS: Jeder WebView-Aufruf ist synchron und kurz. Flutter steuert die
  // Pausen; dadurch läuft keine lange JavaScript-Promise in WKWebView.
  Future<List<String>> erfasseIosDateilisteSchrittweise() async {
    if (dateilisteWirdErfasst) {
      throw StateError('Dateilisten-Erfassung läuft bereits');
    }
    final lauf = ++dateilisteLaufnummer;
    final gefunden = <String>{};
    final beginn = DateTime.now();
    var stabil = 0;
    var stillstand = 0;
    var letzteHoehe = -1;
    var letzteAnzahl = -1;
    var endeErreicht = false;

    setState(() {
      dateilisteWirdErfasst = true;
      dateilisteGefunden = 0;
      status = 'iOS-Dateiliste wird schrittweise erfasst ...';
    });
    protokolliereSyncDiagnose('iOS: Flutter-gesteuerte Erfassung gestartet');
    try {
      for (var schritt = 0; schritt < 220; schritt++) {
        if (!mounted) throw StateError('Ansicht wurde geschlossen');
        if (DateTime.now().difference(beginn) > const Duration(seconds: 115)) {
          throw TimeoutException('iOS-Dateiliste: Zeitlimit 115 Sekunden');
        }
        // JavaScript liefert sofort eine JSON-Zeichenfolge zurück.
        final antwort = await controller
            .runJavaScriptReturningResult(r'''
          (() => {
            const liste = Array.from(
              document.querySelectorAll('[id^="html-list_"]')
            ).find(el => el.scrollHeight > el.clientHeight);
            if (!liste) return JSON.stringify({fehler: 'Scrollbereich fehlt'});
            const namen = new Set();
            const add = wert => {
              const name = (wert || '').trim();
              if (name.length > 4 && name.length < 260 &&
                  name.toLowerCase().endsWith('.txt') &&
                  !name.includes('/') && !name.includes(String.fromCharCode(92))) {
                namen.add(name);
              }
            };
            for (const el of document.querySelectorAll(
              '[title], [aria-label], [role="row"]'
            )) {
              add(el.getAttribute('title'));
              add(el.getAttribute('aria-label'));
              if (el.getAttribute('role') === 'row') {
                add((el.innerText || '').split(String.fromCharCode(10))[0]);
              }
            }
            const vorher = liste.scrollTop;
            const maximum = Math.max(0, liste.scrollHeight - liste.clientHeight);
            const amEnde = vorher >= maximum - 2;
            if (!amEnde) {
              liste.scrollTop = Math.min(
                vorher + Math.max(100, liste.clientHeight / 2), maximum
              );
            }
            return JSON.stringify({
              dateien: Array.from(namen),
              vorher: vorher, nachher: liste.scrollTop,
              hoehe: liste.scrollHeight, maximum: maximum,
              amEnde: amEnde
            });
          })();
        ''')
            .timeout(const Duration(seconds: 12));
        // iOS liefert normalerweise einen JSON-String; Android ist hier
        // nicht betroffen. Eventuelle zusätzliche Anführungszeichen abfangen.
        dynamic daten = antwort;
        if (daten is String) daten = jsonDecode(daten);
        if (daten is String) daten = jsonDecode(daten);
        if (daten is! Map) throw const FormatException('Ungültige iOS-Antwort');
        if (daten['fehler'] != null) throw StateError('${daten['fehler']}');
        final liste = daten['dateien'];
        if (liste is! List) throw const FormatException('Dateiliste fehlt');
        gefunden.addAll(liste.whereType<String>());
        final vorher = (daten['vorher'] as num).toDouble();
        final nachher = (daten['nachher'] as num).toDouble();
        final hoehe = (daten['hoehe'] as num).toInt();
        final amEnde = daten['amEnde'] == true;
        if (schritt % 4 == 0 || amEnde) {
          protokolliereSyncDiagnose(
            'Schritt $schritt: ${gefunden.length} Dateien, '
            'Scroll ${nachher.toStringAsFixed(0)}, Höhe $hoehe, Ende $amEnde',
          );
        }
        if (mounted) {
          setState(() {
            dateilisteGefunden = gefunden.length;
            status = '${gefunden.length} TXT-Dateien gefunden ...';
          });
        }
        if (amEnde) {
          if (hoehe == letzteHoehe && gefunden.length == letzteAnzahl) {
            stabil++;
          } else {
            stabil = 0;
          }
          letzteHoehe = hoehe;
          letzteAnzahl = gefunden.length;
          if (stabil >= 5 && gefunden.isNotEmpty) {
            endeErreicht = true;
            break;
          }
          // OneDrive kann am Ende weitere virtuelle Zeilen nachladen.
          await Future.delayed(const Duration(milliseconds: 1100));
        } else {
          if (nachher <= vorher + 1) {
            stillstand++;
            if (stillstand >= 4) {
              throw StateError('iOS-Scrollbereich bewegt sich nicht');
            }
          } else {
            stillstand = 0;
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      if (!endeErreicht) {
        throw StateError(
          'Dateiliste nicht vollständig erfasst '
          '(${gefunden.length} Dateien)',
        );
      }
      if (lauf != dateilisteLaufnummer) {
        throw StateError('Dateilisten-Lauf wurde ersetzt');
      }
      // Eine offensichtlich kleinere Liste nicht als vollständigen Bestand
      // übernehmen; insbesondere die vorhandenen 82 Predigten schützen.
      if (gefunden.length < predigtTexte.length) {
        throw StateError(
          'Nur ${gefunden.length} Dateien erkannt; '
          '${predigtTexte.length} Predigten sind bereits gespeichert',
        );
      }
      final dateien = gefunden.toList()..sort();
      protokolliereSyncDiagnose(
        'iOS-Dateiliste abgeschlossen: ${dateien.length} Dateien',
      );
      if (mounted) {
        setState(() {
          predigtDateien
            ..clear()
            ..addAll(dateien);
          dateilisteGefunden = dateien.length;
          status = '${dateien.length} Predigtdateien erfasst';
        });
      }
      return dateien;
    } catch (e) {
      protokolliereSyncDiagnose('iOS-Dateiliste fehlgeschlagen: $e');
      rethrow;
    } finally {
      if (mounted) setState(() => dateilisteWirdErfasst = false);
    }
  }

  // iOS: asynchronen WebView-Auftrag ohne langes Await starten.
  Future<void> starteIosDateiliste(int laufnummer) async {
    await controller.runJavaScript('''
      (() => {
        const laufId = $laufnummer;
        const senden = daten => PredigtFinder.postMessage(
          JSON.stringify({laufId: laufId, ...daten})
        );
        const warten = ms => new Promise(r => setTimeout(r, ms));
        const arbeiten = async () => {
          senden({typ: 'syncDiagnose', meldung: 'iOS-Erfassung gestartet'});
          const liste = Array.from(document.querySelectorAll('[id^="html-list_"]'))
            .find(el => el.scrollHeight > el.clientHeight);
          if (!liste) throw Error('Scrollbereich nicht gefunden');
          const gefunden = new Set();
          const sammeln = () => {
            for (const el of document.querySelectorAll('[title], [aria-label], [role="row"]')) {
              const namen = [el.getAttribute('title'), el.getAttribute('aria-label')];
              if (el.getAttribute('role') === 'row') {
                namen.push((el.innerText || '').split(String.fromCharCode(10))[0]);
              }
              for (const wert of namen) {
                const name = (wert || '').trim();
                if (name.length > 4 && name.length < 260 &&
                    name.toLowerCase().endsWith('.txt') &&
                    !name.includes('/')) gefunden.add(name);
              }
            }
          };
          liste.scrollTop = 0;
          await warten(700);
          sammeln();
          let stillstand = 0;
          let stabil = 0;
          let letzteHoehe = -1;
          let letzteAnzahl = -1;
          const beginn = Date.now();
          for (let schritt = 0; schritt < 180 && Date.now() - beginn < 70000; schritt++) {
            sammeln();
            const vorher = liste.scrollTop;
            const maximum = Math.max(0, liste.scrollHeight - liste.clientHeight);
            if (vorher >= maximum - 2) {
              await warten(1000);
              sammeln();
              if (liste.scrollHeight === letzteHoehe &&
                  gefunden.size === letzteAnzahl) stabil++;
              else stabil = 0;
              letzteHoehe = liste.scrollHeight;
              letzteAnzahl = gefunden.size;
              if (stabil >= 4) {
                if (gefunden.size === 0) throw Error('Keine TXT-Dateien gefunden');
                senden({typ: 'syncDiagnose', meldung: 'Listenende erreicht: ' + gefunden.size});
                senden({dateien: Array.from(gefunden).sort(), anzahl: gefunden.size,
                  schritte: schritt});
                return;
              }
              liste.scrollTop = liste.scrollHeight;
            } else {
              liste.scrollTop = Math.min(vorher + Math.max(100, liste.clientHeight / 2), maximum);
              await warten(450);
              if (liste.scrollTop <= vorher + 1) {
                stillstand++;
                if (stillstand >= 4) throw Error('Scrollposition bewegt sich nicht');
              } else stillstand = 0;
            }
            if (schritt % 3 === 0) {
              senden({typ: 'dateilisteFortschritt', anzahl: gefunden.size, schritte: schritt});
              senden({typ: 'syncDiagnose', meldung: 'Scroll ' + schritt +
                ': ' + liste.scrollTop + '/' + maximum + ', Dateien ' + gefunden.size});
            }
          }
          throw Error('Listenende nicht sicher erreicht (' + gefunden.size + ' Dateien)');
        };
        void arbeiten().catch(e => senden({typ: 'dateilisteFehler',
          meldung: String(e && e.message || e)}));
      })();
    ''');
  }

  Future<void> testFileList() async {
    if (dateilisteWirdErfasst) return;

    final laufnummer = ++dateilisteLaufnummer;

    debugPrint('PREDIGTFINDER DATEILISTE START: Lauf $laufnummer');

    setState(() {
      dateilisteWirdErfasst = true;
      dateilisteGefunden = 0;
      status = 'Dateiliste wird erfasst ...';
    });
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await starteIosDateiliste(laufnummer);
        return;
      }
      await controller.runJavaScript('''
      (async () => {
        const laufId = $laufnummer;

        PredigtFinder.postMessage(JSON.stringify({
          typ: 'syncDiagnose',
          meldung: 'JavaScript gestartet',
          laufId: laufId
        }));

        const list = Array.from(
          document.querySelectorAll('*')
        ).find(el =>
          el.id.startsWith('html-list_') &&
          el.scrollHeight > el.clientHeight
        );

        if (!list) {
          PredigtFinder.postMessage(JSON.stringify({
            typ: 'syncDiagnose',
            meldung: 'FEHLER: Scrollbereich nicht gefunden',
            laufId: laufId
          }));
          return 'Scrollbereich nicht gefunden';
        }

        PredigtFinder.postMessage(JSON.stringify({
          typ: 'syncDiagnose',
          meldung: 'Scrollbereich gefunden',
          laufId: laufId
        }));

        // Temporäre Diagnose der iOS-Dateinamen-Erkennung
        if (laufId === $laufnummer) {
          const bodyText = document.body.innerText || '';

          const txtTreffer =
            bodyText.match(/[.]txt/gi) || [];

          const htmlTreffer = Array.from(
            document.querySelectorAll(
              '[title], [aria-label], [data-automationid]'
            )
          ).filter(el => {
            const text = [
              el.getAttribute('title') || '',
              el.getAttribute('aria-label') || '',
              el.textContent || ''
            ].join(' ');

            return /[.]txt/i.test(text);
          });

          PredigtFinder.postMessage(JSON.stringify({
            typ: 'syncDiagnose',
            laufId: laufId,
            meldung:
              'DOM: ' + bodyText.length +
              ' Zeichen, TXT-Vorkommen: ' +
              txtTreffer.length +
              ', HTML-Treffer: ' +
              htmlTreffer.length +
              ', Scrollposition: ' +
              list.scrollTop +
              ', Scrollhöhe: ' +
              list.scrollHeight
          }));
        }

        const found = new Set();

        const collect = () => {
          // iOS: Dateinamen aus HTML-Attributen erfassen
          if (/iPhone|iPad|iPod/i.test(navigator.userAgent)) {
            const elemente = document.querySelectorAll(
              '[title], [aria-label]'
            );

            for (const el of elemente) {
              for (const attribut of ['title', 'aria-label']) {
                const name = (el.getAttribute(attribut) || '').trim();

                if (name.length > 4 &&
                    name.length < 260 &&
                    name.toLowerCase().endsWith('.txt')) {
                  found.add(name);
                }
              }
            }
          }

          const lines = document.body.innerText.split(
            String.fromCharCode(10)
          );

          for (const line of lines) {
            const name = line.trim();

            if (name.toLowerCase().endsWith('.txt')) {
              found.add(name);
            }
          }
        };

        list.scrollTop = 0;
        await new Promise(r => setTimeout(r, 700));
        collect();

        let lastPosition = -1;
        let steps = 0;

        while (steps < 300) {
          const maxScroll =
            list.scrollHeight - list.clientHeight;

          const nextPosition = Math.min(
            list.scrollTop + Math.max(100, list.clientHeight / 2),
            maxScroll
          );

          if (nextPosition <= lastPosition) {
            break;
          }

          lastPosition = list.scrollTop;
          list.scrollTop = nextPosition;

          await new Promise(r => setTimeout(r, 350));
          collect();

          if (steps % 3 === 0) {
            PredigtFinder.postMessage(JSON.stringify({
              typ: 'dateilisteFortschritt',
              anzahl: found.size,
              schritte: steps
            }));
          }

          steps++;

          if (list.scrollTop >=
              list.scrollHeight - list.clientHeight - 2) {
            let unveraendert = 0;
            let letzteHoehe = list.scrollHeight;
            let letzteAnzahl = found.size;

            while (unveraendert < 5) {
              await new Promise(r => setTimeout(r, 800));
              collect();

              if (list.scrollHeight === letzteHoehe &&
                  found.size === letzteAnzahl) {
                unveraendert++;
              } else {
                unveraendert = 0;
                letzteHoehe = list.scrollHeight;
                letzteAnzahl = found.size;
              }

              list.scrollTop = list.scrollHeight;
            }

            break;
          }
        }

PredigtFinder.postMessage(JSON.stringify({
  typ: 'syncDiagnose',
  laufId: laufId,
  meldung: 'Dateierfassung abgeschlossen: ' +
    found.size + ' Dateien nach ' + steps + ' Scrollschritten'
}));

PredigtFinder.postMessage(JSON.stringify({
  laufId: laufId,
  anzahl: found.size,
  schritte: steps,
  dateien: Array.from(found).sort()
}));

return 'Ergebnis gesendet';      })();
    ''');

      debugPrint('PREDIGTFINDER DATEILISTE: JavaScript gestartet');

      if (!mounted) return;

      setState(() {
        status = 'Dateiliste:  TXT-Dateien gefunden';
      });
    } catch (e) {
      debugPrint('PREDIGTFINDER FEHLER: $e');

      if (dateilisteCompleter != null && !dateilisteCompleter!.isCompleted) {
        dateilisteCompleter!.completeError(e);
      }

      if (!mounted) return;

      setState(() {
        dateilisteWirdErfasst = false;
        status = 'Dateilisten-Erfassung fehlgeschlagen';
      });
    }
  }

  Future<void> testCloseVideoPreview() async {
    try {
      final result = await videoController.runJavaScriptReturningResult(r'''
      (() => {
        const buttons = Array.from(
          document.querySelectorAll('button')
        );

        const kandidaten = buttons
          .filter(button => {
            const label =
              button.getAttribute('aria-label') || '';

            return label.toLowerCase() === 'close';
          })
          .map(button => ({
            tag: button.tagName,
            ariaLabel: button.getAttribute('aria-label'),
            title: button.getAttribute('title') || ''
          }));

        return JSON.stringify({
          anzahl: kandidaten.length,
          kandidaten: kandidaten
        });
      })();
    ''');

      debugPrint('PREDIGTFINDER VIDEO SCHLIESSEN-TEST: $result');
    } catch (e) {
      debugPrint('PREDIGTFINDER VIDEO SCHLIESSEN-FEHLER: $e');
    }
  }

  Future<void> closeVideoPreview() async {
    debugPrint('PREDIGTFINDER VIDEO WIRD GESCHLOSSEN');

    if (mounted) {
      setState(() {
        videoAnsichtAnzeigen = false;
        videoWirdGeladen = false;
        predigtVorschauAnzeigen = false;
        status = 'Zurück zur Predigtliste';
      });
    }

    try {
      await videoController.loadHtmlString('<html><body></body></html>');

      debugPrint('PREDIGTFINDER VIDEO GESCHLOSSEN');
    } catch (e) {
      debugPrint('PREDIGTFINDER VIDEO SCHLIESSEN-FEHLER: $e');
    }
  }

  Future<void> erfassePredigten(int anzahl) async {
    if (hintergrundErfassungAktiv) return;

    if (predigtDateien.isEmpty) {
      setState(() {
        status = 'Bitte zuerst die TXT-Dateiliste einlesen';
      });
      return;
    }

    final bereitsGespeichert = predigtTexte.keys
        .map((name) => name.replaceAll(RegExp(r'\s+'), ' ').trim())
        .toSet();

    final dateien = predigtDateien
        .take(anzahl)
        .where(
          (name) => !bereitsGespeichert.contains(
            name.replaceAll(RegExp(r'\s+'), ' ').trim(),
          ),
        )
        .toList();

    debugPrint(
      'PREDIGTFINDER SYNCHRONISIERUNG: '
      '${predigtDateien.length} Dateien in der Liste, '
      '${dateien.length} noch einzulesen',
    );
    final fehlerhafteDateien = <String>[];
    var erfolgreich = 0;
    var gestoppt = false;

    erfassungAbbrechen = false;
    hintergrundErfassungAktiv = true;

    try {
      for (var index = 0; index < dateien.length; index++) {
        if (!mounted) return;

        final dateiname = dateien[index];

        setState(() {
          status = 'Verarbeite ${index + 1} von ${dateien.length}: $dateiname';
        });

        final normalisiert = dateiname.replaceAll(RegExp(r'\s+'), ' ').trim();

        final alteEintraege = predigtTexte.keys
            .where(
              (name) =>
                  name.replaceAll(RegExp(r'\s+'), ' ').trim() == normalisiert,
            )
            .toList();

        // Vorhandene Daten zunächst sichern
        final alteTexte = {
          for (final name in alteEintraege) name: predigtTexte[name]!,
        };
        final alteVideos = {
          for (final name in alteEintraege)
            if (videoDateinamen.containsKey(name)) name: videoDateinamen[name]!,
        };

        for (final name in alteEintraege) {
          predigtTexte.remove(name);
          videoDateinamen.remove(name);
        }

        var gespeichert = false;
        var geschlossen = false;

        try {
          await openSelectedFile(dateiname);

          for (var versuch = 0; versuch < 60; versuch++) {
            await Future.delayed(const Duration(milliseconds: 500));

            gespeichert = predigtTexte.keys.any(
              (name) =>
                  name.replaceAll(RegExp(r'\s+'), ' ').trim() == normalisiert,
            );

            if (gespeichert) break;
          }

          if (!gespeichert) {
            debugPrint(
              'PREDIGTFINDER SPEICHERDIAGNOSE: '
              'Datei=$dateiname | '
              'Texte=${predigtTexte.length} | '
              'Vorhanden=${predigtTexte.containsKey(dateiname)}',
            );

            throw Exception('Text nicht gespeichert');
          }

          // Erfolgreich eingelesene Predigt
          erfolgreich++;

          // Eventuellen früheren Fehler entfernen.
          synchronisierungsFehler.remove(dateiname);

          debugPrint('PREDIGTFINDER ERFOLGREICH: $dateiname');
        } catch (e) {
          fehlerhafteDateien.add(dateiname);

          // Fehler für den Administrator protokollieren.
          synchronisierungsFehler[dateiname] = e.toString();

          // Vorherige Daten bei einem Fehler wiederherstellen.
          predigtTexte.addAll(alteTexte);
          videoDateinamen.addAll(alteVideos);

          debugPrint('PREDIGTFINDER DATEIFEHLER: $dateiname | $e');
        } finally {
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            // iOS: Nach dem Einleseversuch die Dateiliste
            // kontrolliert wiederherstellen.
            geschlossen = await stelleOneDriveDateilisteWiederHer();
          } else {
            // Android: Bisheriges Verhalten beibehalten.
            geschlossen = await testClosePreview();
          }
        }

        if (!geschlossen && defaultTargetPlatform == TargetPlatform.iOS) {
          debugPrint(
            'PREDIGTFINDER IOS WIEDERHERSTELLUNG FEHLGESCHLAGEN: $dateiname',
          );

          synchronisierungsFehler[dateiname] =
              'iOS: OneDrive-Dateiliste konnte nicht wiederhergestellt werden';

          gestoppt = true;
          break;
        }

        if (!geschlossen) {
          debugPrint('PREDIGTFINDER SCHLIESSFEHLER: $dateiname');
          synchronisierungsFehler[dateiname] =
              'OneDrive-Textvorschau konnte nicht geschlossen werden';

          // Erneut versuchen, die Textvorschau zu schließen.
          for (var versuch = 0; versuch < 3; versuch++) {
            await Future.delayed(const Duration(milliseconds: 800));

            geschlossen = await testClosePreview();

            if (geschlossen) break;
          }

          if (!geschlossen) {
            debugPrint('PREDIGTFINDER WIEDERHERSTELLUNG: $dateiname');

            final wiederhergestellt = await stelleOneDriveDateilisteWiederHer();

            if (!wiederhergestellt) {
              debugPrint(
                'PREDIGTFINDER ABBRUCH: '
                'OneDrive-Dateiliste nicht wiederherstellbar',
              );

              gestoppt = true;
              break;
            }

            debugPrint(
              'PREDIGTFINDER FORTSETZUNG: '
              'Dateiliste wiederhergestellt',
            );
          }
        }

        if (erfassungAbbrechen) {
          debugPrint('PREDIGTFINDER ERFASSUNG ABGEBROCHEN');
          gestoppt = true;
          break;
        }

        await Future.delayed(const Duration(milliseconds: 1000));

        if (!mounted) return;

        setState(() {
          status =
              '${index + 1}/${dateien.length} verarbeitet | '
              '$erfolgreich erfolgreich | '
              '${fehlerhafteDateien.length} Fehler';
        });
      }

      debugPrint(
        'PREDIGTFINDER TEXTERFASSUNG: '
        '$erfolgreich erfolgreich, '
        '${fehlerhafteDateien.length} Fehler, '
        'gestoppt=$gestoppt',
      );

      if (mounted) {
        setState(() {
          status =
              '$erfolgreich Predigten eingelesen, '
              '${fehlerhafteDateien.length} Fehler'
              '${gestoppt ? " – Verarbeitung gestoppt" : ""}';
        });
      }
    } catch (e) {
      debugPrint('PREDIGTFINDER ERFASSUNGSFEHLER: $e');

      if (mounted) {
        setState(() {
          status = 'Erfassungsfehler: $e';
        });
      }
    } finally {
      hintergrundErfassungAktiv = false;
    }
  }

  void abbrechenErfassung() {
    if (!hintergrundErfassungAktiv) return;

    setState(() {
      erfassungAbbrechen = true;
      status = 'Abbruch angefordert – aktuelle Datei abschließen ...';
    });
  }

  Future<void> testDreiPredigten() async {
    await erfassePredigten(10);
  }

  void alleFilterZuruecksetzen() {
    setState(() {
      suchfeld1.clear();
      suchfeld2.clear();
      suchfeld3.clear();

      verknuepfung1 = 'UND';
      verknuepfung2 = 'UND';

      suchErgebnisse.clear();
      suchTrefferzahlen.clear();
      sucheAktiv = false;

      markierteDatei = null;
      videoAnsichtAnzeigen = false;
      predigtVorschauAnzeigen = false;

      status = 'Alle Suchfilter zurückgesetzt';
    });

    debugPrint(
      'PREDIGTFINDER FILTER ZURÜCKGESETZT: '
      '${predigtDateien.length} Dateien in der Liste, '
      '${predigtTexte.length} Texte gespeichert',
    );
  }

  void suchePredigten() {
    final begriffe = [
      suchfeld1.text.trim().toLowerCase(),
      suchfeld2.text.trim().toLowerCase(),
      suchfeld3.text.trim().toLowerCase(),
    ];

    final operatoren = [verknuepfung1, verknuepfung2];

    final aktiveIndizes = [
      for (int i = 0; i < begriffe.length; i++)
        if (begriffe[i].isNotEmpty) i,
    ];

    if (aktiveIndizes.isEmpty) {
      setState(() {
        status = 'Bitte mindestens einen Suchbegriff eingeben';
      });
      return;
    }

    bool passt(String inhalt) {
      final text = inhalt.toLowerCase();

      final werte = aktiveIndizes
          .map((i) => text.contains(begriffe[i]))
          .toList();

      if (werte.length == 1) return werte.first;

      final verbindungen = <String>[
        for (int i = 1; i < aktiveIndizes.length; i++)
          operatoren[aktiveIndizes[i] - 1],
      ];

      // UND wird vor ODER ausgewertet.
      final gruppen = <bool>[];
      var aktuelleGruppe = werte.first;

      for (int i = 0; i < verbindungen.length; i++) {
        if (verbindungen[i] == 'UND') {
          aktuelleGruppe = aktuelleGruppe && werte[i + 1];
        } else {
          gruppen.add(aktuelleGruppe);
          aktuelleGruppe = werte[i + 1];
        }
      }

      gruppen.add(aktuelleGruppe);
      return gruppen.any((wert) => wert);
    }

    int zaehleTreffer(String inhalt) {
      final text = inhalt.toLowerCase();
      var gesamt = 0;

      for (final index in aktiveIndizes) {
        final begriff = begriffe[index];
        var position = 0;

        while (true) {
          final gefunden = text.indexOf(begriff, position);
          if (gefunden < 0) break;

          gesamt++;
          position = gefunden + begriff.length;
        }
      }

      return gesamt;
    }

    final trefferzahlen = <String, int>{};

    final ergebnisse =
        predigtTexte.entries.where((eintrag) => passt(eintrag.value)).map((
          eintrag,
        ) {
          trefferzahlen[eintrag.key] = zaehleTreffer(eintrag.value);
          return eintrag.key;
        }).toList()..sort((a, b) {
          final vergleich = (trefferzahlen[b] ?? 0).compareTo(
            trefferzahlen[a] ?? 0,
          );

          return vergleich != 0 ? vergleich : a.compareTo(b);
        });

    debugPrint(
      'PREDIGTFINDER SUCHERGEBNIS: '
      '${ergebnisse.length} Treffer '
      'in ${predigtTexte.length} geladenen Predigttexten',
    );

    setState(() {
      suchTrefferzahlen
        ..clear()
        ..addAll(trefferzahlen);

      suchErgebnisse
        ..clear()
        ..addAll(ergebnisse);

      sucheAktiv = true;
      markierteDatei = null;
      videoAnsichtAnzeigen = false;
      predigtVorschauAnzeigen = false;

      status =
          '${ergebnisse.length} Treffer in '
          '${predigtTexte.length} geladenen Predigttexten';
    });
  }

  Future<void> pruefeAktuelleVideoAdresse() async {
    try {
      final url = await videoController.currentUrl();

      debugPrint('PREDIGTFINDER VIDEO-ADRESSE: $url');
    } catch (e) {
      debugPrint('PREDIGTFINDER VIDEO-ADRESSFEHLER: $e');
    }
  }

  Future<void> videoImBrowserOeffnen(String videoName) async {
    final link = videoDirektlinks[videoName];

    if (link == null ||
        !RegExp(
          r'^https://(www\.)?(youtube\.com/watch\?v=|youtu\.be/)',
        ).hasMatch(link)) {
      if (!mounted) return;
      setState(() {
        status = 'Dieses Video ist noch nicht auf YouTube verfügbar';
      });
      return;
    }

    try {
      final erfolg = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );

      if (!erfolg && mounted) {
        setState(() {
          status = 'Browser konnte nicht geöffnet werden';
        });
      }
    } catch (e) {
      debugPrint('PREDIGTFINDER BROWSERFEHLER: $e');
      if (!mounted) return;
      setState(() {
        status = 'Fehler beim Öffnen des Browsers';
      });
    }
  }

  Future<void> oeffneVideoDirekt(String videoName) async {
    debugPrint('PREDIGTFINDER: Video im Browser öffnen: $videoName');

    await videoImBrowserOeffnen(videoName);
  }

  Future<void> ladeOneDriveVideoOrdner() async {
    try {
      await pruefeGitHubKonfiguration();

      if (!mounted) return;

      setState(() {
        videoWirdGeladen = true;
        status = 'Lade OneDrive-Videoordner ...';
      });

      debugPrint('PREDIGTFINDER VIDEOORDNER: $aktiveOneDriveVideoUrl');

      await videoController.loadRequest(Uri.parse(aktiveOneDriveVideoUrl));
    } catch (e) {
      debugPrint('PREDIGTFINDER VIDEOORDNER FEHLER: $e');

      if (!mounted) return;

      setState(() {
        videoWirdGeladen = false;
        status = 'Videoordner konnte nicht geladen werden';
      });
    }
  }

  Future<bool> warteAufVideoDateiliste() async {
    for (int versuch = 0; versuch < 30; versuch++) {
      if (!mounted) return false;

      try {
        final ergebnis = await videoController.runJavaScriptReturningResult(r'''
          (() => {
            const liste = Array.from(
              document.querySelectorAll('[id^="html-list_"]')
            ).find(el => el.scrollHeight > el.clientHeight);

            return liste !== undefined;
          })();
        ''');

        if (ergebnis == true || ergebnis.toString() == 'true') {
          debugPrint('PREDIGTFINDER VIDEOLISTE BEREIT');
          return true;
        }
      } catch (e) {
        debugPrint('PREDIGTFINDER VIDEOLISTE WARTE: $e');
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    debugPrint('PREDIGTFINDER VIDEOLISTE TIMEOUT');
    return false;
  }

  Future<void> openSelectedVideo(String videoName) async {
    try {
      if (!mounted) return;

      setState(() {
        videoAnsichtAnzeigen = true;
        aktuellerVideoDateiname = videoName;
        aktuellerVideoTitel = videoName.replaceFirst(
          RegExp(r'\.mp4$', caseSensitive: false),
          '',
        );
        predigtVorschauAnzeigen = false;
        status = 'Suche und öffne Video ...';
      });

      await WidgetsBinding.instance.endOfFrame;

      await Future.delayed(const Duration(milliseconds: 500));

      await videoController.runJavaScript('''
      (async () => {
        const gesuchterName = ${jsonEncode(videoName)};

        const senden = daten =>
          PredigtFinderVideo.postMessage(
            JSON.stringify(daten)
          );

        const warten = ms =>
          new Promise(resolve => setTimeout(resolve, ms));

        const liste = Array.from(
          document.querySelectorAll('[id^="html-list_"]')
        ).find(el => el.scrollHeight > el.clientHeight);

        if (!liste) {
          senden({
            typ: 'videoSuche',
            erfolg: false,
            meldung: 'Videoliste nicht gefunden'
          });
          return;
        }

        liste.scrollTop = 0;
        await warten(1000);

        let schritte = 0;
        let treffer = [];
        let endeErreicht = false;

        senden({
          typ: 'videoSuche',
          phase: 'gestartet',
          dateiname: gesuchterName
        });

        while (schritte < 600) {
          treffer = Array.from(
            document.querySelectorAll('[role="row"]')
          ).filter(el => {
            const name = (el.innerText || '')
              .split(String.fromCharCode(10))[0]
              .trim();

            return name === gesuchterName;
          });

          if (treffer.length > 0) break;

          const vorher = liste.scrollTop;
          const maximum =
            liste.scrollHeight - liste.clientHeight;

          if (vorher >= maximum - 2) {
            await warten(1500);

            if (
              liste.scrollHeight - liste.clientHeight
              <= maximum + 2
            ) {
              endeErreicht = true;
              break;
            }
            continue;
          }

          liste.scrollTop = Math.min(
            vorher + Math.max(100, liste.clientHeight / 2),
            maximum
          );

          await warten(500);
          schritte++;
        }

if (treffer.length === 1) {
  treffer[0].dispatchEvent(
    new MouseEvent('dblclick', {
      bubbles: true,
      cancelable: true,
      view: window
    })
  );

  senden({
    typ: 'videoOeffnen',
    erfolg: true,
    dateiname: gesuchterName,
    meldung: 'Videoöffnung ausgelöst'
  });
} else {
  senden({
    typ: 'videoOeffnen',
    erfolg: false,
    dateiname: gesuchterName,
    anzahlTreffer: treffer.length,
    meldung: 'Video nicht eindeutig gefunden'
  });
}      })();
    ''');
    } catch (e) {
      debugPrint('PREDIGTFINDER VIDEOSUCHE FEHLER: $e');
    }
  }

  Future<void> openSelectedFile(String dateiname) async {
    try {
      await controller.runJavaScript('''
      (async () => {
        const dateiname = ${jsonEncode(dateiname)};

        const senden = (daten) => {
          PredigtFinder.postMessage(JSON.stringify(daten));
        };

        const liste = Array.from(
          document.querySelectorAll('[id^="html-list_"]')
        ).find(el => el.scrollHeight > el.clientHeight);

        if (!liste) {
          senden({
            typ: 'dateisuche',
            erfolg: false,
            dateiname: dateiname,
            meldung: 'OneDrive-Liste nicht gefunden'
          });
          return;
        }

        const warten = (ms) =>
          new Promise(resolve => setTimeout(resolve, ms));

        const findeDatei = () => {
          return Array.from(
            document.querySelectorAll('[role="row"]')
          ).filter(el => {
            const name = (el.innerText || '')
              .split(String.fromCharCode(10))[0]
              .trim();

            return name === dateiname;
          });
        };

        liste.scrollTop = 0;
        await warten(1000);

        let schritte = 0;
        let treffer = [];
        let endeErreicht = false;

while (schritte < 600) {
          treffer = findeDatei();

          if (treffer.length > 0) {
            break;
          }

          const altePosition = liste.scrollTop;
          const maximalePosition =
            liste.scrollHeight - liste.clientHeight;

          if (altePosition >= maximalePosition - 2) {
            endeErreicht = true;
            break;
          }

          liste.scrollTop = Math.min(
            altePosition + Math.max(100, liste.clientHeight / 2),
            maximalePosition
          );

          await warten(500);
          schritte++;

          if (liste.scrollTop <= altePosition) {
            endeErreicht = true;
            break;
          }
        }

        if (treffer.length !== 1) {
          senden({
            typ: 'dateisuche',
            erfolg: false,
            dateiname: dateiname,
            anzahlTreffer: treffer.length,
            schritte: schritte,
            endeErreicht: endeErreicht,
            meldung: 'Datei nicht eindeutig gefunden'
          });
          return;
        }

        treffer[0].dispatchEvent(
          new MouseEvent('dblclick', {
            bubbles: true,
            cancelable: true,
            view: window
          })
        );

        senden({
          typ: 'dateiOeffnen',
          erfolg: true,
          dateiname: dateiname,
          schritte: schritte,
          meldung: 'Öffnungsversuch ausgelöst'
        });
      })();
    ''');
    } catch (e) {
      debugPrint('PREDIGTFINDER AUSWAHL FEHLER: $e');
    }
  }

  Future<void> openOneDrive() async {
    await pruefeGitHubKonfiguration();
    if (!mounted) return;
    setState(() {
      isOpened = true;
      isLoading = true;
      status = 'Verbinde mit OneDrive ...';
    });

    try {
      await controller.loadRequest(Uri.parse(aktiveOneDriveUrl));
    } catch (e) {
      setState(() {
        isLoading = false;
        status = 'Verbindungsfehler: $e';
      });
    }
  }

  Future<void> kontaktHilfeOeffnen() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'Info@missiongotteswort.de',
      queryParameters: {
        'subject': 'Ich bitte um Kontaktaufnahme. Details in der Mail',
      },
    );

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('E-Mail konnte nicht geöffnet werden: $e');
    }
  }

  Future<void> missionTelegramOeffnen() async {
    final uri = Uri.parse('https://t.me/missiongotteswort');

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Telegram konnte nicht geöffnet werden: $e');
    }
  }

  void impressumAnzeigen() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Impressum'),
        content: const SingleChildScrollView(
          child: SelectableText(
            'PredigtFinder\n'
            'Anbieter: Frank Wernet\n'
            'Schopenhauerstraße 41c\n'
            '70565 Stuttgart\n'
            'Deutschland\n\n'
            'E-Mail: Info@missiongotteswort.de',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  void datenschutzAnzeigen() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Datenschutzerklärung'),
        content: const SingleChildScrollView(
          child: SelectableText(
            'Verantwortlicher:\n'
            'Frank Wernet\n'
            'Schopenhauerstraße 41c\n'
            '70565 Stuttgart\n'
            'E-Mail: Info@missiongotteswort.de\n\n'
            'PredigtFinder ermöglicht die Suche nach Predigten '
            'und das Öffnen zugehöriger Videos.\n\n'
            'Die App speichert Predigttexte und Konfigurationsdaten '
            'lokal auf dem Gerät.\n\n'
            'Die App ruft Konfigurationsdaten über GitHub Pages '
            'und Predigtdateien über Microsoft OneDrive ab. '
            'Bei diesen Verbindungen können technische Daten '
            'wie die IP-Adresse an die jeweiligen Anbieter '
            'übermittelt werden.\n\n'
            'Über die Kontaktfunktionen können Nutzer ihr '
            'E-Mail-Programm oder Telegram öffnen. '
            'Für die Nutzung dieser Dienste gelten zusätzlich '
            'die Datenschutzinformationen der jeweiligen Anbieter.\n\n'
            'Datenschutzanfragen können an '
            'Info@missiongotteswort.de gerichtet werden.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

bottomNavigationBar: automatischeSynchronisierungAktiv
    ? SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          color: Colors.blue.shade50,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Predigten werden synchronisiert …',
                ),
              ),
            ],
          ),
        ),
      )
    : null,

      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mission Gottes Wort',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text('PredigtFinder', style: TextStyle(fontSize: 12)),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'Administration',
            icon: const Icon(Icons.lock_outline),

            onPressed: adminAnmelden,
          ),
          PopupMenuButton<String>(
            tooltip: 'Kontakt und Informationen',
            icon: const Icon(Icons.more_vert),
            onSelected: (wert) {
              if (wert == 'hilfe') {
                kontaktHilfeOeffnen();
              } else if (wert == 'mission') {
                missionTelegramOeffnen();
              } else if (wert == 'impressum') {
                impressumAnzeigen();
              } else if (wert == 'datenschutz') {
                datenschutzAnzeigen();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'hilfe', child: Text('Ich suche Hilfe')),
              PopupMenuItem(
                value: 'mission',
                child: Text('Interesse an unserer Mission'),
              ),

              PopupMenuItem(value: 'impressum', child: Text('Impressum')),
              PopupMenuItem(
                value: 'datenschutz',
                child: Text('Datenschutzerklärung'),
              ),
            ],
          ),
        ],
      ),

      body: Column(
        children: [
          if (!videoAnsichtAnzeigen)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  suchmenueAnzeigen = !suchmenueAnzeigen;
                });
              },
              icon: Icon(
                suchmenueAnzeigen ? Icons.expand_less : Icons.expand_more,
              ),
              label: const Text('Predigtsuche'),
            ),

          if (!videoAnsichtAnzeigen && suchmenueAnzeigen)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  TextField(
                    controller: suchfeld1,
                    decoration: const InputDecoration(
                      labelText: 'Suchbegriff 1',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),

                  const SizedBox(height: 4),

                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'ODER', label: Text('ODER')),
                      ButtonSegment(value: 'UND', label: Text('UND')),
                    ],
                    selected: {verknuepfung1},
                    onSelectionChanged: (auswahl) {
                      setState(() {
                        verknuepfung1 = auswahl.first;
                      });
                    },
                  ),

                  const SizedBox(height: 4),

                  TextField(
                    controller: suchfeld2,
                    decoration: const InputDecoration(
                      labelText: 'Suchbegriff 2',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),

                  const SizedBox(height: 4),

                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'ODER', label: Text('ODER')),
                      ButtonSegment(value: 'UND', label: Text('UND')),
                    ],
                    selected: {verknuepfung2},
                    onSelectionChanged: (auswahl) {
                      setState(() {
                        verknuepfung2 = auswahl.first;
                      });
                    },
                  ),

                  const SizedBox(height: 4),

                  TextField(
                    controller: suchfeld3,
                    decoration: const InputDecoration(
                      labelText: 'Suchbegriff 3',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),

                  const SizedBox(height: 6),

                  ElevatedButton.icon(
                    onPressed: suchePredigten,
                    icon: const Icon(Icons.search),
                    label: const Text('Predigten suchen'),
                  ),

                  const SizedBox(height: 6),

                  OutlinedButton.icon(
                    onPressed: alleFilterZuruecksetzen,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Alle Filter zurücksetzen'),
                  ),
                ],
              ),
            ),

          if (testmenueFreigeschaltet)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  testfunktionenAnzeigen = !testfunktionenAnzeigen;
                });
              },
              icon: Icon(
                testfunktionenAnzeigen ? Icons.expand_less : Icons.expand_more,
              ),
              label: const Text('Technische Testfunktionen'),
            ),

          if (testfunktionenAnzeigen)
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed:
                            isOpened &&
                                !isLoading &&
                                !hintergrundErfassungAktiv &&
                                predigtDateien.isNotEmpty
                            ? () => erfassePredigten(predigtDateien.length)
                            : null,
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Alle Predigten einlesen'),
                      ),

                      ElevatedButton.icon(
                        onPressed:
                            hintergrundErfassungAktiv && !erfassungAbbrechen
                            ? abbrechenErfassung
                            : null,
                        icon: const Icon(Icons.stop_circle_outlined, size: 16),
                        label: const Text('Erfassung abbrechen'),
                      ),
                      ElevatedButton.icon(
                        onPressed:
                            isOpened && !isLoading && !hintergrundErfassungAktiv
                            ? testDreiPredigten
                            : null,
                        icon: const Icon(Icons.science, size: 16),
                        label: const Text('10 Predigten testen'),
                      ),
                      ElevatedButton.icon(
                        onPressed: isLoading ? null : openOneDrive,
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('OneDrive 1'),
                      ),
                      ElevatedButton.icon(
                        onPressed: isOpened && !isLoading ? testFileList : null,
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('Dateiliste'),
                      ),
                      ElevatedButton.icon(
                        onPressed: isOpened && !isLoading
                            ? testTextPreview
                            : null,
                        icon: const Icon(Icons.article_outlined, size: 16),
                        label: const Text('Text testen'),
                      ),
                      ElevatedButton.icon(
                        onPressed: isOpened && !isLoading
                            ? testClosePreview
                            : null,
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Schließen'),
                      ),
                      ElevatedButton.icon(
                        onPressed: isOpened && !isLoading
                            ? testFileElement
                            : null,
                        icon: const Icon(Icons.find_in_page, size: 16),
                        label: const Text('Dateielement'),
                      ),
                      if (predigtVorschauAnzeigen || videoAnsichtAnzeigen)
                        ElevatedButton.icon(
                          onPressed: closeVideoPreview,
                          icon: const Icon(Icons.arrow_back, size: 16),
                          label: const Text('Zurück'),
                        ),
                    ],
                  ),
                  Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  if (dateilisteWirdErfasst) ...[
                    const SizedBox(height: 6),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 4),
                    Text(
                      '$dateilisteGefunden TXT-Dateien gefunden ...',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  if (isLoading) const LinearProgressIndicator(),
                ],
              ),
            ),

          if (videoAnsichtAnzeigen)
            TextButton.icon(
              onPressed: closeVideoPreview,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Zurück zur Predigtliste'),
            ),

          if (!videoAnsichtAnzeigen)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    sucheAktiv
                        ? '${suchErgebnisse.length} Treffer'
                        : '${predigtTexte.length} Predigten gespeichert',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${predigtTexte.length} Texte',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),

          if (!videoAnsichtAnzeigen && !predigtVorschauAnzeigen)
 
if (!videoAnsichtAnzeigen && !predigtVorschauAnzeigen)
  Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: 8,
      vertical: 6,
    ),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
              style: OutlinedButton.styleFrom(
    backgroundColor: !sortierungNeuesteZuerst &&
            !sortierungNachTreffern
        ? Colors.blue.shade100
        : null,
  ),
            onPressed: () {
              setState(() {
                sortierungNeuesteZuerst = false;
                sortierungNachTreffern = false;
              });
            },
            child: const Text('A–Z'),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
  backgroundColor: sortierungNeuesteZuerst &&
          !(sucheAktiv && sortierungNachTreffern)
      ? Colors.blue.shade100
      : null,
),
            onPressed: () {
              setState(() {
                sortierungNeuesteZuerst = true;
                sortierungNachTreffern = false;
              });
            },
            child: const Text('Neueste'),
          ),
        ),
        if (sucheAktiv) ...[
          const SizedBox(width: 5),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
  backgroundColor: sucheAktiv && sortierungNachTreffern
      ? Colors.blue.shade100
      : null,
),
              onPressed: () {
                setState(() {
                  sortierungNachTreffern = true;
                });
              },
              child: const Text('Treffer ↓'),
            ),
          ),
        ],
      ],
    ),
  ),


          Expanded(
            child: isOpened || predigtDateien.isNotEmpty
                ? IndexedStack(
                    index: videoAnsichtAnzeigen
                        ? 2
                        : (predigtDateien.isNotEmpty || sucheAktiv) &&
                              !predigtVorschauAnzeigen
                        ? 1
                        : 0,
                    children: [
                      isOpened
                          ? WebViewWidget(controller: controller)
                          : const SizedBox.shrink(),


                        Builder(
                          builder: (context) {
                            final sortierteDateien = sortiertePredigtDateien();

                            return ListView.builder(
                              itemCount: sortierteDateien.length,
                              itemBuilder: (context, index) {
                                final dateiname = sortierteDateien[index];
                                final istMarkiert = markierteDatei == dateiname;


                          return ListTile(
                            leading: Icon(
                              Icons.play_circle_outline,
                              color: Colors.blue,
                            ),
                            title: Text(
                              (() {
                                final text = predigtTexte[dateiname] ?? '';
                                final ersteZeile = text
                                    .split(RegExp(r'\r?\n'))
                                    .first
                                    .trim();

                                final video =
                                    videoDateinamen[dateiname] ??
                                    (ersteZeile.toLowerCase().endsWith('.mp4')
                                        ? ersteZeile
                                        : '');

                                if (video.toLowerCase().endsWith('.mp4')) {
                                  return video.replaceFirst(
                                    RegExp(r'\.mp4$', caseSensitive: false),
                                    '',
                                  );
                                }

                                return dateiname.replaceFirst(
                                  RegExp(r'[.]txt$', caseSensitive: false),
                                  '',
                                );
                              })(),
                            ),
                            subtitle: Builder(
                              builder: (context) {
                                final video = videoDateinamen[dateiname];
                                final sekunden = videoDauern[video];
                                final dauer = sekunden == null
                                    ? ''
                                    : formatiereVideoDauer(sekunden);
                            
                                final treffer = sucheAktiv
                                    ? '${suchTrefferzahlen[dateiname] ?? 0} Treffer'
                                    : '';
                            

final datum = predigtDatum[dateiname];

final datumText = datum == null
    ? ''
    : '${datum.day.toString().padLeft(2, '0')}.'
      '${datum.month.toString().padLeft(2, '0')}.'
      '${datum.year}';

final untertitel = [
  if (datumText.isNotEmpty) datumText,
  if (treffer.isNotEmpty) treffer,
  if (dauer.isNotEmpty) dauer,
].join(' · ');
                         
                                if (untertitel.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                            
                                return Text(
                                  untertitel,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.blueGrey,
                                  ),
                                );
                              },
                            ),
                            selected: istMarkiert,
                            selectedTileColor: Colors.blue.shade100,
                            onTap: () {
                              final jetzt = DateTime.now();

                              final istDoppelklick =
                                  letzteAngeklickteDatei == dateiname &&
                                  letzterKlickZeitpunkt != null &&
                                  jetzt
                                          .difference(letzterKlickZeitpunkt!)
                                          .inMilliseconds <
                                      400;

                              setState(() {
                                markierteDatei = dateiname;

                                if (istDoppelklick) {
                                  status = 'Doppelklick erkannt: $dateiname';

                                  letzterKlickZeitpunkt = null;
                                  letzteAngeklickteDatei = null;
                                } else {
                                  status = 'Markiert: $dateiname';

                                  letzterKlickZeitpunkt = jetzt;
                                  letzteAngeklickteDatei = dateiname;
                                }
                              });
                              if (istDoppelklick) {
                                final text = predigtTexte[dateiname] ?? '';
                                final ersteZeile = text
                                    .split(RegExp(r'\r?\n'))
                                    .first
                                    .replaceFirst('\uFEFF', '')
                                    .trim();
                                final video = videoDateinamen[dateiname] ??
                                    (ersteZeile.toLowerCase().endsWith('.mp4')
                                        ? ersteZeile
                                        : '');

                                if (video.toLowerCase().endsWith('.mp4')) {
                                  unawaited(oeffneVideoDirekt(video));
                                } else {
                                  setState(() {
                                    status = 'Kein Video zugeordnet';
                                  });
                                }
                              }
                            },
            );
          },
        );
      },
    ),

                      Column(
                        children: [
                          if (aktuellerVideoTitel.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                aktuellerVideoTitel,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (aktuellerVideoDateiname.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () => videoImBrowserOeffnen(
                                  aktuellerVideoDateiname,
                                ),
                                icon: const Icon(Icons.download),
                                label: const Text(
                                  'Video auf YouTube ansehen',
                                ),
                              ),
                            ),
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: WebViewWidget(
                                    controller: videoController,
                                  ),
                                ),
                                if (videoWirdGeladen)
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      child: const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(),
                                            SizedBox(height: 16),
                                            Text('Video wird geladen ...'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : const Center(
                    child: Text('OneDrive-Verbindung noch nicht gestartet.'),
                  ),
          ),
        ],
      ),
    );
  }
}
