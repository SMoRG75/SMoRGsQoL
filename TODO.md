# TODO

- [ ] **1. Fix placering af ilvl og speed i WoW Forever**
  - `SQOL.UpdatePlayerFrameIlvlAnchor()` i `PlayerStats.lua:218` er lavet til Retail-PlayerFrame; Forever har et andet layout.
  - Brug `SQOL.IsForever` (`Core.lua:15`) til at vælge egne anchors/offsets for ilvl og speed.

- [ ] **2. Flot brugergrænseflade i addon-options**
  - `Options.lua` bruger i dag kun `Settings.RegisterVerticalLayoutCategory` med checkboxes/dropdowns.
  - Grupper indstillingerne i sektioner (Quests, Stats, Reputation, Countdowns, Visuelt) med overskrifter, beskrivelser og evt. logo.
  - Skal virke både i Retail og Forever.

- [ ] **3. Ikon når target er uden for rækkevidde**
  - Vis et ikon, når våben eller spell ikke kan nå den aktuelle NPC.
  - Undersøg hvilke range-API'er der stadig må bruges i 12.x (`C_Spell.IsSpellInRange`, `IsItemInRange`, `CheckInteractDistance`) — nogle er begrænset i combat.
  - Afgør: hvilken spell tjekkes (auto-attack/klassens standardspell eller valgfri?) og hvor ikonet placeres.

- [ ] **4. Farv det første tal i quest-tracker-objectives**
  - Farv `cur` i `cur/total` med `SQOL.GetProgressColor` (`QuestProgress.lua:6`), så 1/5 bliver rødt og 5/5 grønt.
  - Gælder også færdige objectives, som standard-UI'et ellers gråer/skjuler.

- [ ] **5. Vis target i HUD-tooltip**
  - Tilføj en linje med unit'ens target ("Target: <navn>") i tooltip, klassefarvet, og "You" hvis det er dig.
