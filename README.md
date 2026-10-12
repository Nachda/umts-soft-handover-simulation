# Simulation du soft handover dans un réseau UMTS/WCDMA

> Mini-projet réalisé en **GSTR3** (3e année du cycle ingénieur, 5e année après le bac) à l'**ENSA Tétouan**, filière Télécommunications et Systèmes de Réseaux (GSTR) — année universitaire 2026-2027.

## Description

Un mobile (UE) traverse une ligne de 2 ou 3 Node B. Le script calcule le **RSCP** et l'**Ec/No** du CPICH de chaque cellule, applique l'algorithme de soft handover 3GPP (événements **1A / 1B / 1C / 1D**, avec **hystérésis** et **Time-To-Trigger**) et en déduit la cellule servante, l'Active Set, les zones de soft handover, le nombre de handovers et les **ping-pong**.

## Contexte

Dans un réseau UMTS/WCDMA, tous les Node B partagent la même fréquence : un mobile en déplacement peut donc être connecté à plusieurs cellules en même temps (*soft handover*). Ce projet simule ce mécanisme pour étudier l'effet des paramètres de handover (hystérésis, Time-To-Trigger, reporting range) sur le nombre de handovers, la taille de l'Active Set et les ping-pong.

## Compétences mobilisées

- Modélisation du canal radio : affaiblissement de parcours (espace libre, Okumura-Hata, COST231-Hata, log-distance) et shadowing log-normal corrélé
- Mesures radio WCDMA : RSCP, Ec/No, bruit thermique, interférence inter-cellules
- Mobilité et handover 3GPP : événements 1A/1B/1C/1D, hystérésis, Time-To-Trigger, Active Set
- Simulation et analyse de performance : tirages multiples (Monte-Carlo), étude paramétrique, indicateurs (overhead, ping-pong, taux de soft handover)
- Programmation MATLAB structurée : fonctions locales, code commenté et reproductible (graine aléatoire), visualisation de données
- Veille technique : lecture de spécifications 3GPP et d'articles de recherche

## Stack technique

| Outil | Usage |
|---|---|
| MATLAB (R2016b ou plus récent, sans toolbox) | Simulation, calculs et graphiques |
| Git / GitHub | Versionnement et publication |
| Spécifications 3GPP (TS 25.331, TS 25.133) | Référence pour l'algorithme de handover |

## Entrées et sorties

| Entrées (section 1 du script) | Sorties |
|---|---|
| Nombre de Node B et distance entre eux | RSCP et Ec/No de chaque cellule |
| Position de départ, décalage de la route, vitesse du mobile | Cellule servante au cours du temps |
| Puissance d'émission, part du CPICH, charge, gains, pertes | Active Set et sa taille |
| Modèle de propagation (espace libre, Okumura-Hata, COST231-Hata, log-distance) | Zones de soft handover, % de temps, overhead |
| Shadowing (écart-type, distance de décorrélation) | Nombre de handovers et de mises à jour de l'Active Set (1A, 1B, 1C) |
| Reporting range, hystérésis, **TTT**, taille max de l'Active Set | Ping-pong de la cellule servante et de l'Active Set |
| Seuils absolus de détectabilité, filtrage couche 3, fenêtre ping-pong | Temps passé sous le seuil Ec/No |

## Graphiques produits

1. RSCP = f(distance) : comparaison des modèles de propagation, puis RSCP de chaque Node B le long du trajet
2. Ec/No = f(distance), zones de soft handover grisées
3. Évolution de la cellule servante, handovers et ping-pong marqués
4. Évolution de l'Active Set et de sa taille, ajouts et retraits marqués
5. Étude paramétrique TTT × hystérésis (cartes de chaleur, moyenne sur plusieurs tirages)

## Utilisation

1. Ouvrir `soft_handover_umts.m` dans MATLAB (R2016b ou plus récent, aucune toolbox requise).
2. Modifier les paramètres de la section 1 (`P.n_nodeB = 2` ou `3`, `P.TTT_s`, `P.Hyst_dB`, `P.model`, …).
3. Lancer le script (F5). Le résumé chiffré s'affiche dans la console et les figures s'ouvrent.

