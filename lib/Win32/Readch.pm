package Win32::Readch;

use strict;
use warnings;

use Win32::Console;
use Win32::IPC qw(wait_any);

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT    = qw();
our @EXPORT_OK = qw(readch_block readch_noblock getstr_noecho);
our $VERSION   = '0.03';

my $CONS_INP = Win32::Console->new(STD_INPUT_HANDLE)
  or die "Error in Win32::Readch - Can't Win32::Console->new(STD_INPUT_HANDLE)";

my @Ch_Stack;

sub readch_noblock {
    while ($CONS_INP->GetEvents) {
        my @event = $CONS_INP->Input;

        my $code = defined($event[1])
                && defined($event[5])
                && $event[1] == 1 ? $event[5] + ($event[5] < 0 ? 256 : 0) : undef;

        if (defined $code) {
            push @Ch_Stack, chr($code);
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
