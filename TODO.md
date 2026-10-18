# TODO

## Nye addon-funktioner — prioriteret plan

- [x] **1. Adventure Recap — implementeret**
  - Flytbart sessionsvindue med afsluttede quests, world quests, optjent reputation og registreret spilletid.
  - Gemmer den aktuelle og den foregående session pr. karakter; `/reload` fortsætter sessionen.
  - Implementeret i `SessionRecap.lua` og committet på `master` som `12047f8`.
  - Vinduet er gennemgået i Retail og WoW Forever; automatiske tests består. Fuld funktionel validering i begge klienter er fortsat et krav før release.

- [x] **2. Smart Reputation Memory — implementeret, afprøvet i Retail**
  - Én foretrukken faction pr. karakter. Auto-watch viser midlertidige reputation-gevinster og vender tilbage efter 10 sekunder uden nye gevinster.
  - Manuelle eller eksterne skift af den viste faction aflyser en ventende tilbagevenden. Valget og en eventuel ventende tilbagevenden overlever `/reload` og nyt login.
  - Valgfri og slået fra som standard; gem faction med `/sqol repfocus`, og aktivér **Return to preferred reputation** sammen med auto-watch.
  - Implementeret i `Reputation.lua` og committet som `d749a34` på `codex/reputation-memory`.
  - Lokal fejlrettelse efter Retail-rapport: skjulte underpaneler måles med `IsVisible()`, og forsinkede faction-skift får en afgrænset bekræftelse. Regressionstests dækker begge fejl; brugeren har bekræftet, at rettelsen virker i Retail.
  - Automatiske tests består.
  - [x] Afprøvet i Retail: brugeren har bekræftet, at tilbagevenden til den foretrukne faction virker efter rettelsen (19. oktober 2026).
  - [ ] Valider Reputation Memory og rettelsen i WoW Forever før release.

- [x] **3. Smart Quest Radar — implementeret, afprøvet i Retail**
  - Quest-ikon og op til tre uafsluttede mål på én linje over relevante, synlige nameplates; yderligere mål vises som `+N`.
  - Selvstændigt modul i `QuestRadar.lua`, integreret med den eksisterende nameplate-visning og quest-cache i `QuestProgress.lua`.
  - Slået fra som standard; aktivér under **Quests → Smart Quest Radar** eller med `/sqol radar` (`qr`). Erstatter den gamle talvisning, mens radaren er aktiv, og bruger den eksisterende indstilling for progressfarver.
  - Bruger læsbare tooltip-afsnit, der matcher karakterens aktive quests. Færdige mål, gruppemedlemmers afsnit, tvetydige questtitler og utilgængelige data springes over. Ingen scanning efter enheder uden nameplates.
  - På klienter uden tooltip-linjetyper kræves et præcist match med karakterens egen uafsluttede objektivtekst. Dækningen afhænger af klientens data, også under combat.
  - Automatisk dækket af `tests/radar.lua`, den eksisterende integrationstest og sprogtesten. Implementeret lokalt på `codex/smart-quest-radar`; endnu ikke committet eller pushet.
  - [x] Afprøvet i Retail: brugeren har bekræftet, at funktionen er OK (18. oktober 2026).
  - [ ] Valider i WoW Forever: placering og læsbarhed, flere samtidige questmål, gruppespil, combat, `/reload`, login, samspil med andre addons, klientens tooltip-data og skift mellem radaren og den gamle talvisning.

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
