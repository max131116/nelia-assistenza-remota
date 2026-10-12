#!/usr/bin/env python3
# Nelia Assistenza Remota: nome, server e chiave scritti dentro il programma.
# libs/hbb_common e' un sottomodulo di RustDesk: lo si modifica qui, durante la
# costruzione, invece di copiarlo. Se una riga non si trova, la costruzione si ferma.
import pathlib
import sys

NOME = "Nelia-Assistenza-Remota"  # interno: solo lettere e trattini (servizi, cartelle, comandi)
SERVER = "2.31.51.60"
CHIAVE = "N2xgmHwBFzbk6rh2UrSgdKLoMlgKMFRYg518kVaUWUM="

file = pathlib.Path("libs/hbb_common/src/config.rs")
testo = file.read_text(encoding="utf-8")
cambi = [
    ('RwLock::new("RustDesk".to_owned());', f'RwLock::new("{NOME}".to_owned());'),
    ('pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];', f'pub const RENDEZVOUS_SERVERS: &[&str] = &["{SERVER}"];'),
    ('pub const RS_PUB_KEY: &str = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=";', f'pub const RS_PUB_KEY: &str = "{CHIAVE}";'),
]
for vecchio, nuovo in cambi:
    if testo.count(vecchio) != 1:
        sys.exit(f"Riga non trovata (o piu' volte) in {file}: {vecchio}")
    testo = testo.replace(vecchio, nuovo)
file.write_text(testo, encoding="utf-8")
print(f"{file}: nome {NOME}, server {SERVER}, chiave del nostro server")
