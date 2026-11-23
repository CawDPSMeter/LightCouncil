# Changelog

## 0.15.0
- Gelöschte Einträge der Loot-Historie werden abgeglichen und kommen nicht mehr zurück.
- Versionsprüfung: Hinweis auf neuere Versionen, `/lc check` zeigt alle Versionen im Raid.
- Item-Tooltips zeigen Council-Item, Prio und Reservierer (`/lc tooltip` zum Abschalten).
- Sprachmenü schließt bei Klick daneben.
- Versionsnummer nur noch in der `.toc`.
- README, CHANGELOG und Prüfskript für Übersetzungen; ungenutzte Bilder entfernt.
- `UI_Main.lua` in mehrere Dateien aufgeteilt.

## 0.14.1
- Sicherheit: Raider können die Reservierungsrunde nicht mehr hochsetzen (vorher konnte jeder alle Reservierungen löschen).
- Abstimmungen und Raider-Fenster nur noch von Raidleiter oder Plündermeister; Lootliste nur vom Ersteller änderbar.
- Abgleich-Anfragen gedrosselt, Raid-Schlüssel begrenzt, empfangene Texte entschärft.

## 0.14.0
- Mehrsprachig: Deutsch, Englisch, Französisch, Spanisch, Russisch; Sprachwahl in den Einstellungen und per `/lc lang`.

## 0.13.0
- Anwesenheit wird zwischen allen Council-Mitgliedern abgeglichen.
- Erste Council-Liste nur von Raidleitung, Gildenleitung oder zwei Council-Mitgliedern; `/lc councilreset`.
- Parse/Engagement nur per Flüstern an Council und Raidleiter.
- Vergaben nur von Council oder Plündermeister in die Loot-Historie.
- Texte werden UTF-8-sicher gekürzt.

## 0.12.0
- Einstellbare Raidtage mit Erinnerung zum Reservieren beim Einloggen.
- Loot-Historie mit Abgleich und Export, automatische Vergabe, Main/Off-Spec-Würfeln.
