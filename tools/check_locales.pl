#!/usr/bin/perl
# Light Council – prüft die Übersetzungen.
#   perl tools/check_locales.pl        (im Addon-Ordner ausführen)
#
# Meldet:
#   FEHLT    – Text steht im Code als L["…"], aber nicht in einer Sprachdatei (erscheint dann auf Deutsch)
#   FORMAT   – Platzhalter (%d, %s), Farbcodes (|c…, |r), \n oder Randleerzeichen passen nicht zum Original
#   UNBENUTZT – steht in einer Sprachdatei, aber nicht als L["…"] im Code (nur Hinweis: Texte aus Tabellen
#               wie Wochentage oder Menüpunkte werden erst beim Anzeigen übersetzt und erscheinen hier auch)
# Rückgabewert 1, wenn etwas FEHLT oder das FORMAT nicht stimmt.
use strict; use warnings;

my @code = grep { !/^Locale/ } glob("*.lua");
my (%used, @order);
for my $f (@code) {
    open my $h, '<', $f or die "$f: $!";
    while (my $l = <$h>) {
        next if $l =~ /^\s*--/;
        while ($l =~ /\bL[\[\(]"((?:[^"\\]|\\.)*)"/g) { push @order, $1 unless $used{$1}++ }
    }
}

sub sig {
    my $s = shift;
    my @ph = ($s =~ /%[-0-9.]*[dsx%]/g);
    my ($lead) = $s =~ /^( *)/; my ($trail) = $s =~ /( *)$/;
    my $nl = () = $s =~ /\\n/g; my $r = () = $s =~ /\|r/g;
    return join '|', join('', @ph), length($lead), length($trail), $nl, $r, join(',', $s =~ /\|c[0-9a-fA-F]{8}/g);
}

my $bad = 0;
for my $lf (sort glob("Locales/*.lua")) {
    open my $h, '<', $lf or die "$lf: $!";
    my %t;
    while (my $l = <$h>) {
        $t{$1} = $2 if $l =~ /^\s*\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)",?\s*$/;
    }
    my ($missing, $format, $unused) = (0, 0, 0);
    for my $k (@order) {
        if (!exists $t{$k}) { print "$lf FEHLT: $k\n"; $missing++; next }
        if (sig($k) ne sig($t{$k})) { print "$lf FORMAT: $k  =>  $t{$k}\n"; $format++ }
    }
    for my $k (sort keys %t) { $unused++ unless $used{$k} }
    printf "%s: %d Einträge, %d fehlen, %d Formatfehler, %d nicht direkt im Code\n", $lf, scalar(keys %t), $missing, $format, $unused;
    $bad += $missing + $format;
}
exit($bad ? 1 : 0);
