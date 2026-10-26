# WindowSmash Launcher

Un seul fichier pour installer, mettre à jour et lancer **WindowSmash** : Super Smash Bros. Ultimate en version
PC native (une recompilation du jeu Switch, projet [OpenSmash-Ultimate/WindowSmash](https://github.com/OpenSmash-Ultimate/WindowSmash)),
avec le jeu en ligne entre amis.

Tout est construit sur ton PC à partir de **tes propres fichiers**, dumpés de ta console. Ce dépôt ne contient
aucun fichier du jeu, aucune clé, aucun firmware.

## Ce qu'il te faut

- Windows 10 ou 11, 64 bits.
- Un processeur avec AVX2 (la plupart des PC depuis 2015) et une carte graphique compatible Direct3D 11.
- Environ **35 Go libres** sur un disque qui n'est pas dans OneDrive, et 16 Go de RAM conseillés.
- Internet (téléchargement des outils : Git, Python, outils Microsoft, compilateur).
- **Tes fichiers**, dumpés de ta Switch :
  - le jeu de base Smash Ultimate **1.0.0** (`.xci` ou `.nsp`) ;
  - la mise à jour **13.0.5** (`.nsp`) : WindowSmash ne marche qu'avec cette version ;
  - ton fichier **`prod.keys`** (Lockpick_RCM).

## Installation

1. Ouvre **[WindowSmash Launcher.bat](https://github.com/Nilsix/WindowSmashLauncher/blob/main/WindowSmash%20Launcher.bat)**
   et clique sur le bouton **« Download raw file »** (la flèche vers le bas, en haut à droite du fichier).
   Mets le fichier où tu veux (Bureau, par exemple) : il se met à jour tout seul.
2. Double-clique dessus. Si Windows affiche « Windows a protégé votre ordinateur » : « Informations
   complémentaires », puis « Exécuter quand même ».
3. Choisis **1) Installer**, réponds **O** pour installer les outils qui manquent, accepte les fenêtres
   administrateur, choisis où installer, puis donne tes fichiers quand il les demande.

Compte **1 h 30 à 4 h** selon le PC (la compilation du jeu est longue, et la précompilation des shaders peut
prendre jusqu'à 2 h). Ferme les jeux et les gros programmes pendant ce temps. Tu peux fermer la fenêtre et
relancer le launcher : il reprend où il en était.

À la fin, deux raccourcis sont créés sur le Bureau et dans le menu Démarrer :

- **Smash Ultimate (WindowSmash)** : lance le jeu (en vérifiant les mises à jour à chaque fois) ;
- **WindowSmash Launcher** : le menu (installer, jouer, débloquer, optimiser, diagnostic).

## Mises à jour

Automatiques : à chaque lancement, le launcher se met à jour tout seul (et redémarre s'il a changé). Si une
nouvelle version de WindowSmash est choisie, il propose de la recompiler avant de jouer : en ligne, **tout le
monde doit avoir exactement la même version**.

Depuis octobre 2026, WindowSmash ne marche qu'avec la mise à jour **13.0.5** du jeu. Si tu avais installé avec la
13.0.4 : dumpe la 13.0.5 depuis ta Switch à jour, lance le launcher, accepte la mise à jour et choisis le fichier
13.0.5 quand il le demande. Ta sauvegarde est reprise ; l'ancien dossier `v13.0.4` peut ensuite être supprimé
(le launcher le propose).

## Le menu

| Choix | Ce qu'il fait |
| :--- | :--- |
| 1) Installer / reprendre | Installe tout, ou met à jour une installation existante. |
| 2) Lancer le jeu | Ouvre la fenêtre WindowSmash (réglages), puis le jeu en ligne. |
| 3) Diagnostic | Crée un rapport sans rien installer. |
| 4) Débloquer tous les personnages | Après avoir lancé le jeu une fois puis l'avoir fermé. |
| 5) Optimiser | Précompile les shaders (FPS stables) et met la latence d'affichage à 1. |
| 6) Ajouter mes DLC | Ajoute au jeu les DLC que tu as achetés, dumpés de ta Switch (dossier de fichiers `.nsp`). En ligne, ayez les mêmes DLC. |
| 7) Français / English | Le launcher est en anglais par défaut : **7** le passe en français (et **7** le remet en anglais). Le choix est gardé. |

## Jouer en ligne

1. Lance le jeu avec le raccourci. La première fois, il demande ton pseudo en ligne.
2. Une fenêtre **WindowSmash** s'ouvre : version du jeu, affichage (fenêtre ou plein écran, taille), en ligne,
   manettes. Clique sur **Play**. (Case « Start the game directly » : le jeu démarre directement les fois
   suivantes ; garde Maj enfoncée pendant le lancement pour revoir la fenêtre.)
3. Si Windows demande l'autorisation pour `ssbu.exe`, coche **Réseaux privés et publics**.
4. Dans le jeu : **Local Wireless**. Un joueur crée une room, les autres la choisissent dans la liste.
   Aucun port à ouvrir, pas de VPN : tout passe par le lobby public `smash.recomps.wtf`.
5. Rooms entre amis seulement : dans la fenêtre WindowSmash, choisissez **Private lobby (a code)** et mettez
   **le même code** chez tout le monde. Hors ligne : **Offline**.
