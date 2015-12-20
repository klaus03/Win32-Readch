package Win32::Readch;

use strict;
use warnings;

use Win32::Console;
use Win32::IPC qw(wait_any);
use Unicode::Normalize;
use Win32::TieRegistry; $Registry->Delimiter('/');

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT    = qw();
our @EXPORT_OK = qw(readch_block readch_noblock getstr_noecho inpline keybd cpage);

my $CONS_INP = Win32::Console->new(STD_INPUT_HANDLE)
  or die "Error in Win32::Readch - Can't Win32::Console->new(STD_INPUT_HANDLE)";

sub inpline {
    chomp(my $txt = qx!set /p TXT=& perl -e "print \$ENV{'TXT'}"!);
    $txt;
}

sub keybd {
    my $kb = $Registry->{'HKEY_CURRENT_USER/Keyboard Layout/Preload//1'} // '';
    $kb =~ s{\A 0+}''xms;
    $kb = '0' if $kb eq '';

    return $kb;
}

sub cpage {
    chomp(my $cp = qx{chcp});
    $cp =~ m{: \s* (\d+) \.? \s* \z}xms ? $1 : '0';
}

my @Ch_Stack;
my $Ch_Acc;

my $ZK_keybd = keybd;
my $ZK_cpage = cpage;

my %ZK_Shift;
my %ZK_TList;

%ZK_Shift = (
  29 => [ 'Ctrl' ],
  42 => [ 'Shift-Left' ],
  54 => [ 'Shift-Right' ],
  56 => [ 'Alt-Gr' ],
  58 => [ 'Shift-Lock' ],
  69 => [ 'Num-Lock' ],
  70 => [ 'Scroll-Lock' ],
  91 => [ 'Win-Left' ],
  92 => [ 'Win-Right' ],
  93 => [ 'Win-List' ],
);

#~ 224. 'à' => (\x{61}, \x{300})
#~ 225. 'á' => (\x{61}, \x{301})
#~ 226. 'â' => (\x{61}, \x{302})
#~ 227. 'ã' => (\x{61}, \x{303})
#~ 228. 'ä' => (\x{61}, \x{308})
#~ 229. 'å' => (\x{61}, \x{30a})

for my $code (192..255) {
    my $nfd = NFD(chr($code));

    if (length($nfd) == 2) {
        my $ch1 = substr($nfd, 0, 1);
        my $ch2 = substr($nfd, 1, 1);

        my $astr =
          $ch2 eq "\x{300}" ?  96 : # Accent Grave
          $ch2 eq "\x{301}" ? 180 : # Accent Aigue
          $ch2 eq "\x{302}" ?  94 : # Hat / Circonflex
          $ch2 eq "\x{303}" ? 126 : # Tilde
          $ch2 eq "\x{308}" ? 168 : # Umlaut / Trema
          $ch2 eq "\x{30a}" ? 186 : # Circle
          0;

        $ZK_TList{$astr, $ch1} = $code;
    }
}

my %ZK_Local;
my %ZK_Accent;
my %ZK_Letter;

if ($ZK_keybd eq '40c') { # French keyboard
    %ZK_Local = (
      ''  .$;.'41' => 178, # Power 2
      ''  .$;. '3' => 233, # e Accent Aigue
      ''  .$;. '8' => 232, # e Accent Grave
      ''  .$;.'10' => 231, # c Cedille
      ''  .$;.'11' => 224, # a Accent Grave
      ''  .$;.'40' => 249, # u Accent Grave
      'S' .$;.'12' => 186, # first circle
      'CG'.$;.'27' => 164, # second circle
      'S' .$;.'27' => 163, # Pound symbol
      'S' .$;.'43' => 181, # Greek symbol
      'S' .$;.'53' => 167, # Paragraph
    );

    %ZK_Accent = (
      ''  .$;.'26' =>  94, # Hat / Circonflex
      'S' .$;.'26' => 168, # Umlaut / Trema
      'CG'.$;. '8' =>  96, # Accent Grave
      'CG'.$;. '3' => 126, # Tilde
    );

    %ZK_Letter = (
      ''  .$;.'16' => 'a',
      'S' .$;.'16' => 'A',
      ''  .$;.'18' => 'e',
      'S' .$;.'18' => 'E',
      ''  .$;.'23' => 'i',
      'S' .$;.'23' => 'I',
      ''  .$;.'24' => 'o',
      'S' .$;.'24' => 'O',
      ''  .$;.'22' => 'u',
      'S' .$;.'22' => 'U',
      ''  .$;.'21' => 'y',
      'S' .$;.'21' => 'Y',
      ''  .$;.'49' => 'n',
      'S' .$;.'49' => 'N',
      ''  .$;.'57' => ' ',
    );
}

