use Test;
#use Test::More;
use strict;
use t::Foo;

my $foo = Regexp::Log::Foo->new();

ok( ref($foo) eq 'Regexp::Log::Foo' );

# check defaults
ok(  $foo->format eq '%d %c %b' );
my @capture = $foo->capture;
ok( @capture == 1 );
ok( $capture[0] eq 'c' );

# check the fields method
my @fields = sort $foo->fields;
my $i = 0;
for( @fields ) {
    ok( $_ eq (qw(a b c cn cs d))[$i++] );
}


BEGIN { plan tests => 10 }