6. Nouveau, encore en test : le mode **Online** du jeu. Menu principal, **Online**, **Smash**, **Quickplay** : il
   trouve un autre joueur WindowSmash qui cherche en même temps. Garde le fichier `netplay_id.txt` du dossier
   WindowSmash : c'est ton compte (ne le donne à personne).

En jeu : **Échap** ouvre le menu des réglages, **F1** l'overlay (il doit afficher `Online`), **F11** le plein écran.

Clavier : flèches = stick, Z/X/C/V = A/B/X/Y, A/S = L/R, Q/W = ZL/ZR, Entrée = +.
Les manettes (Xbox, PlayStation, Switch Pro...) marchent directement.

## Si ça ne marche pas

Le launcher s'arrête avec un code (E10 à E99) et une explication, et écrit **`WindowSmash-setup-report.txt`**
sur ton Bureau. Envoie ce fichier tel quel : il ne contient ni clés ni fichiers du jeu.

## OpenSmash Launcher (l'autre version, avec rollback)

[OpenSmash](https://github.com/OpenSmash-Ultimate/ssbu-recomp) est une autre recompilation de Smash Ultimate (rendu
Vulkan) avec un **rollback netcode** expérimental. Son launcher marche comme celui de WindowSmash :

1. Ouvre **[OpenSmash Launcher.bat](https://github.com/Nilsix/WindowSmashLauncher/blob/main/OpenSmash%20Launcher.bat)**,
   clique sur **« Download raw file »**, puis double-clique sur le fichier et choisis **1) Install**.
2. Il installe OpenSmash à côté de WindowSmash (ou où tu veux, environ **30 Go**) dans **la version choisie pour tout
   le groupe**, pas forcément la dernière : en ligne, tout le monde doit avoir la même. Il reprend les fichiers du jeu
   déjà donnés au launcher WindowSmash (jeu de base 1.0.0, mise à jour **13.0.5**, `prod.keys`). Pas besoin de Visual
   Studio. Compte 1 à 3 h la première fois.
3. À la fin : raccourcis **Smash Ultimate (OpenSmash)** (lance le jeu en vérifiant la version) et **OpenSmash
   Launcher** (le menu).

Par défaut (raccourci, option 2), le jeu utilise son **netcode d'origine** ; l'option 8 le lance **avec le rollback**. Il sert dans les rooms **Local Wireless à 2
joueurs** qui l'ont tous les deux ; les rooms à plus de 2 joueurs et les combats locaux se jouent comme d'habitude.
OpenSmash a son propre lobby : les joueurs WindowSmash et OpenSmash ne se voient pas, choisissez le même entre amis.

| Choix | Ce qu'il fait |
| :--- | :--- |
| 1) Installer / mettre à jour | Installe OpenSmash, ou le met à la version du groupe et recompile. |
| 2) Lancer le jeu | Lance le jeu (netcode d'origine, sans rollback). |
| 3) Diagnostic | Si le jeu rame ou plante : examine le PC (RAM, carte graphique et pilote, disque), les réglages, les rapports de plantage du jeu et son dernier log, donne des conseils (pilote, overlays comme Medal / OBS, disque lent, mode PC peu puissant) et crée `OpenSmash-setup-report.txt` sur le Bureau, à envoyer au groupe. |
| 4) Ajouter mes DLC | Les DLC que tu as achetés, dumpés de ta Switch (dossier de fichiers `.nsp`, noms d'origine) : même dossier que l'option 6 du launcher WindowSmash. Pas de recompilation. En ligne, ayez les mêmes DLC. |
| 5) Débloquer tous les personnages | Les 74 personnages de base dans ta sauvegarde (les DLC restent au jeu). Après un premier lancement du jeu, jeu fermé ; une copie de la sauvegarde d'avant est gardée dans `build\save_backups`. |
| 6) Mode PC peu puissant | On / off : résolution interne réduite de moitié et shaders chargés au fil des chargements (moins de mémoire), pour une carte graphique faible ou intégrée. |
| 7) Français / English | Même réglage de langue que le launcher WindowSmash. |
| 8) Lancer le jeu avec rollback | Expérimental, demande un bon processeur (un Ryzen 2700X tombait sous 40 fps) ; les deux joueurs doivent le lancer ainsi. |

N'utilise pas `Install SSBU.bat` ni les raccourcis « SSBU native » d'OpenSmash : ils le mettraient à jour au-delà de
la version du groupe. Il faut une carte graphique avec un pilote **Vulkan 1.3**.

## Pour les développeurs

- `WindowSmash Launcher.bat` : l'amorce (Git, clone et mise à jour de ce dépôt, redémarrage, puis le kit).
- `kit/ws_setup.ps1` : l'installateur (PowerShell 5.1, doit rester en UTF-8 avec BOM).
- `kit/ws_setup.py` : la partie Python (lecture des fichiers du jeu, puis compilation par `tools/build_game.py` de
  WindowSmash).
- `OpenSmash Launcher.bat` : la même amorce pour OpenSmash (même clone de ce dépôt).
- `kit-opensmash/os_setup.ps1` : l'installateur d'OpenSmash (version figée `$OS_COMMIT`, l'installateur d'OpenSmash
  lancé avec `--no-self-update`, rollback écrit dans `config\graphics.ini` avant chaque lancement).
