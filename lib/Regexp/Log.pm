package Regexp::Log;

use strict;
use Carp;
use vars qw( $VERSION );

$VERSION = 0.04;

=head1 NAME

Regexp::Log - A base class for log files regexp builders

=head1 SYNOPSIS

    my $foo = Regexp::Log::Foo->new(
        format  => 'custom %a %b %c/%d',
        capture => [qw( host code )],
    );

    # the format() and capture() methods can be used to set or get
    $foo->format('custom %g %e %a %w/%s %c');
    $foo->capture(qw( host code ));

    # this is necessary to know in which order
    # we will receive the captured fields from the regexp
    my @fields = $foo->capture;

    # the all-powerful capturing regexp :-)
    my $re = $foo->regexp;

    while (<>) {
        my %data;
        @data{@fields} = /$re/;    # no need for /o, it's a compiled regexp

        # now munge the fields
        ...
    }

=head1 DESCRIPTION

Regexp::Log is a base class for a variety of modules that generate
regular expressions for performing the usual data munging tasks on
log files that cannot be simply split().

The goal of this module family is to compute regular expressions
based on the configuration string of the log.

Please note that there is I<nothing useful> you can do with Regexp::Log!
Use one of its derived classes!

=head1 METHODS

The following methods are available, and form the general API for the
derived classes.

Please note that all the accessors return the new value, if used to set.

=over 4

=item new( %args )

Return a new Regexp::Log object. A list of key-value pairs can be given
to initialise the object.

