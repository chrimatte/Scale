# Scale per Mac — sorgenti e manutenzione

App SwiftUI locale per acquisire una pesata Renpho ES-CS20M e sincronizzarla con Intervals.icu. Requisiti: Mac Apple Silicon, macOS 14 o successivo, Bluetooth e Internet. La copia operativa è `~/Applications/Scale.app`.

## Struttura

La cartella principale contiene `Scale-sorgenti`, `Scale.app`, `ble-scale-sync` e `work` come cartelle sorelle. Per preparare una nuova copia, segui il [README principale](../README.md).

L’app legge `ScaleProjectRoot` dal proprio `Info.plist`, impostato da `build.sh` al percorso corrente di `ble-scale-sync`. Avvia il runtime Node.js locale da `work/runtime/node_modules/.bin/node` e l’helper nel bundle. L’helper legge la configurazione e avvia il motore compilato in `ble-scale-sync/dist`.

La chiave resta in `ble-scale-sync/.env`, fuori dal bundle. Il profilo è in `ble-scale-sync/config.yaml`. Le impostazioni salvano entrambi con permessi `0600` dopo aver verificato il collegamento con una richiesta di sola lettura. I file di avvio alternativi usano gli stessi dati.

`work/mac-app` contiene lo stato precedente delle pesate e la configurazione temporanea. La configurazione temporanea viene rigenerata a ogni pesata, conservando i marcatori contro i duplicati.

## Compilazione e installazione

Dalla cartella principale:

```sh
./Scale-sorgenti/build.sh
./Scale-sorgenti/install.sh
```

Gli script funzionano anche se avviati da un’altra cartella. `build.sh` compila in una cartella temporanea, firma e verifica il nuovo bundle prima di sostituire `Scale.app`, conservando una copia precedente. Usa una sovrapposizione virtuale per evitare un modulo SwiftBridging duplicato in alcune installazioni dei Command Line Tools, senza modificare gli strumenti di sistema.

`install.sh` richiede Scale chiusa e un bundle compilato per la posizione corrente del progetto. Verifica la firma e aggiorna `~/Applications/Scale.app`, conservando la versione precedente in `work/backups/install.*`. Identità dell’app e icona restano `local.chrimatte.scale` e `AppIcon.icns`; il Dock continua a puntare alla copia installata.

Dopo aver spostato l’intera cartella del progetto, esegui nuovamente entrambi gli script dalla nuova posizione. La versione già installata conserva il percorso impostato durante la compilazione.

## Test e controlli locali

Dalla cartella principale:

```sh
work/runtime/node_modules/.bin/node --test Scale-sorgenti/core.test.mjs Scale-sorgenti/bridge.test.mjs Scale-sorgenti/settings.test.mjs
(cd ble-scale-sync && ../work/runtime/node_modules/.bin/node dist/index.js validate)
(cd ble-scale-sync && ../work/runtime/node_modules/.bin/node node_modules/typescript/bin/tsc --noEmit)
```

I test usano dati fittizi, connessioni simulate e cartelle temporanee; non inviano pesate e non modificano il profilo reale. I percorsi delle fixture dipendono dalla posizione dei file di test, non dalla cartella di lavoro.

Per ricompilare il motore BLE già completo di dipendenze:

```sh
(cd ble-scale-sync && ../work/runtime/node_modules/.bin/node node_modules/typescript/bin/tsc)
```

## Comportamento da preservare

- Peso senza stima del grasso come impostazione iniziale; la stima si abilita esplicitamente.
- Un eventuale grasso già registrato su Intervals.icu resta invariato in modalità solo peso.
- Conferma finale solo dopo rilettura indipendente dei valori salvati.
- Interrompere arresta il processo di lettura; un invio già completato resta sul servizio.
- Impostazioni non modificabili durante una pesata; chiave vuota significa mantenere quella corrente.
- Nessuna sostituzione dell’icona durante l’esecuzione.

Le simulazioni non sostituiscono una pesata fisica. Il confronto completo tra aspetto chiaro/scuro e VoiceOver non è stato verificato.
