# Buckshot Roulette — Local Splitscreen

Mod pour **Buckshot Roulette** (Steam, Windows) qui ajoute un mode **multijoueur local en écran partagé** : de 2 à 4 joueurs sur un seul PC, chacun avec sa propre vue.

Le mod ne réécrit pas le jeu : il fait tourner le **mode multijoueur officiel**, une copie par joueur, reliées entre elles comme si elles étaient en ligne. On retrouve donc exactement la même table, les mêmes objets, les mêmes règles et le même écran de résultats qu'en partie en ligne.

| | |
|---|---|
| Version du jeu | v2.2.0.6 (Steam, Windows) |
| Joueurs | 2 à 4 : un au clavier et à la souris, les autres à la manette |
| Fichiers du jeu modifiés | aucun |

---

## Installation

1. Fermez le jeu.
2. Double-cliquez sur **`Install.bat`**.
   Le jeu est trouvé automatiquement grâce aux bibliothèques Steam. S'il n'est pas trouvé, l'installeur demande son dossier, que vous pouvez aussi donner directement :
   ```
   Install.bat "D:\SteamLibrary\steamapps\common\Buckshot Roulette\Buckshot Roulette_windows"
   ```
3. Lancez le jeu normalement depuis Steam. **LOCAL SPLITSCREEN** apparaît dans le menu principal, sous MULTIPLAYER.

Ce que fait l'installeur :
- il copie `mod\loader.gd` et `mod\splitscreen.pck` dans `<dossier du jeu>\splitscreen_mod\` ;
- il ajoute une ligne `SplitMod=...` dans `<dossier du jeu>\override.cfg`. Le fichier est créé s'il n'existe pas ; s'il existe, il est complété et l'original est sauvegardé dans `override.cfg.before-splitscreen`.

Si Windows refuse l'écriture dans le dossier du jeu, faites un clic droit sur `Install.bat` puis « Exécuter en tant qu'administrateur ».

## Désinstallation

Double-cliquez sur **`Uninstall.bat`** (même argument optionnel que l'installeur). Il :
- retire la ligne du mod dans `override.cfg`, et supprime ce fichier s'il ne contenait que le mod ;
- supprime `splitscreen_mod\` et la sauvegarde `override.cfg.before-splitscreen`.

Le dossier du jeu revient exactement à son état d'origine.

---

## Utilisation

### Lancer une partie

1. Dans le menu principal, choisissez **LOCAL SPLITSCREEN**.
2. Chaque joueur rejoint avec son propre périphérique. Le premier inscrit est le joueur 1, l'hôte de la partie.
3. Réglez le nombre de manches et l'intro, puis choisissez **START**. Il faut au moins 2 joueurs.

### Contrôles du lobby

| Action | Clavier / souris | Manette |
|---|---|---|
| Rejoindre | Entrée, Espace ou clic gauche | A |
| Quitter le lobby | Retour arrière | B |
| Changer de ligne | Flèches haut / bas | Croix haut / bas ou stick gauche |
| Changer une valeur | Flèches gauche / droite, ou clic sur la ligne | Croix gauche / droite ou stick gauche |
| Valider | Entrée ou clic | A |
| Lancer la partie | Ligne START | Ligne START ou bouton Start |
| Retour au menu principal | Échap ou ligne BACK | Ligne BACK |

Il n'y a qu'un seul joueur clavier et souris ; chaque autre joueur utilise une manette. Si une manette est débranchée dans le lobby, son joueur est retiré.

### Réglages

- **Manches** : 1, 2 ou 3.
- **Passer l'intro** : démarre directement à la table, sans la cinématique d'arrivée.
- Si vous avez personnalisé une partie dans le lobby multijoueur en ligne pendant la même session (objets, santé, cartouches), ces réglages sont repris.

### En partie

- **Disposition** : à 2 joueurs, les vues sont côte à côte et le nom et le périphérique de chaque joueur restent affichés au-dessus de sa vue. À 3 ou 4 joueurs, les vues sont en grille 2 × 2 et ces informations s'affichent quelques secondes en haut de chaque vue.
- **Contrôles** : ce sont ceux du jeu.
  - Clavier et souris : clic pour interagir, clic droit maintenu pour regarder autour, Échap pour le menu pause. Le curseur reste dans la vue de son joueur.
  - Manette : croix directionnelle pour choisir, A pour valider, gâchette gauche pour regarder autour, Start pour le menu pause.
- **Pause** : chaque joueur a son propre menu pause. « Disconnect » arrête la partie pour tout le monde et ramène au lobby écran partagé.
- **Son** : on entend la partie depuis la place du joueur 1.
- **Manette débranchée** : la vue du joueur l'indique ; il reprend la partie dès que la manette est rebranchée.
- **Fin de partie** : après l'écran des résultats, tout le monde revient au lobby écran partagé, prêt pour une revanche.

---

## Fonctionnement technique

### Vue d'ensemble

```
 Fenêtre du jeu
 ┌──────────────────────────────┬──────────────────────────────┐
 │ Vue joueur 1  (960 × 540)    │ Vue joueur 2  (960 × 540)    │
 │ SubViewport + monde 3D       │ SubViewport + monde 3D       │
 │   └ mp_main  → HÔTE          │   └ mp_main  → CLIENT        │
 └──────────────┬───────────────┴──────────────┬───────────────┘
                └─── bus de paquets en mémoire ┘   (remplace Steam P2P)

 clavier + souris ──► vue du joueur clavier      manette n ──► vue de son joueur
