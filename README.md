# OpenSmash Ultimate Launcher

Un seul fichier pour installer, mettre à jour et lancer **OpenSmash Ultimate** : Super Smash Bros. Ultimate en
version PC native (une recompilation du jeu Switch, projet
[OpenSmash-Ultimate/OpenSmash-Ultimate](https://github.com/OpenSmash-Ultimate/OpenSmash-Ultimate)), avec le jeu en
ligne entre amis et le rollback netcode (activé par défaut).

Tout est construit sur ton PC à partir de **tes propres fichiers**, dumpés de ta console. Ce dépôt ne contient
aucun fichier du jeu, aucune clé, aucun firmware.

## Ce qu'il te faut

- Windows 10 ou 11, 64 bits.
- Un processeur avec AVX2 (la plupart des PC depuis 2015) et une carte graphique compatible Direct3D 11.
- Environ **35 Go libres** sur un disque qui n'est pas dans OneDrive (de préférence un SSD interne : le jeu lit ses
  données et ses shaders pendant qu'il tourne, un disque dur USB le fait saccader), et 16 Go de RAM conseillés.
- Internet (téléchargement des outils : Git, Python, outils Microsoft, compilateur).
- **Tes fichiers**, dumpés de ta Switch :
  - le jeu de base Smash Ultimate **1.0.0** (`.xci` ou `.nsp`) ;
  - la mise à jour **13.0.5** (`.nsp`) : OpenSmash Ultimate ne marche qu'avec cette version ;
  - ton fichier **`prod.keys`** (Lockpick_RCM) ;
  - facultatif : le **firmware** de ta console (dossier de fichiers `.nca`), pour les polices d'origine du jeu. Sans
    lui, des polices libres les remplacent (autres polices pour le texte latin, pas de texte chinois, japonais ou
    coréen) ; les combats ne changent pas.

## Installation

1. Ouvre **[OpenSmash Ultimate Launcher.bat](https://github.com/Nilsix/WindowSmashLauncher/blob/main/OpenSmash%20Ultimate%20Launcher.bat)**
   et clique sur le bouton **« Download raw file »** (la flèche vers le bas, en haut à droite du fichier).
   Mets le fichier où tu veux (Bureau, par exemple) : il se met à jour tout seul.
2. Double-clique dessus. Si Windows affiche « Windows a protégé votre ordinateur » : « Informations
   complémentaires », puis « Exécuter quand même ».
3. Choisis **1) Installer**, réponds **O** pour installer les outils qui manquent, accepte les fenêtres
   administrateur, choisis où installer (il propose un SSD interne quand il y a la place), puis donne tes fichiers
   quand il les demande.

Compte **1 h 30 à 4 h** selon le PC (la compilation du jeu est longue, et la précompilation des shaders peut
prendre jusqu'à 2 h). Ferme les jeux et les gros programmes pendant ce temps. Tu peux fermer la fenêtre et
relancer le launcher : il reprend où il en était.

À la fin, deux raccourcis sont créés sur le Bureau et dans le menu Démarrer :

- **Smash Ultimate (OpenSmash Ultimate)** : lance le jeu (en vérifiant les mises à jour à chaque fois) ;
- **OpenSmash Ultimate Launcher** : le menu (installer, jouer, diagnostic, optimiser, DLC).

## Tu avais le launcher WindowSmash ou OpenSmash ?

Depuis novembre 2026, WindowSmash et OpenSmash sont **un seul projet : OpenSmash Ultimate**, et les deux launchers
n'en font plus qu'un. Tu n'as rien à télécharger : lance ton launcher (ou ton raccourci) comme d'habitude.

- Il se met à jour, puis se renomme tout seul en **OpenSmash Ultimate Launcher.bat** ; les raccourcis deviennent
  **Smash Ultimate (OpenSmash Ultimate)** et **OpenSmash Ultimate Launcher**.
- **Launcher WindowSmash** : ton dossier passe sur OpenSmash Ultimate et le jeu est recompilé (1 à 3 h, accepte la
  mise à jour). Ta sauvegarde, ton pseudo et tes réglages restent.
- **Launcher OpenSmash** : il propose d'installer OpenSmash Ultimate (il reprend tes fichiers du jeu et ta
  sauvegarde), puis de supprimer l'ancienne installation OpenSmash (une copie de sa sauvegarde est gardée). Si le
  disque manque de place, il propose de la supprimer avant.
- Le rollback est activé par défaut quand tu lances le jeu (raccourci ou **option 2**) : il n'y a plus d'option à part.

## Mises à jour

Automatiques : à chaque lancement, le launcher se met à jour tout seul (et redémarre s'il a changé). Si une
nouvelle version d'OpenSmash Ultimate est choisie pour le groupe, il propose de la recompiler avant de jouer : en
ligne, **tout le monde doit avoir exactement la même version** (le launcher reste sur cette version, pas forcément la
dernière).

## Le menu

| Choix | Ce qu'il fait |
| :--- | :--- |
| 1) Installer / mettre à jour | Installe tout, ou met une installation existante à la version du groupe et recompile. |
| 2) Lancer le jeu | Ouvre la fenêtre du jeu (réglages), puis le jeu en ligne, avec le rollback netcode par défaut (voir [Jouer en ligne](#jouer-en-ligne)). |
| 3) Diagnostic | Crée un rapport sans rien installer. |
| 4) Débloquer tous les personnages | Le launcher le fait déjà tout seul (après l'installation, au premier lancement quand tu fermes le jeu, puis avant chaque lancement) ; l'option le fait tout de suite, jeu fermé. |
| 5) Optimiser | Précompile les shaders (FPS stables) et met la latence d'affichage à 1. |
| 6) Ajouter mes DLC | Ajoute au jeu les DLC que tu as achetés, dumpés de ta Switch (dossier de fichiers `.nsp`/`.nsz` avec leur nom de dump, qui contient l'identifiant `01006A800016F...`). Un deuxième dossier s'ajoute à la liste. En ligne, ayez les mêmes DLC. |
| 7) Français / English | Le launcher est en anglais par défaut : **7** le passe en français (et **7** le remet en anglais). Le choix est gardé. |

