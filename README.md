# OpenSmash Ultimate Launcher

Ce launcher ouvre **OpenSmash.exe**, le launcher officiel d'**OpenSmash Ultimate** : Super Smash Bros. Ultimate en
version PC native (une recompilation du jeu Switch, projet
[OpenSmash-Ultimate/OpenSmash-Ultimate](https://github.com/OpenSmash-Ultimate/OpenSmash-Ultimate)).

Depuis la v0.4.0 (novembre 2026), OpenSmash.exe installe le jeu, le met à jour avec chaque version publiée et le
lance. Tout le monde reste ainsi sur la même version, ce que faisait ce launcher jusqu'au kit 4.5.

## Ce qu'il fait à chaque lancement

1. Il trouve ton dossier de jeu, celui qu'il avait installé.
2. Un dossier installé par le kit 4 est une copie git bloquée sur une ancienne version. Il le prépare pour que
   OpenSmash.exe puisse le mettre à jour : son `.git` est renommé `.git-kit4` (gardé) et son installeur devient celui
   de la dernière version. Tes fichiers du jeu, tes builds, ta sauvegarde et tes réglages restent en place.
3. Il met dans ce dossier l'OpenSmash.exe de la dernière version (vérifié avec son `.sha256`), puis il le lance.
   Sans dossier de jeu, OpenSmash.exe va dans tes Téléchargements, et son premier écran installe le jeu.
   Cet OpenSmash.exe est compilé chez toi, avec un onglet de plus : NILSIX TOOLS (voir plus bas). Il faut pour ça le
   SDK .NET 8 (ou plus récent). Si ton PC ne l'a pas, le kit télécharge celui de Microsoft une seule fois, pour lui
   seul : environ 300 Mo à télécharger, 750 Mo sur le disque (dans `%LOCALAPPDATA%\WindowSmash-setup\dotnet`), sans
   droits administrateur. La compilation télécharge aussi environ 100 Mo de paquets (380 Mo dans
   `%USERPROFILE%\.nuget\packages`).

La première fois, OpenSmash propose une mise à jour : accepte-la. Il met le jeu à jour et le recompile (de quelques
minutes à une heure). Ensuite, ouvre ce launcher ou OpenSmash.exe, comme tu préfères.

Nouveau joueur ? Le plus simple est de télécharger directement
[OpenSmash.exe](https://github.com/OpenSmash-Ultimate/OpenSmash-Ultimate/releases/latest/download/OpenSmash.exe) :
voir le [guide d'installation](https://github.com/OpenSmash-Ultimate/OpenSmash-Ultimate/blob/main/docs/INSTALL.md).
Il te faut ton jeu en 13.0.5, ton `prod.keys`, et environ 60 Go libres.

Le double boot (option 8, OpenSmash = ssbu-recomp) n'existe plus : une installation ssbu-recomp reste sur ton disque
et se lance avec ses propres fichiers.

## NILSIX TOOLS : la synchro des mods

L'onglet NILSIX TOOLS se trouve entre COMPETITIVE et PARAMÈTRES. Il est compilé depuis les sources de la version
publiée d'OpenSmash, avec la même version : le jeu ne change pas, et tu restes compatible en ligne avec ceux qui ont
l'OpenSmash.exe normal. Si la compilation échoue (pas d'internet, disque plein), tu gardes l'OpenSmash.exe normal, et
le kit réessaie à son prochain lancement.

Pour jouer en ligne avec des mods, il faut exactement les mêmes des deux côtés :

1. Dans NILSIX TOOLS, clique sur **CRÉER LE FICHIER**. Ses étapes s'affichent dans la barre en bas, comme les tâches
   d'OpenSmash. D'abord, tes mods qui ont une version plus récente sur GameBanana sont mis à jour tout seuls : même
   dossier, même activation, même place dans l'ordre (pas les autres fichiers de leur page : un ajout, une variante
   ou la version d'un autre jeu). Puis `Synchro mods - <ton nom>.bat` arrive sur ton Bureau, avec un code (par
   exemple `8809-8748`). Le journal liste aussi les conflits entre tes mods.
2. Envoie ce fichier à la personne qui joue avec toi. Elle ferme OpenSmash et double-clique dessus. Elle n'a pas
   besoin de ce launcher : OpenSmash suffit. Si Windows bloque un fichier téléchargé : « Informations
   complémentaires », puis « Exécuter quand même ».
3. Le fichier installe tes mods depuis GameBanana, aux mêmes versions que les tiens. Il active ceux que tu as activés
   et désactive les autres, dans ton ordre. Il met les mêmes plugins, puis applique les mods.
4. À la fin, elle doit voir **SYNCHRO OK** et le même code que toi. Sinon, le fichier dit ce qui diffère.

Ses mods que tu n'as pas sont désactivés, jamais supprimés. Un de ses dossiers qui porte le nom d'un de tes mods mais
contient d'autres fichiers est remplacé par le tien si c'est le même mod GameBanana (une autre version), sinon renommé
« (ancien) » et désactivé. Un mod qui ne vient pas de GameBanana ne peut pas être téléchargé : le fichier le signale.

Quand CRÉER LE FICHIER a mis des mods à jour, le code change : renvoie le nouveau fichier à la personne qui joue avec
toi.

### La fusion : les mods des deux

**CRÉER UNE FUSION** ajoute tes mods à ceux de la personne qui joue avec toi, sans désactiver les siens :

1. Clique sur **CRÉER UNE FUSION**. Comme pour CRÉER LE FICHIER, tes mods sont d'abord mis à jour depuis GameBanana.
   `Fusion mods - <ton nom>.bat` arrive sur ton Bureau. Seuls tes mods activés en font partie.
2. Envoie-le. Elle ferme OpenSmash et double-clique dessus. Ses propres mods activés sont mis à jour depuis
   GameBanana, puis tes mods s'ajoutent aux siens. Les siens gardent leur activation, sauf une autre version d'un de
   tes mods : elle est désactivée (gardée) et c'est la tienne qui sert. Les plugins des deux restent.
3. À la fin, elle voit **FUSION OK**, avec la liste des conflits (ceux entre ses mods et les tiens d'abord). Ses mods
   passent après les tiens dans l'ordre, donc ce sont eux qui gagnent un conflit. Un fichier
   `Synchro mods - <son nom>.bat` arrive sur son Bureau.
4. Elle te le renvoie et tu double-cliques dessus (OpenSmash fermé). Tu reçois ses mods dans le même ordre, puis
   **SYNCHRO OK** et le même code des deux côtés.

Un de ses mods qui ne vient pas de GameBanana doit être copié à la main dans ton dossier `mods` : le fichier le
signale.

### Les mises à jour

Avec NILSIX TOOLS, ce launcher ne sert qu'à installer : ensuite, ses raccourcis (Bureau, menu Démarrer) ouvrent
directement OpenSmash.exe, qui se met à jour tout seul. Il n'en garde qu'un par dossier : ses autres raccourcis
(« Smash Ultimate (...) ») sont supprimés, et tous quand le dossier a déjà le sien vers OpenSmash.exe (par exemple
« OpenSmash » dans le menu Démarrer).

- Une nouvelle version d'OpenSmash : OpenSmash la propose comme d'habitude. Si tu acceptes, son nouveau launcher est
  compilé chez toi avec l'onglet NILSIX TOOLS (de 30 secondes à quelques minutes), puis OpenSmash redémarre et met le
  jeu à jour.
- Une nouvelle version de NILSIX TOOLS : OpenSmash la cherche à chaque démarrage, en arrière-plan, et la compile
  (environ une minute). Ensuite il se ferme et se relance tout seul avec elle, dès que rien ne serait coupé : pas de
  partie lancée, pas de tâche dans la barre du bas, pas de question ouverte, fenêtre pas réduite. Si tu as lancé une
  partie avant la fin, elle sert au démarrage suivant. L'état s'affiche à droite du journal, dans l'onglet.
- Si la compilation échoue (par exemple quand OpenSmash a changé une partie du code dont l'onglet a besoin), OpenSmash
  prend son launcher normal, sans l'onglet, et les raccourcis redeviennent ceux d'avant. Il retente la compilation à
  chaque lancement, jusqu'à ce que le kit soit corrigé. Le détail est dans
  `%LOCALAPPDATA%\WindowSmash-setup\nilsix-launcher\update.log`.

## Ça ne marche pas ? Le diagnostic

Fais un clic droit sur [Diagnostic OpenSmash.bat](https://github.com/Nilsix/WindowSmashLauncher/raw/main/Diagnostic%20OpenSmash.bat),
puis « Enregistrer le lien sous… », et double-clique sur le fichier. Si tu as ce launcher, il est déjà là :
`%LOCALAPPDATA%\WindowSmashLauncher\Diagnostic OpenSmash.bat`. Si Windows le bloque : « Informations
complémentaires », puis « Exécuter quand même ».

En une minute environ, il écrit `Diagnostic OpenSmash.txt` sur ton Bureau, avec en haut ce qui semble ne pas aller.
Envoie ce fichier à Nilsix.

Il ne change rien. Il lit ton PC (Windows, processeur, RAM, carte graphique, disques), l'état du dossier du jeu,
d'OpenSmash.exe et de NILSIX TOOLS, tes réglages et ta liste de mods. Il vérifie aussi l'accès aux sites dont les mises
à jour ont besoin, et lit la fin des journaux d'OpenSmash et de son dernier rapport. Il ne lit jamais tes clés
(`prod.keys`), les fichiers du jeu, ta connexion au compte ou à Discord, ni les fichiers `.dmp`. Ton nom d'utilisateur
Windows, le nom du PC et les adresses IP publiques sont masqués dans le rapport.

## Pour les développeurs

- `OpenSmash Ultimate Launcher.bat` : l'amorce (Git, clone et mise à jour de ce dépôt, redémarrage, puis le kit).
  `WindowSmash Launcher.bat` et `OpenSmash Launcher.bat` en sont des copies identiques : les anciens launchers se
  mettent à jour depuis le fichier de leur nom (garder les trois identiques).
- `kit/ws_setup.ps1` : le kit 5, qui passe la main à OpenSmash.exe (PowerShell 5.1, UTF-8 avec BOM et CRLF).
- `kit-opensmash/os_setup.ps1` : renvoie vers `kit/ws_setup.ps1` (pour les anciennes amorces OpenSmash).
- `kit/nilsix_launcher.ps1` : compile OpenSmash.exe avec la page NILSIX TOOLS, à partir de l'archive des sources du
  commit de la version publiée (téléchargée sur GitHub). Il ajoute 8 points d'accroche dans `OpenSmash.Launcher` ; si
  l'un d'eux a changé en amont, rien n'est compilé et l'OpenSmash.exe publié est mis à la place.
  `%LOCALAPPDATA%\WindowSmash-setup\nilsix-launcher\record.json` évite de recompiler quand rien n'a changé.
  OpenSmash.exe le lance aussi comme script, avec les fichiers du kit téléchargés sur GitHub : à chaque démarrage, et à
  la place de sa propre mise à jour (`nilsix_launcher.ps1 <dossier> [<version> <commit>]` ; code de sortie 0 = déjà
  compilé, 10 = compilé à l'instant, 1 = pas compilé). `Set-NilsixShortcuts` fait ouvrir OpenSmash.exe aux raccourcis
  du .bat et n'en garde qu'un par dossier (il repasse à chaque démarrage réussi) ; `Restore-NilsixShortcuts` les remet
  comme avant, les supprimés compris (`nilsix-launcher\shortcuts.txt` : une ligne par raccourci, `removed` en 6e champ).
- `kit/nilsix/LauncherForm.Nilsix.cs` : la page NILSIX TOOLS, dessinée avec les mêmes fonctions que les autres pages,
  et ses mises à jour (la vérification au démarrage, `NilsixReplaceLauncherAsync`). `NILSIX_KIT_URL` (par exemple
  `file:///D:/WindowSmashLauncher/kit/`) remplace GitHub pour les tests.
- `kit/mods_sync.py` : `make` écrit le fichier .bat, qui contient ce script et la liste des mods. Sur l'autre PC, `sync`
  fait la synchro puis la vérifie (`check` vérifie seulement). Le code est calculé sur la liste de mods que le jeu
  échange en ligne (`runtime/net_relay.c`) ; la vérification compare aussi l'ordre des mods et les plugins. Les étapes
  de `make` vont dans la barre en bas d'OpenSmash (lignes `PROGRESS <0 à 1, ou -1> <texte>`, `SetLoad`).
  `make --fuse` écrit un fichier de fusion (`"mode": "fuse"` dans la liste, mods activés seulement) ; son `sync`
  écrit le fichier de retour dans `--out` (le Bureau, donné par le .bat).
- `Diagnostic OpenSmash.bat` : le diagnostic, un script PowerShell entre `#@@BEGIN diag.ps1` et `#@@END diag.ps1`
  (CRLF, en-tête ASCII). `OPENSMASH_DIAG_OUT` change le fichier écrit, `OPENSMASH_DIAG_QUIET=1` n'ouvre pas
  l'Explorateur.