sub readch_noblock {
    while ($CONS_INP->GetEvents) {
        my @event = $CONS_INP->Input;

        my $ev1 = $event[1] // -1;

        if ($ev1 == 1) {
            my $ev4 = $event[4];
            my $ev5 = $event[5];
            my $ev6 = $event[6];

            $ev5 += 256 if $ev5 < 0;

            next if $ZK_Shift{$ev4};

            my $K_AltGr     = ($ev6 & (2 ** 0)) <=> 0;
            my $K_Alt       = ($ev6 & (2 ** 1)) <=> 0;
            my $K_CtlRight  = ($ev6 & (2 ** 2)) <=> 0;
            my $K_CtlLeft   = ($ev6 & (2 ** 3)) <=> 0;
            my $K_Shift     = ($ev6 & (2 ** 4)) <=> 0;
            my $K_NumLock   = ($ev6 & (2 ** 5)) <=> 0;
            my $K_Scroll    = ($ev6 & (2 ** 6)) <=> 0;
            my $K_ShiftLock = ($ev6 & (2 ** 7)) <=> 0;

            my $SKey =
              ($K_CtlRight || $K_CtlLeft   ? 'C' : '').
              ($K_Shift    || $K_ShiftLock ? 'S' : '').
              ($K_Alt                      ? 'A' : '').
              ($K_AltGr                    ? 'G' : '');

            my $acc = $ZK_Accent{$SKey, $ev4};

            if (defined $acc) {
                $Ch_Acc = $acc;
                next;
            }

            $ev5 ||= $ZK_Local{$SKey, $ev4} || 0;

            printf "%-6s (%3d, %3d, %3d)%s\n", "[$SKey]", $ev4, $ev5, $ev6, (defined($Ch_Acc) ? " -> '$Ch_Acc'" : '');

            if ($ev5 == 0) {
                if (defined $Ch_Acc) {
                    my $letter = $ZK_Letter{$SKey, $ev4};

                    if (defined $letter) {
                        if ($letter eq ' ') {
                            push @Ch_Stack, chr($Ch_Acc);
                        }
                        else {
                            my $ncode = $ZK_TList{$Ch_Acc, $letter};

                            if (defined $ncode) {
                                push @Ch_Stack, chr($ncode);
                            }
                        }
                    }
                }
            }
            else {
                push @Ch_Stack, chr($ev5);
            }

            $Ch_Acc = undef;
        }
    }

    shift @Ch_Stack;
}

sub readch_block {
    my $ch = readch_noblock;

    # the wait_any() command waits for key-down as well as for key-up events...
    # That means that for every keystroke we get two events: one for key-down and one for key-up.
    # The key-down event delivers the character in readch_noblock, no problem.
    # But the key-up event delivers undef. Therefore we have to skip the undef by
    # using a while (!defined $ch) {...

    while (!defined $ch) {
        # I want to sleep here until a key-down or key-up event is triggered...
        # How can I achieve this under Windows... ???
        # use Win32::IPC does the trick.

        # WaitForMultipleObjects([$CONS_INP]); # this works, but is deprecated.
        wait_any(@{[$CONS_INP]}); # this works and is not deprecated

        $ch = readch_noblock;
    }

    return $ch;
}

sub getstr_noecho {
    my ($prompt) = @_;

    my $password = '';

    local $| = 1;

    print $prompt;

    my $ascii = 0;

    while ($ascii != 13) {
        my $ch = readch_block;
        $ascii = ord($ch);

        if ($ascii == 8) { # Backspace was pressed, remove the last char from the password
            if (length($password) > 0) {
                chop($password);
                print "\b \b"; # move the cursor back by one, print a blank character, move the cursor back by one
            }
        }
        elsif ($ascii == 27) { # Escape was pressed, clear all input
            print "\b" x length($password), ' ' x length($password), "\b" x length($password);
            $password = '';
        }
        elsif ($ascii >= 32) { # a normal key was pressed
            $password = $password.chr($ascii);
            print '*';
        }
    }
    print "\n";

    return $password;
}

1;

__END__

=head1 NAME

Win32::Readch - Read individual characters from the keyboard using Win32::Console

=head1 SYNOPSIS

    use Win32::Readch qw(readch_block getstr_noecho);

    local $| = 1;

    print 'Press a single keystroke: ';
    my $ch1 = readch_block;
    print "Character '$ch1' has been pressed\n\n";

    my $password = getstr_noecho('Please enter a password: ');
    print "Your password is '$password'\n";

=head1 AUTHOR

Klaus Eichner <klaus03@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Klaus Eichner

All rights reserved. This program is free software; you can redistribute
it and/or modify it under the terms of the artistic license 2.0,
see http://www.opensource.org/licenses/artistic-license-2.0.php

=cut
