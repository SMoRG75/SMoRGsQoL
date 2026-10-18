# TODO

## Nye addon-funktioner — prioriteret plan

- [x] **1. Adventure Recap — implementeret**
  - Flytbart sessionsvindue med afsluttede quests, world quests, optjent reputation og registreret spilletid.
  - Gemmer den aktuelle og den foregående session pr. karakter; `/reload` fortsætter sessionen.
  - Implementeret i `SessionRecap.lua` og committet på `master` som `12047f8`.
  - Vinduet er gennemgået i Retail og WoW Forever; automatiske tests består. Fuld funktionel validering i begge klienter er fortsat et krav før release.

- [x] **2. Smart Reputation Memory — implementeret**
  - Én foretrukken faction pr. karakter. Auto-watch viser midlertidige reputation-gevinster og vender tilbage efter 10 sekunder uden nye gevinster.
  - Manuelle eller eksterne skift af den viste faction aflyser en ventende tilbagevenden. Valget og en eventuel ventende tilbagevenden overlever `/reload` og nyt login.
  - Valgfri og slået fra som standard; gem faction med `/sqol repfocus`, og aktivér **Return to preferred reputation** sammen med auto-watch.
  - Implementeret i `Reputation.lua` og committet som `d749a34` på `codex/reputation-memory`.
  - Automatiske tests består; funktionel validering i Retail og WoW Forever mangler før release.

- [ ] **3. Smart Quest Radar — næste nye funktion**
  - Gør questrelevante fjender og NPC'er lettere at genkende med diskrete indikatorer og questprogress på deres nameplates.
  - Start med en afgrænset prototype oven på den eksisterende nameplate-logik i `QuestProgress.lua`.
  - Undersøg først, hvilke quest- og objektivdata Retail og WoW Forever faktisk stiller til rådighed, inklusive under combat.
  - Brug tilgængelige, læsbare data; automatisk identifikation af alle relevante enheder kan ikke forudsættes.
  - Hold funktionen valgfri og visuelt enkel. Kontrollér flere samtidige questmål, combat, `/reload`, login og samspil med andre addons i begge klienter.

## Tidligere opgaver — afsluttet

- [x] **1. Fix placering af ilvl og speed i WoW Forever**
  - `SQOL.UpdatePlayerFrameIlvlAnchor()` i `PlayerStats.lua:218` er lavet til Retail-PlayerFrame; Forever har et andet layout.
  - Brug `SQOL.IsForever` (`Core.lua:15`) til at vælge egne anchors/offsets for ilvl og speed.

- [x] **2. Flot brugergrænseflade i addon-options**
  - Selvstændigt popup-vindue (`OptionsPopup.lua`) med sektioner, åbnes fra LDB-launcher (Bazooka), Addon Compartment, valgfri minimap-knap og `/sqol config`.
  - Venstreklik åbner popuppen, højreklik Blizzards Settings-side; den eksisterende Settings-side bevares og får samme sektionsoverskrifter.
  - Fælles option-liste (`SQOL.OptionSections` i `Options.lua`) bruges af både popup og Settings-side.
  - Skal virke både i Retail og Forever.

- [x] **3. Ikon når target er uden for rækkevidde**
  - Vis et ikon, når våben eller spell ikke kan nå den aktuelle NPC.
  - `RangeIndicator.lua`: ikon til højre for target-portrættet, når ingen offensive evner på de synlige action bars rækker (`C_ActionBar.IsActionInRange`, ikke secret i 12.x).
  - `IsItemInRange`/`CheckInteractDistance` er begrænset mod fjender i combat og bruges ikke.

- [x] **4. Farv det første tal i quest-tracker-objectives**
  - Farv `cur` i `cur/total` med `SQOL.GetProgressColor` (`QuestProgress.lua:6`), så 1/5 bliver rødt og 5/5 grønt.
  - Gælder også færdige objectives, som standard-UI'et ellers gråer/skjuler.

- [x] **5. Vis target i HUD-tooltip**
  - Tilføj en linje med unit'ens target ("Target: <navn>") i tooltip, klassefarvet, og "You" hvis det er dig.

- [x] **6. Centrér quest-tallene over nameplates og flyt dem lidt højere op**
  - "2/14" står i dag til venstre for midten og overlapper navnet (fx "Frostmane Troll Whelp").
  - Placeres i `SQOL_NameplateObjectives_GetText` (`QuestProgress.lua:1236`): `SetPoint("BOTTOM", anchor, "TOP", 0, 15)` mod health-bar-ankeret fra `SQOL_NameplateObjectives_GetAnchor`.
  - Centrér over hele nameplaten/health-baren, og læg teksten over navnet i stedet for oven i det.
