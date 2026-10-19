# WindowSmash Launcher

Un seul fichier pour installer, mettre à jour et lancer **WindowSmash** : Super Smash Bros. Ultimate en version
PC native (une recompilation du jeu Switch, projet [SNO2207/WindowSmash](https://github.com/SNO2207/WindowSmash)),
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
  - la mise à jour **13.0.4** (`.nsp`) ;
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

## Le menu

| Choix | Ce qu'il fait |
| :--- | :--- |
| 1) Installer / reprendre | Installe tout, ou met à jour une installation existante. |
| 2) Lancer le jeu | Lance le jeu en ligne. |
| 3) Diagnostic | Crée un rapport sans rien installer. |
| 4) Débloquer tous les personnages | Après avoir lancé le jeu une fois puis l'avoir fermé. |
| 5) Optimiser | Précompile les shaders (FPS stables) et met la latence d'affichage à 1. |

## Jouer en ligne

1. Lance le jeu avec le raccourci. La première fois, il demande ton pseudo en ligne.
2. Si Windows demande l'autorisation pour `ssbu.exe`, coche **Réseaux privés et publics**.
3. Dans le jeu : **Local Wireless**. Un joueur crée une room, les autres la choisissent dans la liste.
   Aucun port à ouvrir, pas de VPN : tout passe par le lobby public `smash.recomps.wtf`.
4. Rooms entre amis seulement : dans le dossier WindowSmash, ouvrez `online_server.txt` et ajoutez **le même
   code** après l'adresse, chez tout le monde (exemple : `smash.recomps.wtf:39420 moncode`).

Touche **F1** en jeu : l'overlay doit afficher `Online`. **F11** : plein écran.

Clavier : flèches = stick, Z/X/C/V = A/B/X/Y, A/S = L/R, Q/W = ZL/ZR, Entrée = +.
Les manettes (Xbox, PlayStation, Switch Pro...) marchent directement.

## Si ça ne marche pas

Le launcher s'arrête avec un code (E10 à E99) et une explication, et écrit **`WindowSmash-setup-rapport.txt`**
sur ton Bureau. Envoie ce fichier tel quel : il ne contient ni clés ni fichiers du jeu.

## Pour les développeurs

- `WindowSmash Launcher.bat` : l'amorce (Git, clone et mise à jour de ce dépôt, redémarrage, puis le kit).
- `kit/ws_setup.ps1` : l'installateur (PowerShell 5.1, doit rester en UTF-8 avec BOM).
- `kit/ws_setup.py` : la partie Python (lecture des fichiers du jeu, correctifs pour la 13.0.4).
- `memory.md` : tout le contexte technique (pour une session Claude Code ou un développeur).
