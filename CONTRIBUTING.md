# Sviluppare Scale

Il repository principale contiene l'app SwiftUI per macOS, gli helper JavaScript,
i test, gli script e le risorse. Non incorpora i file del motore: `ble-scale-sync`
è un riferimento Git a un sottomodulo upstream,
fissato inizialmente al commit `e2bb0666d47c9a546be454029329d5cb64d53a2b`
(versione 1.39.1). Conserva storia, remoto e convenzioni proprie; il setup del
repository principale non modifica il motore.

## Convenzioni Git

- Branch principale: `main`; branch brevi `feat/<tema>`, `fix/<tema>` e
  `chore/<tema>`. Quando si collabora, integrare tramite pull request e review.
- Conventional Commits: `<tipo>(<scope opzionale>): <descrizione>`.
  Tipi usuali: `feat`, `fix`, `docs`, `test`, `refactor`, `build`, `ci`, `chore`.
  Usare `!` o il footer `BREAKING CHANGE:` per cambiamenti incompatibili.
- Aggiungere soltanto percorsi esaminati. Controllare `git diff --cached`
  prima del commit; non includere profili, chiavi API o pesate.
- Gli aggiornamenti al sottomodulo sono espliciti: prima verificare i suoi
  cambiamenti e test, poi registrare il nuovo riferimento con
  `git add -- ble-scale-sync` nel repository principale.

## Ripristino di una copia di sviluppo

Servono macOS 14 o successivo su Apple Silicon, Apple Command Line Tools,
Python 3, npm e un Node compatibile con il manifest del motore. Il runtime locale
è fissato da `work/runtime/package-lock.json`. Dalla radice, in una nuova copia:

```sh
git submodule update --init
npm ci --prefix work/runtime
export PATH="$PWD/work/runtime/node_modules/.bin:$PATH"
npm ci --prefix ble-scale-sync
npm run build --prefix ble-scale-sync
cp -n Scale-sorgenti/config.yaml.example ble-scale-sync/config.yaml
chmod 600 ble-scale-sync/config.yaml
```

La prima inizializzazione del sottomodulo scarica i sorgenti dal repository
originale; gli archivi ZIP generati dal repository principale non li includono.
Anche `npm ci` scarica dipendenze.
Il repository non contiene credenziali, il profilo personale, lo stato delle
pesate, i backup o l'app compilata. La configurazione iniziale è fittizia: inserisci
il tuo profilo nelle impostazioni dell'app. Conserva separatamente e in modo
privato gli eventuali backup dei dati locali: Git non li sostituisce.

## Controlli

Dalla radice, usando il runtime già disponibile:

```sh
work/runtime/node_modules/.bin/node --test Scale-sorgenti/core.test.mjs Scale-sorgenti/bridge.test.mjs Scale-sorgenti/settings.test.mjs
(cd ble-scale-sync && ../work/runtime/node_modules/.bin/node node_modules/typescript/bin/tsc --noEmit)
zsh -n Scale-sorgenti/build.sh Scale-sorgenti/install.sh '1 - Collega Intervals.command' '2 - Avvia sincronizzazione.command'
```

I test dell'app usano fixture e connessioni simulate. Non inviano pesate.
Per modifiche al motore seguire anche `ble-scale-sync/CONTRIBUTING.md`.
Compilazione e installazione dell'app sono documentate in
`Scale-sorgenti/README.md`; non vengono eseguite dall'hook.

## Hook locale

Il controllo leggero è `.githooks/pre-commit`: richiede Python 3 e Gitleaks
nel `PATH`, controlla whitespace e conflitti, esporta l'intero indice esatto in
una cartella temporanea privata e lo scansiona con Gitleaks. Elimina poi l'export;
non modifica file o staging. Non stampa valori sensibili.

Per abilitarlo in una nuova copia, verificare prima `core.hooksPath` e gli hook
già presenti. In assenza di un altro gestore:

```sh
git config --local core.hooksPath .githooks
```

Controllo manuale equivalente, anche prima del primo commit:

```sh
python3 .githooks/pre-commit
```

Se manca Gitleaks, il commit si ferma: rendere disponibile lo scanner prima di
riprovare, senza bypassare l'hook. Il controllo riguarda i blob del repository
principale; non scansiona i file privati ignorati, gli archivi o la storia del
motore. Prima di pubblicare nuovi commit, verificare anche la storia delle ref
da caricare.
