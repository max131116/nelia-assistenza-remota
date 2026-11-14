// NELIA: manda la registrazione (REC) al cliente con il Trasferimento file.
//
// 1. Fermato il REC, chiede se mandarla al cliente (solo sul Mac dove c'e'
//    l'automazione che fa gli .mp4: la riconosce dalla cartella .pronti).
// 2. Aspetta che l'automazione scriva .pronti/<id> con il percorso dell'.mp4,
//    lascia .pronti/<id>.invia e apre il Trasferimento file.
// 3. La finestra del Trasferimento file trova .pronti/<id>.invia, lo toglie
//    e manda l'.mp4 sulla Scrivania del cliente, in «Registrazioni Nelia».
// Per tornare indietro: ANNULLA MANDA REGISTRAZIONE.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../common.dart';
import 'file_model.dart';
import 'model.dart';
import 'platform_model.dart';

const _kCartellaCliente = 'Registrazioni Nelia';
const _kAttesaMassima = Duration(minutes: 30);

Directory _pronti() =>
    Directory('${bind.mainVideoSaveDirectory(root: false)}/.pronti');

/// Da chiamare appena fermato il REC (finestra del controllo remoto).
Future<void> neliaDopoRec(FFI? ffi) async {
  if (ffi == null || !isDesktop || ffi.id.isEmpty) return;
  try {
    final pronti = _pronti();
    if (!pronti.existsSync()) return;
    final id = ffi.id;
    final sessionId = ffi.sessionId;
    final fermato = DateTime.now();

    final si = await ffi.dialogManager.show<bool>((setState, close, context) {
      return CustomAlertDialog(
        title: const Text('Registrazione'),
        content: const Text('Vuoi mandare la registrazione al cliente?'),
        actions: [
          dialogButton('No', onPressed: () => close(false), isOutline: true),
          dialogButton('Sì', onPressed: () => close(true)),
        ],
        onCancel: () => close(false),
        onSubmit: () => close(true),
      );
    });
    if (si != true) return;

    var annullato = false;
    const tag = 'nelia-prepara-registrazione';
    ffi.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: const Text('Preparo il video…'),
        content: const Text(
          'Il video con la voce sarà pronto fra qualche minuto, poi parte da solo verso il cliente.\n'
          'Non chiudere la connessione.',
        ),
        actions: [
          dialogButton(
            'Annulla',
            onPressed: () {
              annullato = true;
              close();
            },
            isOutline: true,
          ),
        ],
        onCancel: () {
          annullato = true;
          close();
        },
      );
    }, tag: tag);

    final segnale = File('${pronti.path}/$id');
    final limite = fermato.add(_kAttesaMassima);
    String? video;
    while (!annullato && DateTime.now().isBefore(limite)) {
      await Future.delayed(const Duration(seconds: 3));
      try {
        if (segnale.existsSync() &&
            segnale.lastModifiedSync().isAfter(fermato)) {
          final percorso = segnale.readAsStringSync().trim();
          if (percorso.isNotEmpty && File(percorso).existsSync()) {
            video = percorso;
            break;
          }
        }
      } catch (_) {}
    }
    ffi.dialogManager.dismissByTag(tag);
    if (annullato) return;
    if (video == null) {
      showToast(
        'Il video non è pronto: lo trovi più tardi nella cartella delle registrazioni.',
      );
      return;
    }

    File('${pronti.path}/$id.invia').writeAsStringSync(video);
    final ctx = globalKey.currentContext;
    if (ctx == null) {
      showToast('Apri «Trasferimento file»: il video parte da solo.');
      return;
    }
    await connect(
      ctx,
      id,
      isFileTransfer: true,
      connToken: bind.sessionGetConnToken(sessionId: sessionId),
    );
  } catch (e) {
    debugPrint('[nelia] invio registrazione: $e');
  }
}

/// Da chiamare all'apertura della finestra del Trasferimento file.
Future<void> neliaInviaSePronta(FFI ffi, String id) async {
  if (!isDesktop) return;
  try {
    final richiesta = File('${_pronti().path}/$id.invia');
    if (!richiesta.existsSync()) return;
    final vecchia =
        DateTime.now().difference(richiesta.lastModifiedSync()) >
        const Duration(minutes: 10);
    final percorso = richiesta.readAsStringSync().trim();
    richiesta.deleteSync();
    final video = File(percorso);
    if (vecchia || percorso.isEmpty || !video.existsSync()) return;

    final model = ffi.fileModel;
    final remoto = model.remoteController;
    final limite = DateTime.now().add(const Duration(minutes: 1));
    while (remoto.homePath.isEmpty && DateTime.now().isBefore(limite)) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    final casa = remoto.homePath;
    if (casa.isEmpty) return;
    // La finestra apre da sola le cartelle dell'ultima volta: si lascia finire.
    await Future.delayed(const Duration(seconds: 2));
    final windows = remoto.options.value.isWindows;

    // La Scrivania vera: con OneDrive su Windows sta dentro OneDrive.
    // Si aprono solo cartelle viste nell'elenco (una che non c'e' fa
    // aspettare la finestra fino a 30 secondi).
    Future<List<String>> sottocartelle(String dir) async {
      if (!await remoto.openDirectory(dir)) return [];
      return remoto.directory.value.entries
          .where((e) => e.isDirectory)
          .map((e) => e.name)
          .toList();
    }

    var scrivania = casa;
    final inCasa = await sottocartelle(casa);
    for (final od in inCasa.where(
      (n) => n == 'OneDrive' || n.startsWith('OneDrive - '),
    )) {
      final cartellaOd = PathUtil.join(casa, od, windows);
      if ((await sottocartelle(cartellaOd)).contains('Desktop')) {
        scrivania = PathUtil.join(cartellaOd, 'Desktop', windows);
        break;
      }
    }
    if (scrivania == casa && inCasa.contains('Desktop')) {
      scrivania = PathUtil.join(casa, 'Desktop', windows);
    }
    final destinazione = PathUtil.join(scrivania, _kCartellaCliente, windows);
    await remoto.createDir(destinazione);
    var aperta = false;
    for (var i = 0; i < 5 && !aperta; i++) {
      await Future.delayed(const Duration(milliseconds: 600));
      aperta = await remoto.openDirectory(destinazione);
    }

    final locale = model.localController;
    await locale.openDirectory(video.parent.path);
    // La destinazione si da' per percorso, non per la cartella aperta adesso.
    final arrivo = DirectoryData(
      FileDirectory()..path = aperta ? destinazione : scrivania,
      remoto.options.value,
    );
    final voce = Entry()
      ..name = video.path.split(Platform.pathSeparator).last
      ..path = video.path
      ..size = video.lengthSync()
      ..entryType = 4;
    final scelti = SelectedItems(isLocal: true)..add(voce);
    await locale.sendFiles(scelti, arrivo);
  } catch (e) {
    debugPrint('[nelia] invio registrazione: $e');
  }
}
