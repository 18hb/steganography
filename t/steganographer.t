use strict;
use warnings;
use Test::More tests => 8;

use Steganographer;

my @p = (0b000000110000000000000011, 0b000000110000000000000011); # (0x030003, 0x030003)
my $s = Steganographer->new(\@p);
$s->load("./source.png");

my @god;

@god = $s->_expand(0);
is_deeply(\@god, [0b000000000000000000000000, 0b000000000000000000000000]);

@god = $s->_expand(1);
is_deeply(\@god, [0b000000000000000000000000, 0b000000000000000000000001]);

@god = $s->_expand(2);
is_deeply(\@god, [0b000000000000000000000000, 0b000000000000000000000010]);

@god = $s->_expand(3);
is_deeply(\@god, [0b000000000000000000000000, 0b000000000000000000000011]);

@god = $s->_expand(4);
is_deeply(\@god, [0b000000000000000000000000, 0b000000010000000000000000]);

@god = $s->_expand(0x0F);
is_deeply(\@god, [0b000000000000000000000000, 0b000000110000000000000011]);

@god = $s->_expand(0x1F);
is_deeply(\@god, [0b000000000000000000000001, 0b000000110000000000000011]);

@god = $s->_expand(0xFF);
is_deeply(\@god, [0b000000110000000000000011, 0b000000110000000000000011]);
