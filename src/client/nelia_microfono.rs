//! NELIA: il tasto del microfono nella Chiamata vocale (lato di chi si
//! collega). Spento: la nostra voce non parte verso il computer collegato e
//! non entra nella registrazione. Ogni Chiamata vocale nuova parte accesa.
//! Per tornare indietro: ANNULLA TASTI REC E MICROFONO.

use std::sync::atomic::{AtomicBool, Ordering};

static SPENTO: AtomicBool = AtomicBool::new(false);

pub fn imposta(spento: bool) {
    SPENTO.store(spento, Ordering::Relaxed);
}

pub fn spento() -> bool {
    SPENTO.load(Ordering::Relaxed)
}