```

### Le point de départ : le multijoueur du jeu

Buckshot Roulette est fait avec **Godot 4.1.1**. Ses scripts GDScript sont stockés dans un pack (`.pck`) intégré à `Buckshot Roulette.exe`.

Le mode multijoueur (`res://multiplayer/`) suppose **un joueur local par instance du jeu** :
- chaque instance crée les sièges de tous les joueurs autour de la table, mais ne contrôle que le sien ;
- l'instance de l'hôte valide chaque action (prendre le fusil, tirer, utiliser un objet) puis diffuse le résultat à tout le monde ;
- les instances communiquent par paquets Steam P2P.

Le mod recrée cette situation, mais dans un seul processus.

### Chargement du mod

1. Au démarrage, Godot lit `override.cfg` dans le dossier de l'exécutable. Le mod y déclare l'autoload `SplitMod`, qui pointe vers `splitscreen_mod/loader.gd`.
2. `loader.gd` s'exécute avant le chargement du menu principal. Il calcule le MD5 des 29 scripts du jeu que le mod remplace et le compare à ceux de la v2.2.0.6.
3. S'ils correspondent, il monte `splitscreen.pck` avec `ProjectSettings.load_resource_pack(..., replace_files = true)`. Les scripts du pack prennent alors la place des originaux, et les scènes du jeu les utilisent sans être modifiées.
4. S'ils ne correspondent pas (mise à jour du jeu), il ne charge rien : le jeu tourne normalement, sans l'entrée LOCAL SPLITSCREEN.

### Une copie du match par joueur

Au lancement d'une partie, la scène de session crée, pour chaque joueur :
- un `SubViewport` de **960 × 540**, la résolution de rendu d'origine du jeu, avec `own_world_3d` : rendu, physique, caméra et environnement sont séparés ;
- une copie complète de la scène multijoueur `mp_main`, chargée **sans cache** (`CACHE_MODE_IGNORE`), pour que chaque copie possède ses propres meshes, matériaux et animations.

