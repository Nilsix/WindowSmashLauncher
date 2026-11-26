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
   Si ton PC a le SDK .NET 8 (ou plus récent), cet OpenSmash.exe est compilé chez toi, avec un onglet de plus :
   NILSIX TOOLS (voir plus bas).

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
l'OpenSmash.exe normal. Sans le SDK .NET, tu gardes l'OpenSmash.exe normal.

Pour jouer en ligne avec des mods, il faut exactement les mêmes des deux côtés :

1. Dans NILSIX TOOLS, clique sur **CRÉER LE FICHIER**. `Synchro mods - <ton nom>.bat` arrive sur ton Bureau, avec
   un code (par exemple `8809-8748`). Le journal liste aussi les conflits entre tes mods, et ceux qui ont une
   version plus récente sur GameBanana.
2. Envoie ce fichier à ton ami. Il ferme OpenSmash et double-clique dessus. Il n'a pas besoin de ce launcher :
   OpenSmash suffit. Si Windows bloque un fichier téléchargé : « Informations complémentaires », puis « Exécuter quand
   même ».
3. Le fichier installe tes mods depuis GameBanana, aux mêmes versions que les tiens. Il active ceux que tu as activés
   et désactive les autres, dans ton ordre. Il met les mêmes plugins, puis applique les mods.
4. À la fin, ton ami doit voir **SYNCHRO OK** et le même code que toi. Sinon, le fichier dit ce qui diffère.

Ses mods que tu n'as pas sont désactivés, jamais supprimés. Un de ses dossiers qui porte le nom d'un de tes mods mais
contient d'autres fichiers est renommé « (ancien) » et désactivé. Un mod qui ne vient pas de GameBanana ne peut pas
être téléchargé : le fichier le signale.

Quand OpenSmash se met à jour lui-même, il remet son OpenSmash.exe normal : l'onglet revient au lancement suivant par
ce launcher, qui le recompile (de 30 secondes à quelques minutes).

## Pour les développeurs

- `OpenSmash Ultimate Launcher.bat` : l'amorce (Git, clone et mise à jour de ce dépôt, redémarrage, puis le kit).
  `WindowSmash Launcher.bat` et `OpenSmash Launcher.bat` en sont des copies identiques : les anciens launchers se
  mettent à jour depuis le fichier de leur nom (garder les trois identiques).
- `kit/ws_setup.ps1` : le kit 5, qui passe la main à OpenSmash.exe (PowerShell 5.1, UTF-8 avec BOM et CRLF).
- `kit-opensmash/os_setup.ps1` : renvoie vers `kit/ws_setup.ps1` (pour les anciennes amorces OpenSmash).
- `kit/nilsix_launcher.ps1` : compile OpenSmash.exe avec la page NILSIX TOOLS, seulement quand les sources du dossier de
  jeu sont celles de la version publiée (`tools/source_version.txt`). Il ajoute 5 points d'accroche dans
  `OpenSmash.Launcher` ; si l'un d'eux a changé en amont, rien n'est compilé et l'OpenSmash.exe publié est mis à la
  place. `%LOCALAPPDATA%\WindowSmash-setup\nilsix-launcher\record.json` évite de recompiler à chaque lancement.
- `kit/nilsix/LauncherForm.Nilsix.cs` : la page NILSIX TOOLS, dessinée avec les mêmes fonctions que les autres pages.
- `kit/mods_sync.py` : `make` écrit le fichier .bat, qui contient ce script et la liste des mods. Chez l'ami, `sync`
  fait la synchro puis la vérifie (`check` vérifie seulement). Le code est calculé sur la liste de mods que le jeu
  échange en ligne (`runtime/net_relay.c`) ; la vérification compare aussi l'ordre des mods et les plugins.
