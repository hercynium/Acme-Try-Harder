use strict;
use warnings;
package Acme::Try::Harder;

use Data::Dumper;

use Module::Load::Conditional qw( can_load );
use Import::Into;

use Carp;
$Carp::Internal{+__PACKAGE__}++;

# determine the best try/catch/finally implementation to export to the caller
our $IMPL;
our $PP_IMPL;
BEGIN {
  $PP_IMPL = "Acme::Try::Softer";
  # Syntax::Keyword::Try is faster, safer, and better than the source filter
  # in every way. If it's available, just use it and be done with all this.
  if ( can_load( modules => { 'Syntax::Keyword::Try' => undef } )
       and not $ENV{TRY_HARDER_USE_PP} ) {
    #warn "USING Syntax::Keyword::Try\n";
    $IMPL = "Syntax::Keyword::Try";
  }
  else {
    # but if it is's not installed, fall back to this monstrosity which
    # uses Try::Tiny and mangles the caller's code to (sorta) work like
    # Syntax::Keyword::Try...
    #warn "USING Try::Tiny + Source Filtering\n";
    #$IMPL = "Try::Tiny";
    $IMPL = $PP_IMPL;
  }
}

use if $IMPL eq $PP_IMPL, "Filter::Simple";
use if $IMPL eq $PP_IMPL, "Text::Balanced" => qw( extract_codeblock );
use if $IMPL eq $PP_IMPL, "Try::Tiny" => ();


sub import {
    # TODO: add option to force using a particular implementation
    $IMPL->import::into( scalar caller() );
}


### code below only needed for the source-filtering implementation

# use an object to indicate a code-block never called return. This assumes
# nobody will ever intentionally return this object themselves...
my $S =  __PACKAGE__ . "::SENTINEL";
our $SENTINEL = bless {}, $S;

# return val of a Try::Tiny try/catch construct gets stored here
# so we can return it to the caller if needed.
my $R = __PACKAGE__ . "::RETVAL";
our @RETVAL;

# if an error is caught, stash it here to inject in the finally block
my $E = __PACKAGE__ . "::ERROR";
our $ERROR;

# cache surrounding sub's @_ to set in try/catch subs
my $A = __PACKAGE__ . "::ARGS";
our @ARGS;

# TODO: store $_ in a var so it (maybe?) can behave the same... not sure if
# that is possible...

