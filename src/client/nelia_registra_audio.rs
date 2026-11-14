//! NELIA: la voce nella registrazione (REC), come una registrazione di Zoom.
//!
//! Durante una registrazione dello schermo si salva anche l'audio, in un file
//! a parte nella stessa cartella dei video:
//!   «outgoing_<id>_<AAAAMMGGhhmmssmmm>_audio.wav»
//! con dentro, mescolati e a tempo:
//!   - quello che arriva dal computer collegato (la voce del cliente nella
//!     «Chiamata vocale», e l'audio del suo computer);
//!   - il nostro microfono, quando la «Chiamata vocale» e' accesa.
//! Sul Mac un'automazione unisce poi video e audio in un .mp4.
//!
//! Regole:
//! - niente qui puo' rompere la sessione: ogni errore si scrive nel registro e
//!   la registrazione dell'audio si ferma, il resto va avanti come prima;
//! - se in tutta la registrazione non arriva mai audio, il file si cancella
//!   (la registrazione resta solo video, come prima);
//! - l'intestazione del WAV si aggiorna a ogni scrittura: anche se il
//!   programma si chiude di colpo il file resta leggibile.
//! Per tornare indietro: ANNULLA REGISTRA AUDIO.

use hbb_common::{chrono, log};
use magnum_opus::{Channels, Decoder};
use std::{
    collections::VecDeque,
    fs::File,
    io::{Seek, SeekFrom, Write},
    path::PathBuf,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

/// 24 kHz mono a 16 bit: per la voce basta e avanza (~48 KB al secondo).
const RATE: u64 = 24_000;
/// L'audio si scrive con 300 ms di ritardo, per aspettare i pezzi in arrivo.
const RITARDO: u64 = RATE * 3 / 10;
/// Un flusso fermo da piu' di mezzo secondo riparte dal momento in cui arriva.
const SALTO: u64 = RATE / 2;
/// Un pezzo Opus decodificato e' al massimo 120 ms.
const MAX_PEZZO: usize = (RATE as usize) * 120 / 1000;

struct Flusso {
    decoder: Decoder,
    /// Dove va il prossimo campione (in campioni dall'inizio).
    prossimo: Option<u64>,
}

impl Flusso {
    fn new() -> Option<Self> {
        match Decoder::new(RATE as u32, Channels::Mono) {
            Ok(decoder) => Some(Self { decoder, prossimo: None }),
            Err(e) => {
                log::error!("[nelia audio] decoder non creato: {e:?}");
                None
            }
        }
    }
}

struct Registrazione {
    token: Arc<()>,
    inizio: Instant,
    file: File,
    percorso: PathBuf,
    /// Campioni gia' scritti nel file.
    scritti: u64,
    /// Il mix ancora da scrivere: mix[0] e' il campione numero «scritti».
    mix: VecDeque<i32>,
    remota: Flusso,
    mia: Flusso,
    /// E' mai arrivato dell'audio?
    sentito: bool,
}

lazy_static::lazy_static! {
    static ref ATTIVA: Mutex<Option<Registrazione>> = Mutex::new(None);
}

/// Finche' esiste, l'audio si registra; quando sparisce (REC fermato,
/// sessione chiusa) il file si chiude.
pub struct Guardia {
    token: Option<Arc<()>>,
}

impl Drop for Guardia {
    fn drop(&mut self) {
        if let Some(t) = self.token.take() {
            ferma_se(&t);
        }
    }
}

fn nome_pulito(s: &str) -> String {
    s.chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
        .collect()
}

fn intestazione_wav(file: &mut File, campioni: u64) -> std::io::Result<()> {
    let dati = (campioni * 2).min(u32::MAX as u64 - 36) as u32;
    let mut h = Vec::with_capacity(44);
    h.extend_from_slice(b"RIFF");
    h.extend_from_slice(&(36 + dati).to_le_bytes());
    h.extend_from_slice(b"WAVEfmt ");
    h.extend_from_slice(&16u32.to_le_bytes()); // fmt lungo 16
    h.extend_from_slice(&1u16.to_le_bytes()); // PCM
    h.extend_from_slice(&1u16.to_le_bytes()); // mono
    h.extend_from_slice(&(RATE as u32).to_le_bytes());
    h.extend_from_slice(&((RATE * 2) as u32).to_le_bytes()); // byte al secondo
    h.extend_from_slice(&2u16.to_le_bytes()); // byte per campione
    h.extend_from_slice(&16u16.to_le_bytes()); // bit
    h.extend_from_slice(b"data");
    h.extend_from_slice(&dati.to_le_bytes());
    let pos = file.stream_position()?;
    file.seek(SeekFrom::Start(0))?;
    file.write_all(&h)?;
    file.seek(SeekFrom::Start(pos.max(44)))?;
    Ok(())
}

/// Comincia a registrare l'audio. Se una registrazione e' gia' accesa (altro
/// schermo della stessa sessione), resta quella: la Guardia non la ferma.
pub fn inizia(id: &str, cartella: &str) -> Guardia {
    let mut attiva = match ATTIVA.lock() {
        Ok(a) => a,
        Err(_) => return Guardia { token: None },
    };
    if attiva.is_some() {
        return Guardia { token: None };
    }
    let (Some(remota), Some(mia)) = (Flusso::new(), Flusso::new()) else {
        return Guardia { token: None };
    };
    let cartella = PathBuf::from(cartella);
    if let Err(e) = std::fs::create_dir_all(&cartella) {
        log::error!("[nelia audio] cartella non creata: {e}");
        return Guardia { token: None };
    }
    let percorso = cartella.join(format!(
        "outgoing_{}_{}_audio.wav",
        nome_pulito(id),
        chrono::Local::now().format("%Y%m%d%H%M%S%3f")
    ));
    let mut file = match File::create(&percorso) {
        Ok(f) => f,
        Err(e) => {
            log::error!("[nelia audio] file non creato: {e}");
            return Guardia { token: None };
        }
    };
    if let Err(e) = intestazione_wav(&mut file, 0) {
        log::error!("[nelia audio] intestazione non scritta: {e}");
        let _ = std::fs::remove_file(&percorso);
        return Guardia { token: None };
    }
    let token = Arc::new(());
    *attiva = Some(Registrazione {
        token: token.clone(),
        inizio: Instant::now(),
        file,
        percorso: percorso.clone(),
        scritti: 0,
        mix: VecDeque::new(),
        remota,
        mia,
        sentito: false,
    });
    drop(attiva);
    log::info!("[nelia audio] registrazione iniziata: {}", percorso.display());

    // Ogni 200 ms scrive nel file quello che e' pronto.
    let t = token.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_millis(200));
        let mut attiva = match ATTIVA.lock() {
            Ok(a) => a,
            Err(_) => break,
        };
        match attiva.as_mut() {
            Some(r) if Arc::ptr_eq(&r.token, &t) => {
                if let Err(e) = scrivi_pronti(r, false) {
                    log::error!("[nelia audio] scrittura non riuscita, mi fermo: {e}");
                    let r = attiva.take();
                    drop(attiva);
                    if let Some(r) = r {
                        chiudi(r);
                    }
                    break;
                }
            }
            _ => break,
        }
    });

    Guardia { token: Some(token) }
}

