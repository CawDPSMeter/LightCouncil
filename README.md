# Light Council

Loot-Addon für **World of Warcraft Forever** (Interface 16001): Reservierungen direkt im Addon und Lootverteilung mit einem Council aus 3 oder 5 Personen für wichtige Items. Raider würfeln per Knopfdruck.

*English: in-addon soft reservations and loot distribution with a 3 or 5 member council for important items. Available in German, English, French, Spanish and Russian (`/lc lang en`).*

## Funktionen

- **Reservierungen im Addon:** Raider wählen ihre Items selbst (Standard: 2 pro Raid). Nach dem Speichern ist die Wahl gesperrt, Änderungen gehen nur per Antrag an den Council.
- **Gear-Sets:** Raider stellen sich Sets zusammen (z. B. je Biom) und legen ihre Prio-Reihenfolge fest. Das Addon erkennt, was schon vorhanden ist. Alle sehen die Sets der anderen, der Council sieht in der Abstimmung, welchen Platz das Item beim Spieler hat. Optional kann direkt aus dem Set reserviert werden.
- **Raidtage mit Erinnerung:** An euren Raidtagen erinnert das Addon beim Einloggen alle, die noch nicht reserviert haben.
- **Council-Abstimmung:** Bei markierten Council-Items stimmt der Council anonym ab: *Freigeben*, *Eingrenzen* oder *Aussetzen*. Score aus Anwesenheit, Parse und Engagement hilft bei der Entscheidung.
- **Würfeln per Knopf:** Raider mit dem Addon bekommen ein Loot-Fenster mit Würfel-Knopf (Main Spec / Off Spec). Ohne Addon läuft alles über `/roll` im Raidchat.
- **Automatische Vergabe:** Der Plündermeister gibt das Item direkt an den Gewinner, Ansage per Raidwarnung.
- **Loot-Historie:** Wer hat wann welches Item bekommen – wird zwischen allen abgeglichen, exportierbar als Tabelle oder für Discord.
- **Anwesenheit:** Wird bei jedem Boss-Kill erfasst und zwischen allen Council-Mitgliedern abgeglichen.
- **Item-Tooltips:** Council-Item, Prio und Reservierer erscheinen im Tooltip jedes Items.
- **Mehrsprachig:** Deutsch, Englisch, Französisch, Spanisch, Russisch.

Optionale Loot-Quellen: AtlasLoot (Classic/Forever) oder Naowh Forever.

## Installation

1. Den Ordner `LightCouncil` nach `World of Warcraft\_forever_\Interface\AddOns\` kopieren.
2. Spiel starten oder `/reload`.
3. Raidleitung: unter **Einstellungen** die Council-Mitglieder eintragen (Vor- und Nachname) und speichern.

## Befehle

| Befehl | Wirkung |
|---|---|
| `/lc` | Hauptfenster öffnen |
| `/lc loot` | Loot-Fenster für Raider öffnen/schließen |
| `/lc test [Itemlink]` | Council-Ablauf allein testen (nichts geht in den Raidchat) |
| `/lc check` | Zeigt, wer im Raid das Addon in welcher Version hat |
| `/lc lang <auto\|de\|en\|fr\|es\|ru>` | Sprache wechseln |
| `/lc tooltip` | Infos im Item-Tooltip ein-/ausschalten |
| `/lc anw` | Anwesenheit jetzt erfassen |
| `/lc log` | Letzte Entscheidungen im Chat |
| `/lc abbruch` | Laufende Abstimmung/Würfelrunde abbrechen |
| `/lc councilreset` | Gespeicherte Council-Liste vergessen und neu anfragen |
| `/lc hilfe` | Alle Befehle |

## Sicherheit

Daten anderer Spieler werden nur übernommen, wenn sie von der richtigen Stelle kommen: Reservierungen, Historie und Anwesenheit nur vom Council, Abstimmungen und Loot-Fenster nur vom Raidleiter oder Plündermeister. Bitte immer die neueste Version nutzen – `/lc check` zeigt veraltete Versionen im Raid.

## Entwicklung

- Alle sichtbaren Texte stehen im Code auf Deutsch als `L["…"]`. Die Übersetzungen liegen in `Locales/*.lua`.
- `perl tools/check_locales.pl` meldet fehlende oder fehlerhafte Übersetzungen.
- Die Versionsnummer steht nur in `LightCouncil.toc`.

## Lizenz

Die Schrift Inter steht unter der SIL Open Font License 1.1 (`Media/Fonts/FONT-LICENSE.txt`).
