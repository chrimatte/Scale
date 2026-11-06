# Scale per Mac

Scale è un'interfaccia per macOS che rende più semplice usare [ble-scale-sync](https://github.com/KristianP26/ble-scale-sync), il motore Bluetooth sviluppato dal progetto originale. Consente di leggere il peso da una bilancia Renpho ES-CS20M e caricarlo automaticamente su Intervals.icu: dopo aver configurato il proprio account, l'utente avvia una pesata dall'app e Scale gestisce lettura, invio e verifica del salvataggio.

Il repository Scale contiene un riferimento Git al motore: i sorgenti di ble-scale-sync vengono scaricati separatamente dal repository originale tramite submodule. L'integrazione è stata sviluppata per questa bilancia; non è stata verificata con tutti i dispositivi supportati dal motore.

Scale è un progetto non ufficiale e non è affiliato né approvato da Renpho o Intervals.icu. I rispettivi nomi identificano i prodotti e servizi compatibili.

La modalità iniziale invia solo il peso. La stima del grasso è facoltativa e non corrisponde a una misurazione della bilancia. Scale rilegge il servizio dopo l'invio; più pesate nello stesso giorno aggiornano il record giornaliero.

## Requisiti

- Mac Apple Silicon con macOS 14 o successivo, Bluetooth e connessione Internet.
- Apple Command Line Tools, Python 3, npm e Git. La compilazione del motore può richiedere gli strumenti nativi previsti da ble-scale-sync.
- Un account Intervals.icu e una chiave API. Il codice e il runtime restano sul Mac; la pesata viene inviata a Intervals.icu.

## Installazione da sorgente

Da Terminale, clona il repository con il submodule. Usa l'URL del repository Scale dopo la sua pubblicazione; se hai già una copia senza submodule, esegui `git submodule update --init` dalla sua cartella. Poi, dalla radice del progetto:

```sh
npm ci --prefix work/runtime
export PATH="$PWD/work/runtime/node_modules/.bin:$PATH"
npm ci --prefix ble-scale-sync
npm run build --prefix ble-scale-sync
cp -n Scale-sorgenti/config.yaml.example ble-scale-sync/config.yaml
chmod 600 ble-scale-sync/config.yaml
./Scale-sorgenti/build.sh
./Scale-sorgenti/install.sh
```

Il comando `cp -n` preserva un profilo già presente. Il file contiene inizialmente dati fittizi, che devono essere sostituiti nelle impostazioni. Apri `~/Applications/Scale.app`, vai in **Impostazioni**, inserisci profilo, ID atleta e chiave API di Intervals.icu e scegli **Salva e verifica**. La verifica richiede una connessione al servizio. La chiave viene salvata in `ble-scale-sync/.env` e il profilo in `ble-scale-sync/config.yaml`; entrambi sono locali ed esclusi da Git. La chiave viene inviata a Intervals.icu tramite HTTPS per autenticare le richieste. Non condividere quei file.

L'app installata dipende dalla cartella del progetto e dal motore compilato: non spostarli o eliminarli. Se sposti la cartella completa, ricompila e reinstalla. Gli script mantengono copie precedenti in `work/backups`. Per i dettagli e i controlli consulta [CONTRIBUTING.md](CONTRIBUTING.md) e [Scale-sorgenti/README.md](Scale-sorgenti/README.md).

## Utilizzo

Apri Scale, attendi il collegamento, premi **Avvia pesata** e sali sulla bilancia. Chiudi l'app Renpho sul telefono e tieni il Mac acceso e vicino alla bilancia. Le opzioni del profilo si trovano in **Impostazioni**. Non utilizzare contemporaneamente l'app e gli script alternativi di sincronizzazione continua.

L'app non importa lo storico Renpho e non è configurata per l'avvio automatico. Gli script `.command` sono un'interfaccia alternativa al motore e richiedono un profilo configurato.

## Privacy e dati

Scale memorizza il profilo e la chiave API nel progetto sul Mac. Le pesate e i dati necessari al funzionamento sono conservati localmente e inviati a Intervals.icu; Scale legge anche i dati del servizio necessari alla verifica. Il progetto non prevede un server proprio di raccolta dati né funzioni di telemetria. Intervals.icu tratta i dati ricevuti secondo le proprie condizioni e la propria informativa privacy.

La chiave API dà accesso ai dati dell'account: ogni utente è responsabile della sua custodia e deve proteggere il proprio Mac e i backup, senza pubblicare `.env`, il profilo, le pesate o i log che possono contenerli. L'autore non assume responsabilità per la custodia o la divulgazione della chiave da parte dell'utente, nei limiti consentiti dalla legge. Se sospetti che la chiave sia stata esposta, rigenerala su Intervals.icu. L'uso dell'API è soggetto ai [termini di Intervals.icu](https://forum.intervals.icu/t/intervals-icu-api-terms-and-conditions/114087).

## Destinazione d'uso e responsabilità

Scale è uno strumento amatoriale destinato al monitoraggio personale e al benessere. Non è un dispositivo medico e non è destinato a diagnosi, prevenzione o trattamento di condizioni mediche. Le informazioni e le stime fornite non sostituiscono il parere di un professionista sanitario.

Il software è fornito senza garanzie, nei limiti consentiti dalla legge. L'autore non assume responsabilità per danni derivanti dall'uso, da errori di misurazione o sincronizzazione, né dalla disponibilità di servizi o dispositivi di terze parti, nei limiti consentiti dalla legge. Controlla i valori registrati su Intervals.icu e conserva backup dei dati importanti.

## Realizzazione

Scale è stato implementato con l'assistenza di OpenAI Codex. L'icona è stata generata con l'ausilio di intelligenza artificiale.

## Licenza

Il codice e le risorse originali di Scale sono distribuiti secondo la [GNU General Public License versione 3](LICENSE) (GPL-3.0-only). Il motore [ble-scale-sync](https://github.com/KristianP26/ble-scale-sync), sviluppato separatamente, mantiene la propria licenza GPL-3.0 e i relativi avvisi, disponibili nel suo repository.