Depuis la version du 4 novembre 2026 (kit 4.3), le menu a une seule option pour jouer : les numéros des options
suivantes ont baissé d'un (DLC = 6, langue = 7).

## Jouer en ligne

1. Lance le jeu avec le raccourci. La première fois, il demande ton pseudo en ligne.
2. Une fenêtre s'ouvre : version du jeu, affichage (fenêtre ou plein écran, taille), en ligne, manettes. Clique
   sur **Play**. (Case « Start the game directly » : le jeu démarre directement les fois suivantes ; garde Maj
   enfoncée pendant le lancement pour revoir la fenêtre.)
3. Si Windows demande l'autorisation pour `ssbu.exe`, coche **Réseaux privés et publics**.
4. Dans le jeu : **Local Wireless**. Un joueur crée une room, les autres la choisissent dans la liste.
   Aucun port à ouvrir, pas de VPN : tout passe par le lobby public `smash.recomps.wtf`.
5. Rooms entre amis seulement : dans la fenêtre du jeu, choisissez **Private lobby (a code)** et mettez **le même
   code** chez tout le monde. Hors ligne : **Offline**.
6. Encore en test : le mode **Online** du jeu. Menu principal, **Online**, **Smash**, **Quickplay** : il trouve un
   autre joueur qui cherche en même temps. Garde le fichier `netplay_id.txt` du dossier OpenSmash Ultimate : c'est
   ton compte (ne le donne à personne).

**Rollback** : activé par défaut. Les combats Quickplay et les combats à 2 dans une room Local Wireless se jouent en
rollback quand l'autre joueur l'a aussi (les deux jeux se mettent d'accord en 15 s au plus, sinon le combat se joue avec
le netcode d'origine du jeu). Les rooms à plus de 2 joueurs et les combats locaux se jouent comme d'habitude. Pour
jouer sans : **Échap** > **Online** > **Rollback netcode** sur **off** (compte au prochain lancement). Le rollback
demande un bon processeur : si les FPS baissent en ligne, essaie sans.

En jeu : **Échap** ouvre le menu des réglages, **F1** l'overlay (il doit afficher `Online`), **F11** le plein écran.

Clavier : flèches = stick, Z/X/C/V = A/B/X/Y, A/S = L/R, Q/W = ZL/ZR, Entrée = +.
Les manettes (Xbox, PlayStation, Switch Pro...) marchent directement.

N'utilise pas `Install WindowSmash.bat`, `Play SSBU.bat` ni `OpenSmash.exe` du dossier du jeu : ils le mettraient à
jour au-delà de la version du groupe. Le launcher et ses raccourcis suffisent.

## Si ça ne marche pas

Le launcher s'arrête avec un code (E10 à E99) et une explication, et écrit **`OpenSmash-Ultimate-setup-report.txt`**
sur ton Bureau. Envoie ce fichier tel quel : il ne contient ni clés ni fichiers du jeu.

## Pour les développeurs

- `OpenSmash Ultimate Launcher.bat` : l'amorce (Git, clone et mise à jour de ce dépôt, redémarrage, puis le kit).
  `WindowSmash Launcher.bat` et `OpenSmash Launcher.bat` en sont des copies identiques : les anciens launchers se
  mettent à jour depuis le fichier de leur nom, puis le kit les renomme (garder les trois identiques).
- `kit/ws_setup.ps1` : l'installateur (PowerShell 5.1, doit rester en UTF-8 avec BOM et CRLF), version figée
  `$WS_COMMIT` d'OpenSmash-Ultimate/OpenSmash-Ultimate.
- `kit/ws_setup.py` : la partie Python (lecture des fichiers du jeu, puis compilation par `tools/build_game.py`).
- `kit-opensmash/os_setup.ps1` : renvoie vers `kit/ws_setup.ps1` (pour les anciennes amorces OpenSmash).
