# Edith Updater

Aggiorna Edith ML da una release GitHub verificata.

Ogni avvio dell'add-on:

1. cerca l'ultima release;
2. verifica checksum del pacchetto e dei singoli file;
3. crea un backup;
4. aggiorna AppDaemon e il package Home Assistant;
5. controlla la configurazione;
6. riavvia AppDaemon e Home Assistant;
7. esegue rollback automatico in caso di configurazione non valida.

Alla prima installazione `update_on_start` applica automaticamente l'ultima
release, creando anche gli helper Home Assistant necessari.

La versione 1.0.2 corregge la lettura delle opzioni al primo avvio e attende
silenziosamente che Home Assistant crei lo switch di aggiornamento.

La versione 1.0.3 gestisce il riavvio tramite Supervisor senza interpretare
come errore la normale chiusura della connessione durante il riavvio.

Per un repository privato, inserire nelle opzioni un token GitHub con solo
permesso di lettura sul repository Edith.