## Algorithme

Pour chaque cellule *i*, avec *Q* l'Ec/No (ou le RSCP) éventuellement filtré, *Qbest* la meilleure cellule de l'Active Set, *R* la reporting range et *H* l'hystérésis. Chaque condition doit rester vraie pendant le TTT.

| Événement | Condition | Action |
|---|---|---|
| 1A | `Q_i > Qbest − (R − H)` | ajout à l'Active Set |
| 1B | `Q_i < Qbest − (R + H)` | retrait de l'Active Set |
| 1C | Active Set plein et `Q_i > Qworst + H` | remplacement de la pire cellule |
| 1D | `Q_candidate > Q_servante + H` | changement de cellule servante |

- Shadowing log-normal corrélé spatialement (processus AR(1) de Gudmundson).
- `Ec/No = RSCP / (somme des puissances reçues de toutes les cellules + bruit thermique)`.
- Ping-pong : retour à la cellule précédente en moins de `Tpp_s` secondes (5 s par défaut).

## Scénarios types

Valeurs indicatives, issues d'un portage Python de l'algorithme (moyenne de 10 tirages de shadowing, 3 km entre Node B, 50 km/h, reporting range 4 dB). Les nombres exacts varient avec la graine aléatoire.

| Scénario | σ shadowing | TTT | Hystérésis | 2 Node B | 3 Node B |
|---|---|---|---|---|---|
| Soft handover « propre » | 0 dB | 0,32 s | 2 dB | 1 handover, 0 ping-pong | 2 handovers, 0 ping-pong |
| Cas réaliste | 3 dB | 0,32 s | 2 dB | ≈ 3,6 handovers, ≈ 1 ping-pong | ≈ 6 handovers, ≈ 2 ping-pong |
| Ping-pong massif | 6 dB | 0 | 0 dB | ≈ 38 handovers, ≈ 33 ping-pong | ≈ 75 handovers, ≈ 62 ping-pong |
| Ping-pong supprimé | 6 dB | 1,28 s | 3 dB | ≈ 0 ping-pong | ≈ 1 ping-pong |

Dans le cas propre, la zone de soft handover occupe environ 13 % du trajet.

## Choix de modélisation et limites

- **Modèle de propagation** : COST231-Hata par défaut (valide de 1500 à 2000 MHz, légèrement extrapolé à 2100 MHz). Okumura-Hata n'est valide que jusqu'à 1500 MHz (avertissement affiché). Hata est défini pour des distances d'environ 1 km et plus ; la distance minimale est bornée à 20 m.
- Le **hard handover** n'est pas modélisé : la phase à deux cellules dure toujours au moins le TTT, donc tout changement de cellule passe par un soft handover.
- Les Node B sont alignés sur une droite, une seule porteuse, sans modélisation du softer handover ni de la liaison montante.
- Le code MATLAB n'a pas pu être exécuté lors de sa rédaction ; seule la logique a été validée par un portage Python. Merci de signaler tout bug via une issue.

## Références

- 3GPP TS 25.331 (RRC) et TS 25.133 (exigences de mesures), exemple d'algorithme de soft handover : [RP-030304](https://www.3gpp.org/ftp/tsg_ran/TSG_RAN/TSGR_20/Docs/PDF/RP-030304.pdf)
- Schinnenburg, Forkel, Haverkamp, *Realization and Optimization of Soft and Softer Handover in UMTS Networks*, EPMCC 2003
- Valenta, *Soft Handover Optimization in UMTS FDD Networks*, EEICT 2008
- COST 231, *Digital Mobile Radio: Towards Future Generation Systems*

## Auteur

**Nourouddine Nachda** — étudiant ingénieur, ENSA Tétouan (GSTR3).
Encadrant : *à compléter*

## Licence

MIT — voir [LICENSE](LICENSE).
