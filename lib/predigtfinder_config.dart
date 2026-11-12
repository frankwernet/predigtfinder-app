import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;

class PredigtFinderConfig {
  final String predigttexteUrl;
  final String predigtvideosUrl;
  final int version;

  const PredigtFinderConfig({
    required this.predigttexteUrl,
    required this.predigtvideosUrl,
    required this.version,
  });

  static const String configUrl =
      'https://frankwernet.github.io/predigtfinder/config.json';

  static Future<PredigtFinderConfig> laden() async {
    final uri = Uri.parse(configUrl).replace(
      queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()},
    );

    final antwort = await http.get(uri).timeout(const Duration(seconds: 15));

    if (antwort.statusCode != 200) {
      throw Exception('Konfiguration nicht erreichbar: ${antwort.statusCode}');
    }

    final daten = jsonDecode(antwort.body);

    if (daten is! Map<String, dynamic>) {
      throw const FormatException('Ungültige Konfiguration');
    }

    final texte = daten['predigttexte_url'];
    final videos = daten['predigtvideos_url'];
    final version = daten['version'];

    if (texte is! String || videos is! String || version is! int) {
      throw const FormatException('Konfigurationsfelder fehlen');
    }

    final texteUri = Uri.tryParse(texte);
    final videosUri = Uri.tryParse(videos);

    if (texteUri == null ||
        videosUri == null ||
        texteUri.scheme != 'https' ||
        videosUri.scheme != 'https' ||
        texteUri.host != '1drv.ms' ||
        videosUri.host != '1drv.ms') {
      throw const FormatException('Ungültige OneDrive-Adressen');
    }

    return PredigtFinderConfig(
      predigttexteUrl: texte,
      predigtvideosUrl: videos,
      version: version,
    );
  }

  static Future<File> _lokaleDatei() async {
    final verzeichnis = await getApplicationDocumentsDirectory();
    return File('${verzeichnis.path}/predigtfinder_config_cache.json');
  }

  Future<void> lokalSpeichern() async {
    final datei = await _lokaleDatei();
    final tempDatei = File('${datei.path}.tmp');

    final daten = {
      'version': version,
      'predigttexte_url': predigttexteUrl,
      'predigtvideos_url': predigtvideosUrl,
    };

    await tempDatei.writeAsString(jsonEncode(daten), flush: true);

    if (await datei.exists()) {
      await datei.delete();
    }

    await tempDatei.rename(datei.path);
  }

  static Future<PredigtFinderConfig?> lokalLaden() async {
    final datei = await _lokaleDatei();

    if (!await datei.exists()) {
      return null;
    }

    try {
      final daten = jsonDecode(await datei.readAsString());

      if (daten is! Map<String, dynamic>) {
        return null;
      }

      final texte = daten['predigttexte_url'];
      final videos = daten['predigtvideos_url'];
      final version = daten['version'];

      if (texte is! String || videos is! String || version is! int) {
        return null;
      }

      final texteUri = Uri.tryParse(texte);
      final videosUri = Uri.tryParse(videos);

      if (texteUri == null ||
          videosUri == null ||
          texteUri.scheme != 'https' ||
          videosUri.scheme != 'https' ||
          texteUri.host != '1drv.ms' ||
          videosUri.host != '1drv.ms') {
        return null;
      }

      return PredigtFinderConfig(
        predigttexteUrl: texte,
        predigtvideosUrl: videos,
        version: version,
      );
    } catch (_) {
      return null;
    }
  }
}
