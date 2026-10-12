# Nelia Assistenza Remota

Programma di assistenza remota per i clienti di Nelia (mynelia.it), costruito su
[RustDesk](https://github.com/rustdesk/rustdesk) 1.5.0, software libero con licenza
**AGPL-3.0**. Il codice di questo progetto è pubblico come richiede la licenza.

Cosa cambia rispetto a RustDesk:
- nome «Nelia Assistenza Remota» e icona con la N di Nelia;
- si collega al server di Nelia (`2.31.51.60`) con la sua chiave, già scritti dentro
  (`nelia/applica-hbb-common.py`, applicato durante la costruzione);
- si costruisce da GitHub con `.github/workflows/nelia.yml` (solo Windows e Mac).

Download: sezione **Releases** di questo progetto.