Les ressources externes que le match modifie en cours de partie (l'`Environment` pour la saturation à la mort et le flash du défibrillateur, l'écran du brouilleur, l'écran du téléphone) sont dupliquées pour chaque copie. Ainsi, rien de ce qui arrive sur l'écran d'un joueur ne déteint sur celui d'un autre.

La copie du joueur 1 est l'**hôte**, les autres sont des **clients**, exactement comme en ligne.

### Le réseau remplacé par un bus en mémoire

- `PacketManager.send_p2p_packet()` appelle `SplitMod.send_packet()`. Le paquet est sérialisé (`var_to_bytes`) puis déposé dans la file de chaque destinataire : tous les autres joueurs pour la cible `0`, sinon le joueur visé.
- Chaque copie lit **un paquet par image**, comme le jeu le fait avec `Steam.readP2PPacket()`, avec les mêmes contrôles : un client n'accepte que les paquets de l'hôte.
- Tout le reste est le code d'origine : attente des joueurs, création des sièges, manches, distribution des objets, validation des actions par l'hôte et statistiques de fin de partie.

### Ce qui était global devient propre à chaque joueur

Dans un seul processus, les singletons du jeu sont partagés par toutes les copies. Les scripts du match sont donc modifiés pour demander à `SplitMod` les valeurs qui doivent dépendre du joueur :

| Code d'origine | Remplacé par | Effet en écran partagé |
|---|---|---|
| `GlobalSteam.STEAM_ID` | `SplitMod.sid(self)` | Identifiant du joueur local de cette copie |
| `get_node("/root/mp_main/...")` | `SplitMod.mp_root(self).get_node(...)` | La scène `mp_main` de cette copie |
| `Input.set_mouse_mode`, `Input.set_custom_mouse_cursor` | `SplitMod.set_mouse_mode`, `SplitMod.set_custom_mouse_cursor` | Seule la copie du joueur clavier et souris pilote le curseur |
| `AudioServer.set_bus_volume_db`, `AudioServer.get_bus_effect` | `SplitMod.set_bus_volume_db`, `SplitMod.get_bus_effect` | Seule la copie du joueur 1 règle volumes et filtre passe-bas |
| `Steam.getFriendPersonaName`, `Steam.getPlayerAvatar` | `SplitMod.persona_name`, `SplitMod.get_player_avatar` | Noms « PLAYER 1 » à « PLAYER 4 » |
| `GlobalVariables.cursor_state_after_toggle` | `SplitMod.gv(self).cursor_state_after_toggle` | État du curseur propre à chaque joueur |
| `change_scene_to_file(mp_lobby)` | `SplitMod.change_scene(...)` | Fin de partie : retour au lobby écran partagé |

`SplitMod` retrouve la copie d'un nœud en remontant jusqu'au `SubViewport` qui le contient. Pendant une partie en écran partagé, il ignore aussi les rappels de lobby Steam (invitations, changements de membres), qui sinon écraseraient la liste des joueurs.

**Hors écran partagé, chaque appel renvoie exactement la valeur d'origine** : le multijoueur en ligne utilise les mêmes scripts sans changement de comportement.

Ces modifications sont appliquées par `tools/build.js` sous forme de remplacements exacts, dont le nombre d'occurrences est vérifié. Si le code du jeu change, la compilation s'arrête et indique le fichier en cause, au lieu de produire un mod cassé.

### Entrées

Toutes les entrées arrivent à la fenêtre principale. La scène de session les intercepte (`_input`), les marque comme traitées, puis les transmet au `SubViewport` du bon joueur avec `push_input` :
- clavier et souris vers le joueur clavier et souris (le clavier va au joueur 1 s'il n'y en a pas) ;
- chaque manette vers le joueur qui l'a inscrite.

Pour la souris :
- la position est convertie dans les coordonnées 960 × 540 de la vue du joueur, et le curseur est maintenu dans cette vue ;
- le mouvement relatif, utilisé pour regarder autour de soi, est mis à la même échelle que dans le jeu d'origine, pour garder la même sensibilité.

Chaque `SubViewport` garde son propre focus d'interface : les manettes naviguent dans les invites du jeu indépendamment les unes des autres.

### Image et son

- Pendant la partie, la fenêtre passe en résolution native (`content_scale_mode = DISABLED`). Chaque vue est rendue en 960 × 540, puis affichée à l'échelle avec des bandes noires si besoin. Les réglages de rendu (anticrénelage, ombres, filtrage) sont copiés de la fenêtre du jeu.
- Toutes les copies jouent les mêmes événements au même moment. Seul le `SubViewport` du joueur 1 a donc ses écouteurs audio 2D et 3D actifs, ce qui évite d'entendre chaque son en double.

### Menu et lobby

- `MenuManager.gd` ajoute l'entrée LOCAL SPLITSCREEN en dupliquant le bouton MULTIPLAYER. Elle a ainsi la même police, les mêmes sons, le même survol et la même navigation à la manette ; les boutons suivants sont décalés d'une ligne.
- Le lobby est construit par code avec les polices, sons et musique du jeu. Il gère l'inscription par périphérique et les réglages.
- En fin de partie, la session restaure tout ce qu'elle avait changé : identifiants et membres Steam, personnalisation du match, volumes et filtre audio, mode d'affichage, curseur. Elle revient ensuite au lobby.

---

## Après une mise à jour du jeu

Si une mise à jour modifie l'un des scripts remplacés, le mod se désactive tout seul au lancement. Le jeu reste jouable, sans l'entrée LOCAL SPLITSCREEN. Pour le remettre en service, recompilez le mod (voir [Développement](#développement)) puis relancez `Install.bat`.

## État du projet

Vérifié dans une copie isolée du jeu, à 2 joueurs (souris pour le joueur 1, manette simulée pour le joueur 2) :
- l'entrée du menu principal, sa navigation à la manette et le passage au lobby ;
- le lobby : inscription, réglages et retour au menu ;
- le démarrage de la partie et la synchronisation des vues ;
- la distribution d'objets, la prise du fusil, les tirs, les dégâts et le passage des tours ;
- l'installation et la désinstallation, avec et sans `override.cfg` existant.

Pas encore vérifié :
- une partie complète jusqu'à l'écran des résultats ;
- 3 et 4 joueurs ;
- de vraies manettes ;
- le multijoueur en ligne avec le mod installé.

---

## Développement

### Compiler le mod

Il faut **Node.js 18** ou plus récent.

```
node tools/build.js ["chemin\vers\Buckshot Roulette.exe"]
```

Sans argument, le jeu est cherché à son emplacement Steam par défaut. Le script :
1. lit les scripts originaux directement dans le pack intégré à l'exe et les place dans `build\original` ;
2. applique les modifications, en vérifiant le nombre exact d'occurrences de chacune ;
3. ajoute les fichiers de `src\pack\` ;
4. écrit `mod\splitscreen.pck`, ainsi que `mod\loader.gd` avec les MD5 des scripts originaux remplacés.

Aucun fichier du jeu n'est stocké dans le dépôt : `build\` est ignoré par Git.

### Structure du dépôt

| Chemin | Rôle |
|---|---|
| `Install.bat`, `Uninstall.bat` | Lanceurs de l'installeur et du désinstalleur |
| `installer\` | Scripts PowerShell : recherche du jeu, copie des fichiers, gestion de `override.cfg` |
| `mod\` | Le mod compilé, c'est-à-dire ce qui est installé dans le jeu |
| `src\loader.gd` | Autoload `SplitMod` : vérification de version, chargement du pack, contexte par joueur, bus de paquets |
| `src\menu_additions.gd` | Entrée LOCAL SPLITSCREEN, ajoutée à la fin de `MenuManager.gd` |
| `src\pack\mods\splitscreen\split_lobby.*` | Lobby : inscription des joueurs et réglages |
| `src\pack\mods\splitscreen\split_session.*` | Partie : vues, chargement des copies du match, routage des entrées |
| `tools\build.js` | Modifications des scripts du jeu et compilation du mod |
| `tools\pck.js`, `tools\mkpck.js` | Lecture et écriture des packs Godot 4.1 (format PCK v2) |
| `tools\mp_main_scripts.txt` | Liste des scripts utilisés par la scène multijoueur |
| `tools\deps.js`, `tools\nodes.js` | Analyse des scènes du jeu, une fois converties en texte |
| `tools\godot\` | Scripts exécutés par le moteur du jeu : conversion des scènes, vérification de compilation, test automatique |

### Tester sans toucher au jeu installé

1. Copiez `Buckshot Roulette.exe` et `steam_api64.dll` dans un dossier de test.
2. Lancez `Install.bat "<dossier de test>"`.
3. Ajoutez au `override.cfg` de ce dossier :
   ```
   [application]
   config/use_custom_user_dir=true
   config/custom_user_dir_name="BuckshotSplitTest"
   ```
   Sauvegardes et journaux iront dans `%APPDATA%\BuckshotSplitTest`, séparés de ceux du jeu.
4. Pour le test automatique, ajoutez sous `[autoload]` :
   ```
   SplitTest="*<chemin du dépôt>/tools/godot/split_test.gd"
   ```

Lancements utiles depuis Git Bash (journal dans `%APPDATA%\BuckshotSplitTest\logs\godot.log`) :

| Commande | Effet |
|---|---|
| `SPLIT_TEST_MODE=menu "Buckshot Roulette.exe" --headless` | Vérifie l'entrée du menu et le lobby, sans fenêtre |
| `SPLIT_TEST_MODE=session "Buckshot Roulette.exe" --windowed` | Joue une partie à 2 joueurs avec des entrées simulées (souris et manette) |
| `CHECK_LIST=<liste.txt> "Buckshot Roulette.exe" --headless --script <chemin absolu>/tools/godot/compile_check.gd` | Compile dans le moteur du jeu les scripts listés (un chemin `res://` par ligne) |

---

## Note

`mod\splitscreen.pck` contient des copies modifiées de scripts du jeu, qui restent la propriété de leurs auteurs. Ce dépôt est destiné à un usage privé : ne redistribuez pas le mod sans leur accord.
