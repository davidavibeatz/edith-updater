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

Per un repository privato, inserire nelle opzioni un token GitHub con solo
permesso di lettura sul repository Edith.
