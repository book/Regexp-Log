use Test::More;
use strict;
use t::Foo;

my $foo = Regexp::Log::Foo->new();

ok( ref($foo) eq 'Regexp::Log::Foo' );

# check defaults
ok(  $foo->format eq '%d %c %b', "Check default format" );
my @capture = $foo->capture;
ok( @capture == 1, "Check default capture" );
ok( $capture[0] eq 'c', "Check default captured field" );

# check the fields method
my @fields = sort $foo->fields;
my $i = 0;
for( qw(a b c cn cs d) ) {
    ok( $fields[$i++] eq $_, "Check all fields are captured: $_" );
}


BEGIN { plan tests => 10 }
