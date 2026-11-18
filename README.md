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

La première fois, OpenSmash propose une mise à jour : accepte-la. Il met le jeu à jour et le recompile (de quelques
minutes à une heure). Ensuite, ouvre ce launcher ou OpenSmash.exe, comme tu préfères.

Nouveau joueur ? Le plus simple est de télécharger directement
[OpenSmash.exe](https://github.com/OpenSmash-Ultimate/OpenSmash-Ultimate/releases/latest/download/OpenSmash.exe) :
voir le [guide d'installation](https://github.com/OpenSmash-Ultimate/OpenSmash-Ultimate/blob/main/docs/INSTALL.md).
Il te faut ton jeu en 13.0.5, ton `prod.keys`, et environ 60 Go libres.

## Le double boot

Au lancement, le launcher demande quel jeu ouvrir :

- **1) OpenSmash Ultimate** (choix par défaut) : il ouvre la fenêtre d'OpenSmash.exe, comme décrit plus haut.
- **2) OpenSmash** (ssbu-recomp, l'autre jeu) : il ouvre le menu de ce launcher pour ssbu-recomp (installer, jouer,
  rollback, diagnostic, DLC, déblocage des personnages, mode PC peu puissant). `0` revient au choix du jeu.

Le raccourci « Smash Ultimate (OpenSmash) » lance directement ssbu-recomp.

## Pour les développeurs

- `OpenSmash Ultimate Launcher.bat` : l'amorce (Git, clone et mise à jour de ce dépôt, redémarrage, puis le kit).
  `WindowSmash Launcher.bat` et `OpenSmash Launcher.bat` en sont des copies identiques : les anciens launchers se
  mettent à jour depuis le fichier de leur nom (garder les trois identiques).
- `kit/ws_setup.ps1` : le kit 5, qui demande le jeu, puis passe la main à OpenSmash.exe ou à `kit-opensmash/os_kit.ps1`
  (PowerShell 5.1, UTF-8 avec BOM et CRLF).
- `kit-opensmash/os_kit.ps1` : le menu de ssbu-recomp (choix 2 et modes `os-*`), épinglé sur son dernier commit.
- `kit-opensmash/os_setup.ps1` : renvoie vers `kit/ws_setup.ps1` (pour les anciennes amorces OpenSmash).
