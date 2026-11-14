// NELIA: due tasti piccoli sopra lo schermo del computer collegato, solo
// dalla parte di chi si collega:
// - REC in alto a destra (come il REC della barra; un po' sotto il bordo per
//   non coprire la X delle finestre del cliente);
// - in basso a sinistra, solo durante la Chiamata vocale, il nostro
//   microfono: spento, la nostra voce non parte e non si registra.
// Per tornare indietro: ANNULLA TASTI REC E MICROFONO.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../consts.dart';
import '../../models/chat_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';

class NeliaTastiChiamata extends StatelessWidget {
  final FFI ffi;
  const NeliaTastiChiamata({Key? key, required this.ffi}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Obx(() {
        if (ffi.inputModel.relativeMouseMode.value ||
            ffi.ffiModel.pi.isSet.isFalse) {
          return const Offstage();
        }
        final inChiamata =
            ffi.chatModel.voiceCallStatus.value == VoiceCallStatus.connected;
        return Stack(
          children: [
            Positioned(top: 44, right: 12, child: _TastoRec(ffi: ffi)),
            if (inChiamata)
              Positioned(bottom: 16, left: 16, child: _TastoMicrofono()),
          ],
        );
      }),
    );
  }
}

class _TastoRec extends StatefulWidget {
  final FFI ffi;
  const _TastoRec({required this.ffi});

  @override
  State<_TastoRec> createState() => _TastoRecState();
}

class _TastoRecState extends State<_TastoRec>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lampeggio = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void dispose() {
    _lampeggio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.ffi.recordingModel;
    return AnimatedBuilder(
      animation: Listenable.merge([rec, widget.ffi.ffiModel]),
      builder: (context, _) {
        final nascosto =
            bind.mainGetLocalOption(key: kOptionHideRecordingButton) == 'Y';
        final permesso =
            rec.start || widget.ffi.ffiModel.permissions['recording'] != false;
        if (nascosto || !permesso) {
          if (_lampeggio.isAnimating) _lampeggio.stop();
          return const SizedBox.shrink();
        }
        if (rec.start && !_lampeggio.isAnimating) {
          _lampeggio.repeat(reverse: true);
        } else if (!rec.start && _lampeggio.isAnimating) {
          _lampeggio.stop();
          _lampeggio.value = 0;
        }
        return Tooltip(
          message: rec.start ? 'Ferma la registrazione' : 'Registra',
          child: Material(
            color: rec.start
                ? const Color(0xFFD32F2F)
                : Colors.black.withOpacity(0.55),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => rec.toggle(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: rec.start
                          ? Tween(begin: 1.0, end: 0.25).animate(_lampeggio)
                          : const AlwaysStoppedAnimation(1.0),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: rec.start
                              ? Colors.white
                              : const Color(0xFFFF5252),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'REC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TastoMicrofono extends StatefulWidget {
  @override
  State<_TastoMicrofono> createState() => _TastoMicrofonoState();
}

class _TastoMicrofonoState extends State<_TastoMicrofono> {
  @override
  Widget build(BuildContext context) {
    final spento = bind.mainNeliaMicrofonoSpento();
    return Tooltip(
      message: spento ? 'Riaccendi il microfono' : 'Spegni il microfono',
      child: Material(
        color: spento ? const Color(0xFFD32F2F) : Colors.black.withOpacity(0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () async {
            await bind.mainNeliaMicrofono(spento: !spento);
            if (mounted) setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(
              spento ? Icons.mic_off : Icons.mic,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