The default arguments are:

 format   - the format of the log line
 capture  - the name of the fields to capture with the regexp
            (given as an array ref)
 comments - leave the (?#=name) ... (?#!name) comments in the regexp

Other arguments (and the corresponding accessors) can be defined in derived
classes.

=cut

sub new {
    my $class = shift;
    no strict 'refs';
    my $self = bless {
        debug    => 0,
        comments => 0,
        %{"${class}::DEFAULT"},
        @_
    }, $class;

    # some initialisation code
    if ( my @capture = @{ $self->{capture} } ) {
        $self->{capture} = [];
        $self->capture(@capture);
    }

    return $self;
}

=item format( $formatstring )

This accessor sets or gets the format string used as a template
to generate the log-matching regexp. This is usually the configuration
line of the log-generating software.

=cut

sub format {
    my $self = shift;
    $self->{format} = shift if @_;
    return $self->{format};
}

=item capture( @fields )

Add the elements of @fields to the list of fields that the regular
expression should capture (if possible).

The method returns the list of actually captured fields, B<in the same
order as the regular expression captures>.

The special tags C<:none> and C<:all> can be used to capture none or all
of the fields. C<:none> can also be used to reset a capture list, as shown
in the following example:

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

When used to set, this method returns the I<new> list of captured fields,
in capture order.

=cut

sub capture {
    my $self = shift;

    # add the new tags to capture
    for (@_) {

        # special tags
        if ( $_ eq ':none' ) { $self->{capture} = [] }
        elsif ( $_ eq ':all' ) {
            $self->{capture} = [ $self->fields ];
        }

        # normal tags
        else { push @{ $self->{capture} }, $_ }
    }

    my %capture = map { ( $_, 1 ) } @{ $self->{capture} };
    $self->{capture} = [ keys %capture ] if @_;

    # compute what will be actually captured, in which order
    $self->_regexp;
    return grep { $capture{$_} } ( $self->{_regexp} =~ /\(\?\#=([-\w]+)\)/g );

}

# this internal method actually computes the correct regular expression
sub _regexp {
    my $self  = shift;
    my $class = ref $self;

    $self->{_regexp} = $self->{format};

    $self->{_regexp} =~ s/([\\|()\[\]{}^\$*+?.])/\\$1/g;
    $self->_preprocess if $self->can('_preprocess');

    # accept predefined formats
    no strict 'refs';
    $self->{format} = ${"${class}::FORMAT"}{ $self->{format} }
      if exists ${"${class}::FORMAT"}{ $self->{format} };

    my $convert = join '|', reverse sort keys %{"${class}::REGEXP"};
    $self->{_regexp} =~ s/($convert)/${"${class}::REGEXP"}{$1}/g;

    $self->_postprocess if $self->can('_postprocess');
}

=item regexp( )

Return a computed regular expression, computed from the data given to 
the Regexp::Log object, and ready to be used in a script.

=item regex( )

regex() is an alias for the regexp() method.

=cut

sub regexp {
    my $self   = shift;
    $self->_regexp;
    my $regexp = $self->{_regexp};

    my %capture = map { ( $_, 1 ) } @{ $self->{capture} };

    # this is complicated, but handles multiple levels of imbrication
    my $pos = 0;
    while ( ( $pos = index( $regexp, "(?#=", $pos ) ) != -1 ) {
        ( pos $regexp ) = $pos;
        $regexp =~ s{\G\(\?\#=([-\w]+)\)(.*?)\(\?\#\!\1\)}
                    { exists $capture{$1} ? "((?#=$1)$2(?#!$1))"
                                          : "(?:(?#=$1)$2(?#!$1))" }ex;
        $pos += 4;    # oh my! a magic constant!
    }

    # for regexp debugging
    if ( $self->debug ) {
        $regexp =~ s/\(\?\#\!([-\w]+)\)/(?#!$1)(?{ print STDERR "$1 "})/g;
        $regexp =~ s/^/(?{ print STDERR "\n"})/;
    }

    # remove comments
    $regexp =~ s{\(\?\#[=!][^)]*\)}{}g unless $self->comments;

    # compute the regexp
    if ( $self->debug ) { use re 'eval'; $regexp = qr/^$regexp$/; }
    else { $regexp = qr/^$regexp$/ }

    return $regexp;
}

*regex = \&regexp;

=item fields( )

This method return the list of all the fields that can be captured.

For complex subclasses making a lot of modifications in _preprocess() and
_postprocess(), the result may not be accurate.

The result of fields() is therefore given for information only.

=cut

sub fields {
    my $self  = shift;
    my $class = ref $self;
    no strict 'refs';
    return map { (/\(\?\#=([-\w]+)\)/g) } values %{"${class}::REGEXP"};
}

=item comments( $bool )

Accessor for the C<comments> attribute.

Comments are removed by default.

=cut

sub comments {
    my $self = shift;
    $self->{comments} = shift if @_;
    return $self->{comments};
}

=item debug( $bool );

Get/set regexp debug mode.

If C<debug> is set, each time a field (or subfield) is matched, its name
(followed by a space) is printed on STDERR. A newline is printed at the
beginning of the search. This lets you see where the regexp backtracks,
and watch all its attempts to match something. Useful but usually I<very>
verbose.

This is mainly useful when writing a new Regexp::Log subclass.

=cut

sub debug {
    my $self = shift;
    $self->{debug} = shift if @_;
    return $self->{debug};
}

=back

=head1 SUBCLASSES

This section explains how to create new subclasses of Regexp::Log.

=head2 Package template

To implement a Regexp::Log::Foo class, you need to create a package
that defines the appropriate class variables, as in the following
example (this is the complete code for Regexp::Log::Foo!):

    package Regexp::Log::Foo;

    use base qw( Regexp::Log );
    use vars qw( $VERSION %DEFAULT %FORMAT %REGEXP );

    $VERSION = 0.01;

    # default values
    %DEFAULT = (
        format  => '%d %c %b',
        capture => [ 'c' ],
    );

    # predefined format strings
    %FORMAT = ( ':default' => '%a %b %c', );

    # the regexps that match the various fields
    # this is the difficult part
    %REGEXP = (
        '%a' => '(?#=a)\d+(?#!a)',
        '%b' => '(?#=b)th(?:is|at)(?#!b)',
        '%c' => '(?#=c)(?#=cs)\w+(?#!cs)/(?#=cn)\d+(?#!cn)(?#!c)',
        '%d' => '(?#=d)(?:foo|bar|baz)(?#!d)',
    );

    # Note that the three hashes (%DEFAULT, %FORMAT and %REGEXP)
    # MUST be defined, even if they are empty.

    # the _regexp field is an internal field used as a template
    # by the regexp()

    # the _preprocess method is used to modify the format string
    # before the fields are expanded to their regexp value
    sub _preprocess {
        my $self = shift;

        # multiple consecutive spaces in the format are compressed
        # to a single space
        $self->{_regexp} =~ s/ +/ /g;
    }

    # the _postprocess method is used to modify the format string
    # after the fields are expanded to their regexp value

    1;

Please note that the _preprocess() and _postprocess() method should
only modify the C<_regexp> attribute.

The comments are removed after _postprocess() is run, if C<comments>
is set to a false value.

=head2 Some explanations on the regexp format

You may have noticed the presence of C<(?#...)> regexp comments in the
previous example. These are used by Regexp::Log to identify the different
parts of the log line and compute a regular expression that can capture
them.

These comments work just like HTML tags: C<(?#=bar)> marks the beginning
of a field named I<bar>, and C<(?#!bar)> marks the end of the field.

You'll also notice that C<%c> is split in two subfields: C<cs> and
C<cn>, which have their own tags.

Consider the following example script:

    my $log = Regexp::Log::Foo->new(
        format => ':default',
        capture => [ qw( c cn ) ],
    );
    my $re = $log->regexp;
    my @fields = $log->capture();

    while(<>) {
        my @data;
        @data{@fields} = (/$re/g);

        # some more code
    }

The %data hash will have two keys: C<c> and C<cn>, even though C<c>
already holds the information in C<cn>. This gives log mungers a lot
of flexibility in what they can get from their log lines, with no added
work. Lazyness is a virtue.

B<Important notes:>

=over 4

=item *

Since Regexp::Log handles all the capturing parentheses
by itself, there must not be any capturing parentheses in any regexp template
of a derived class. If there are capturing parentheses in the values of
%REGEXP, named captures I<will not work>.

=item *

All the regexp comments that let the Regexp::Log classes find the named
captures must be stored in %REGEXP values. Even if you are using a
complex process to create the final regexp (have a look at
Regexp::Log::BlueCoat source code), you I<must> put the special regexp
comments in %REGEXP.

=back

=head2 Changing the subclasse default behaviour

If a subclass that is available from CPAN is buggy or incomplete, or
does not exactly fit your log files, it's very easy to add to a
Regexp::Log subclass from within your scripts.

Imagine that the C<%d> element of our Regexp::Log::Foo module is
incomplete, because it does not match the string C<fu> that appears
occasionaly (maybe the Regexp::Log::Foo developper didn't know?).
Or that you patched the Foo software so that your own version creates
non-standard log files.

After emailing the patch to the author, you can temporarily fix your
script by adding the following line:

    $Regexp::Log::Foo::REGEXP{'%d'} = '(?#=d)(?:fu|foo|bar|baz)(?#!d)'

That is to say, by replacing the C<%d> entry in the subclass' %REGEXP
hash.

=head1 BUGS

Probably. Most of them should be in the derived classes, though.

The F<t/20debug.t> test file fails with Perl 5.6.0 and 5.6.1. I have
no idea why, but it may be linked to the use of the C<(?{ ... })> regexp
construct in the debugging code.

=head1 AUTHOR

Philippe 'BooK' Bruhat E<lt>book@cpan.orgE<gt>.

=head1 LICENCE

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.

=cut

1;