/// Scrive i campioni fino a «adesso meno il ritardo» (o tutti, alla fine).
fn scrivi_pronti(r: &mut Registrazione, tutto: bool) -> std::io::Result<()> {
    let fino = if tutto {
        r.scritti + r.mix.len() as u64
    } else {
        let adesso = r.inizio.elapsed().as_micros() as u64 * RATE / 1_000_000;
        adesso.saturating_sub(RITARDO)
    };
    if fino <= r.scritti {
        return Ok(());
    }
    let n = (fino - r.scritti) as usize;
    let mut byte = Vec::with_capacity(n * 2);
    for i in 0..n {
        let v = r.mix.get(i).copied().unwrap_or(0).clamp(i16::MIN as i32, i16::MAX as i32) as i16;
        byte.extend_from_slice(&v.to_le_bytes());
    }
    let tolti = n.min(r.mix.len());
    r.mix.drain(..tolti);
    r.file.write_all(&byte)?;
    r.scritti = fino;
    intestazione_wav(&mut r.file, r.scritti)?;
    Ok(())
}

fn aggiungi(r: &mut Registrazione, da_remoto: bool, opus: &[u8]) {
    let adesso = r.inizio.elapsed().as_micros() as u64 * RATE / 1_000_000;
    let mut pcm = [0i16; MAX_PEZZO];
    let flusso = if da_remoto { &mut r.remota } else { &mut r.mia };
    let n = match flusso.decoder.decode(opus, &mut pcm, false) {
        Ok(n) => n.min(MAX_PEZZO),
        Err(e) => {
            log::trace!("[nelia audio] pezzo non decodificato: {e:?}");
            return;
        }
    };
    if n == 0 {
        return;
    }
    // Il pezzo e' appena arrivato: finisce «adesso». Se il flusso era fermo
    // (o e' andato troppo avanti), riparte da qui.
    let inizio_pezzo = adesso.saturating_sub(n as u64);
    let pos = match flusso.prossimo {
        Some(p) if p + SALTO >= inizio_pezzo && p <= adesso + RATE => p,
        _ => inizio_pezzo,
    };
    flusso.prossimo = Some(pos + n as u64);
    r.sentito = true;
    for (i, &v) in pcm[..n].iter().enumerate() {
        let assoluto = pos + i as u64;
        if assoluto < r.scritti {
            continue; // arrivato tardi: gia' scritto
        }
        let k = (assoluto - r.scritti) as usize;
        if k >= r.mix.len() {
            r.mix.resize(k + 1, 0);
        }
        r.mix[k] += v as i32;
    }
}

