# Changelog

## 0.16.1
- Fairness: Ein Item gilt im Set auch dann als „hat es“, wenn die Loot-Historie zeigt, dass der Spieler es bekommen hat (niemand kann sich durch falsche Angaben bedürftiger machen).
- Sets anderer Spieler zeigen ihren Stand; Sets älter als 14 Tage sind im Council-Fenster als „(alt)“ markiert.
- Leistung: „Habe ich das Item?“ wird zwischengespeichert; Set-Änderungen werden nur noch gemeldet, wenn sich wirklich etwas ändert.
- Versionsabfrage (`/lc check`) wird nur noch aus der eigenen Gruppe beantwortet, höchstens alle 30 Sekunden.
- Lange Sets werden nicht mehr mitten in einem Item abgeschnitten; „Umbenennen“ zeigt den bisherigen Namen.

## 0.16.0
- Neu: **Gear-Sets**. Raider stellen sich ein oder mehrere benannte Sets zusammen (z. B. je Biom) und bringen die Items in ihre Prio-Reihenfolge. Was man schon hat, erkennt das Addon selbst (angelegt, Taschen, Bank).
- Das aktive Set wird an alle verteilt; unter „Gear-Sets → Alle Sets“ sieht jeder den Stand der anderen.
- Council-Abstimmung zeigt in der neuen Spalte „Set“, auf welchem Platz das Item in der Prio des Spielers steht; Tooltips zeigen das ganze Set.
- „Meine Reservierung“: „+ Set“ bei jedem Item; optional „Aus Gear-Set übernehmen“ (Council schaltet das unter „Raidtage“ ein – Randoms ohne Set reservieren wie gewohnt).
- Item-Tooltips und Loot-Fenster zeigen, wer das Item im Set hat bzw. welchen Platz es in deinem Set hat.

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
