#!/usr/bin/env python3
# Nelia Assistenza Remota: nome, server e chiave scritti dentro il programma.
# libs/hbb_common e' un sottomodulo di RustDesk: lo si modifica qui, durante la
# costruzione, invece di copiarlo. Se una riga non si trova, la costruzione si ferma.
import base64
import hashlib
import os
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

# Password fissa: quella che si vede nel programma resta la stessa a ogni avvio
# (salvata nelle impostazioni). Cambia solo col tasto «Aggiorna password» o dopo
# troppi tentativi sbagliati. Lunga 10 caratteri se il cliente non sceglie altro.
file = pathlib.Path("libs/hbb_common/src/password_security.rs")
testo = file.read_text(encoding="utf-8")
cambi = [
    (
        "Arc::new(RwLock::new(get_auto_password()));",
        "Arc::new(RwLock::new(password_salvata()));",
    ),
    (
        "// Should only be called in server\npub fn update_temporary_password() {\n    *TEMPORARY_PASSWORD.write().unwrap() = get_auto_password();\n}",
        "// Nelia: password fissa per questo computer, salvata nelle impostazioni.\n"
        "const NELIA_PASSWORD_FISSA: &str = \"nelia-password-fissa\";\n\n"
        "fn password_salvata() -> String {\n"
        "    let salvata = Config::get_option(NELIA_PASSWORD_FISSA);\n"
        "    if !salvata.is_empty() {\n"
        "        return salvata;\n"
        "    }\n"
        "    nuova_password_salvata()\n"
        "}\n\n"
        "fn nuova_password_salvata() -> String {\n"
        "    let nuova = get_auto_password();\n"
        "    Config::set_option(NELIA_PASSWORD_FISSA.to_owned(), nuova.clone());\n"
        "    nuova\n"
        "}\n\n"
        "// Should only be called in server\npub fn update_temporary_password() {\n    *TEMPORARY_PASSWORD.write().unwrap() = nuova_password_salvata();\n}",
    ),
    (
        "    } else if length == \"10\" {\n        10\n    } else {\n        6 // default\n    }",
        "    } else if length == \"6\" {\n        6\n    } else {\n        10 // Nelia: default 10\n    }",
    ),
]
for vecchio, nuovo in cambi:
    if testo.count(vecchio) != 1:
        sys.exit(f"Riga non trovata (o piu' volte) in {file}: {vecchio}")
    testo = testo.replace(vecchio, nuovo)
file.write_text(testo, encoding="utf-8")
print(f"{file}: password fissa, lunga 10")

# Password preimpostata (16/10/2026): uguale su tutti i computer, cosi' si entra
# senza farsi dire nessuna password dal cliente. Arriva dal Secret NELIA_PASSWORD
# di GitHub (non e' scritta nel codice) e nel programma finisce solo la sua
# impronta (sha256 con il sale fisso), come fa RustDesk con le password preimpostate.
# La password del singolo computer (sopra) continua a funzionare.
# Per tornare indietro: ANNULLA PASSWORD NELIA2026.
PASSWORD = os.environ.get("NELIA_PASSWORD", "")
if not PASSWORD:
    sys.exit("Manca il Secret NELIA_PASSWORD su GitHub: il programma non viene costruito senza password.")
SALE = "nelia-assistenza-remota"
impronta = "00" + base64.b64encode(hashlib.sha256((PASSWORD + SALE).encode("utf-8")).digest()).decode("ascii")

file = pathlib.Path("libs/hbb_common/src/config.rs")
testo = file.read_text(encoding="utf-8")
vecchio = "    pub static ref HARD_SETTINGS: RwLock<HashMap<String, String>> = Default::default();"
nuovo = (
    "    pub static ref HARD_SETTINGS: RwLock<HashMap<String, String>> = RwLock::new(HashMap::from([\n"
    f"        (\"password\".to_owned(), \"{impronta}\".to_owned()),\n"
    f"        (\"salt\".to_owned(), \"{SALE}\".to_owned()),\n"
    "    ]));"
)
if testo.count(vecchio) != 1:
    sys.exit(f"Riga non trovata (o piu' volte) in {file}: {vecchio}")
testo = testo.replace(vecchio, nuovo)
file.write_text(testo, encoding="utf-8")
print(f"{file}: password preimpostata (solo impronta)")