fn tocca(da_remoto: bool, opus: &[u8]) {
    if let Ok(mut attiva) = ATTIVA.try_lock() {
        if let Some(r) = attiva.as_mut() {
            aggiungi(r, da_remoto, opus);
        }
    } else if let Ok(mut attiva) = ATTIVA.lock() {
        if let Some(r) = attiva.as_mut() {
            aggiungi(r, da_remoto, opus);
        }
    }
}

/// Un pezzo di audio arrivato dal computer collegato (Opus).
pub fn audio_remoto(opus: &[u8]) {
    tocca(true, opus);
}

/// Un pezzo del nostro microfono nella «Chiamata vocale» (Opus).
pub fn audio_mio(opus: &[u8]) {
    tocca(false, opus);
}

fn chiudi(mut r: Registrazione) {
    if let Err(e) = scrivi_pronti(&mut r, true) {
        log::error!("[nelia audio] ultima scrittura non riuscita: {e}");
    }
    let _ = r.file.flush();
    let percorso = r.percorso.clone();
    let sentito = r.sentito;
    drop(r);
    if sentito {
        log::info!("[nelia audio] registrazione chiusa: {}", percorso.display());
    } else {
        // Nessun audio in tutta la registrazione: il file non serve.
        let _ = std::fs::remove_file(&percorso);
        log::info!("[nelia audio] nessun audio, file tolto");
    }
}

fn ferma_se(token: &Arc<()>) {
    let r = match ATTIVA.lock() {
        Ok(mut a) => match a.as_ref() {
            Some(r) if Arc::ptr_eq(&r.token, token) => a.take(),
            _ => None,
        },
        Err(_) => None,
    };
    if let Some(r) = r {
        chiudi(r);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nome_senza_caratteri_strani() {
        assert_eq!(nome_pulito("123 456/7"), "123_456_7");
    }

    #[test]
    fn wav_valido_e_silenzio_tolto() {
        let dir = std::env::temp_dir().join(format!("nelia-audio-{}", std::process::id()));
        // Senza audio: il file sparisce.
        {
            let _g = inizia("111", dir.to_str().unwrap());
            std::thread::sleep(Duration::from_millis(300));
        }
        let rimasti: Vec<_> = std::fs::read_dir(&dir).map(|d| d.flatten().collect()).unwrap_or_default();
        assert!(rimasti.is_empty(), "senza audio non deve restare niente");

        // Con audio (un pezzo Opus vero): il file resta ed e' un WAV leggibile.
        let mut enc = magnum_opus::Encoder::new(RATE as u32, Channels::Mono, magnum_opus::Application::Voip).unwrap();
        let tono: Vec<i16> = (0..480).map(|i| ((i as f32 * 0.2).sin() * 8000.0) as i16).collect();
        let mut out = [0u8; 4000];
        let n = enc.encode(&tono, &mut out).unwrap();
        {
            let _g = inizia("222", dir.to_str().unwrap());
            for _ in 0..10 {
                audio_remoto(&out[..n]);
                audio_mio(&out[..n]);
                std::thread::sleep(Duration::from_millis(20));
            }
            std::thread::sleep(Duration::from_millis(600));
        }
        let file = std::fs::read_dir(&dir).unwrap().flatten().next().expect("file audio").path();
        let byte = std::fs::read(&file).unwrap();
        assert_eq!(&byte[0..4], b"RIFF");
        assert_eq!(&byte[8..16], b"WAVEfmt ");
        let dati = u32::from_le_bytes([byte[40], byte[41], byte[42], byte[43]]) as usize;
        assert_eq!(dati, byte.len() - 44);
        assert!(byte[44..].iter().any(|&b| b != 0), "c'e' audio");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