sub munge_code {
  # work on a copy of the original, build up new code from that
  my ($code_to_filter) = @_;
  my $filtered_code = "";

  # if we don't find a catch-block, we'll need to inject a dummy one to preserve
  # $@ in the finally block.
  my $found_catch = 0;

  # find try/catch/finally keywords followed by a code-block, and extract the block
  while ( $code_to_filter =~ / ( .*? ) \b( try | catch | finally ) \s* ( [{] .* ) /msx ) {
    my ($before_kw, $kw, $after_kw) = ($1, $2, $3);
    my ($code_block, $remainder) = extract_codeblock($after_kw, "{}");

    # make sure to munge any nested try/catch blocks
    $code_block = munge_code( $code_block ) if $code_block;

    # rebuild the code with our modifications...
    $filtered_code .= $before_kw;

    # if it's the try keyword, wrap the whole thing in a do-block and capture
    # the return value from the try function (localised to allow nesting).
    # Also wrap the block in a do to avoid confusing the perl parser. If
    # return isn't invoked in the inner -do-block, the sentinel will be
    # returned, indicating we shouldn't return from the outer do-block later.
    if ( $kw eq 'try' ) {
      $filtered_code .= "do { local \@$A = \@_; local \$$E; local \@$R = $kw { \@_ = \@$A; do $code_block; return \$$S; }";
    }
    # catch blocks get the sentinel treatment, plus shoving the exception
    # back into $@ for compatability with Syntax::Keyword::Try. Yes, this
    # is disgusting. But if you're using this module you're just as much
    # a monster as I am.
    elsif ( $kw eq 'catch' ) {
      # SKT only supports a single catch block, so enforce that here...
      $filtered_code .= "$kw { \@_ = \@$A; \$$E = \$_; local \$@ = \$_; do $code_block; return \$$S; }";
      $found_catch = 1;
    }
    # finally blocks do not support returning, but should see the error in $@, for
    # compat with SKT
    elsif ( $kw eq 'finally' ) {
      # if user never adds a catch block, we need to make one so we can propagate
      # $@ into the finally block (ick)
      if ( not $found_catch ) {
        $filtered_code .= "catch { \$$E = \$_; die \$_ }";
      }
      $filtered_code .= "$kw { local \$@ = \$$E; do $code_block; }";
    }

    # if the remainder doesn't start with a catch or finally clause, assume
    # that's the end and add code to check for the sentinel and DTRT
    if ( $remainder !~ /\A \s* ( catch | finally ) \s* [{] /msx ) {
      # if RETVAL contains the sentinel, then the block never called return so neither
      # should we, and of course never call return if not inside a subroutine
      my $ret_code = "if ( caller() and ( !ref(\$$R\[0]) or !\$$R\[0]->isa(ref(\$$S)) ) )"
                  . " { return wantarray ? \@$R : \$$R\[0]; }";
      $filtered_code .= "; $ret_code };";
    }

    # repeat this loop on the remainder
    $code_to_filter = $remainder;
  }

  # overwrite the original code with the filtered code, plus whatever was left-over
  return $filtered_code . $code_to_filter;
}


my $D = __PACKAGE__ . "::DIED";
our $DIED;
my $W = __PACKAGE__ . "::WANTARRAY";
our $WANTARRAY;
my $T = __PACKAGE__ . "::TRY";
our $TRY;
my $C = __PACKAGE__ . "::CATCH";
our $CATCH;
my $F = __PACKAGE__ . "::FINALLY";
our $FINALLY;

my $G = __PACKAGE__ . "::ScopeGuard";

# an alternative implementation that replaces Try::Tiny with plain eval...
sub munge_code2 {
  # work on a copy of the original, build up new code from that
  my ($code_to_filter) = @_;
  my $filtered_code = "";

  my $found_catch = 0;
  my $found_finally = 0;

  # find try/catch/finally keywords followed by a code-block, and extract the block
  while ( $code_to_filter =~ / ( .*? ) \b( try | catch | finally ) \s* ( [{] .* ) /msx ) {
    my ($before_kw, $kw, $after_kw) = ($1, $2, $3);
    my ($code_block, $remainder) = extract_codeblock($after_kw, "{}");

    # make sure to munge any nested try/catch blocks
    $code_block = munge_code( $code_block ) if $code_block;

    chomp $code_block;

    # rebuild the code with our modifications...
    $filtered_code .= $before_kw;

    if ( $kw eq 'try' ) {
      $filtered_code .= ";{ ";
      $filtered_code .= "local \$$T = sub { do $code_block; return \$$S; };";
    }
    elsif ( $kw eq 'catch' ) {
      die "Syntax Error: Only one catch-block allowed." if $found_catch++ > 1;
      $filtered_code .= "local \$$C = sub { do $code_block; return \$$S; };";
    }
    elsif ( $kw eq 'finally' ) {
      die "Syntax Error: Only one finally-block allowed." if $found_finally++ > 1;
      $filtered_code .= "local \$$F = '$G'->_new(sub $code_block, \@_); ";
    }

    # if the remainder doesn't start with a catch or finally clause, assume
    # that's the end and add code to check for the sentinel and DTRT
    if ( $remainder !~ /\A \s* ( catch | finally ) \s* [{] /msx ) {
      $filtered_code .= "local ( \$$E, \$$D, \@$R ); local \$$W = wantarray; "
                      . "{ local \$@; \$$D = not eval { if ( \$$W ) { \@$R = &\$$T; } elsif ( defined \$$W ) { \$$R\[0] = &\$$T; } else { &\$$T; } return 1; }; \$$E = \$@; }; "
                      . "if ( \$$D ) { "
                      .   "if ( \$$C ) { "
                      .     "local \$@ = \$$E; "
                      .     "if ( \$$W ) { \@$R = &\$$C; } elsif ( defined \$$W ) { \$$R\[0] = &\$$C; } else { &\$$C; } "
                      .   "} "
                      .   "else { die \$$E } "
                      . "}; "
                      . "if ( caller() and (!ref(\$$R\[0]) or !\$$R\[0]->isa('$S')) ) { return \$$W ? \@$R : \$$R\[0]; } "
                      . "}";

      $found_catch = $found_finally = 0;
    }

    # repeat this loop on the remainder
    $code_to_filter = $remainder;
  }

  # overwrite the original code with the filtered code, plus whatever was left-over
  return $filtered_code . $code_to_filter;
}


sub setup_filter {
  # Let Filter::Simple strip out all comments and strings to make it easier
  # to extract try/catch/finally code-blocks correctly.
  FILTER_ONLY(
    code_no_comments => sub { $_ = munge_code2( $_ ) }
  );
}

setup_filter() if $IMPL eq $PP_IMPL;


package Acme::Try::Harder::ScopeGuard; {
  use Data::Dumper;
  use constant UNSTABLE_DOLLARAT => ("$]" < '5.013002') ? 1 : 0;
  sub _new {
    shift;
    bless [ @_ ];
  }
  sub DESTROY {
    my ($code, @args) = @{ $_[0] };
    # save the err to make it available in the finally sub, and to restore after
    my $err = $@;
    # work around issue in older versions of perl
    local $@ if UNSTABLE_DOLLARAT;
    eval {
      $@ = $err;
      $code->(@args);
      1;
    } or do {
      warn
        "Execution of finally() block $code resulted in an exception, which "
      . '*CAN NOT BE PROPAGATED* due to fundamental limitations of Perl. '
      . 'Your program will continue as if this event never took place. '
      . "Original exception text follows:\n\n"
      . (defined $@ ? $@ : '$@ left undefined...')
      . "\n"
      ;
    };
    # restore the original error
    $@ = $err;
  }
}

1 && "This was an awful idea."; # truth
