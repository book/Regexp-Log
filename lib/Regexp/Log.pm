package Regexp::Log;

use strict;
use Carp;
use vars qw( $VERSION );

$VERSION = 0.01;

=head1 NAME

Regexp::Log - A regexp builder for munging log files

=head1 SYNOPSIS

    my $foo = Regexp::Log::Foo->new(
        format  => 'custom %g %e %a %w/%s %b %m %i %u %H/%d %c',
        capture => [qw( host code )],
    );

    # the format() and capture() methods can be used to set or get
    $foo->format('custom %g %e %a %w/%s %b %m %i %u %H/%d %c');
    $foo->capture(qw( host code ));

    # this is necessary to know in which order
    # we will receive the captured fields from the regex
    my @fields = $foo->capture;

    # the all-powerful capturing regex :-)
    my $re = $foo->regex;

    while (<>) {
        my %data;
        @data{@fields} = /$re/;

        # now do something with the fields
    }

=head1 DESCRIPTION

Regexp::Log is a base class for a variety of 

=head1 METHODS

The following methods are available:

=over 4

=item new( %args )

Return a new Regexp::Log::BlueCoat object. A list of key-value pairs can
be given to the constructor.

The arguments are:

 format  - the format of the log line
 capture - the name of the fields to capture with the regex
           (given as an array ref)

=cut

sub new {
    my $class = shift;
    return bless {
        format  => '',
        capture => [],
        @_
    }, $class;
}

=item format( $formatstring )

This accessor sets or gets the formatstring used to generate the
log-matching regexp.

=cut

sub format {
    my $self   = shift;
    my $class  = ref $self;
    my $format = $self->{format};

    if (@_) {
        $self->{_regexp} = $self->{format} = shift;
        no strict 'refs';
        $self->{_regexp} =~ s/${"$class::CONVERT"}/${"$class::REGEXP"}{$1}/g;
    }
    return $format;
}

=item capture( @fields )

Add the elements of @fields to the list of fields that the regular
expression should capture (if possible).

The method returns the list of actually  captured fields, B<in the same
order as the regular expression capture> in list context.

The special tags C<:none> and C<:all> can be used to capture none or
all of the fields. C<:none> can be used to reset a capture list, as shown in the following example:

    my $log = Regexp::Log::Foo->new( format => $format );

    # create a regexp that will capture gmttime and host
    $log->capture(qw( gmttime host ));
    my $re1 = $log->regexp;    # captures gmttime and host

    # add username to the list of captured fields
    $log->capture(qw( username ));
    my $re2 = $log->regexp;    # captures gmttime, host and username

    # start afresh and capture username and uri
    $log->capture(qw( :none username uri ));
    my $re3 = $log->regexp;    # captures username and uri

=cut

sub capture {
    my $self = shift;

    # add the new tags to capture
    for (@_) {

        # special tags
        if ( $_ eq ':none' ) { $self->{capture} = {} }
        elsif ( $_ eq ':all' ) {
            my @fields = ( $self->{_regexp} =~ /\(\?\#([-\w]+)\)/g );
            @{ $self->{capture} }{@fields} = (1) x @fields;
        }

        # normal tags
        else { $self->{capture}{$_} = 1 }
    }

    # compute what will be actually captured, in which order
    return
      grep { $self->{capture}{$_} } ( $self->{_regexp} =~ /\(\?\#([-\w]+)\)/g );

}

=item regexp

Return the computed regular expression, read to use.

regex() is an alias for regexp().

=cut

sub regexp {
    my $self = shift;
    my $regexp = $self->{_regexp};
    $regexp =~ s{\(\?\#(-[\w]+\)(.*?)\(\?\#!\1)}
                {$self->{capture}{$_} ? "($2)" : $2 }eg;
    return $regexp;
}

*regex = \&regexp;

=head1 TODO

Make it easy to create derived classes for any logging system.

=head1 BUGS

Probably lots. Most of them should be in the derived classes, though.

=head1 AUTHOR

Philippe 'BooK' Bruhat E<lt>book@cpan.orgE<gt>.

=head1 LICENCE

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;
