use strict;
use warnings;
package Acme::Try::Harder;

use Module::Load::Conditional qw( can_load );
use Import::Into;

# determine the best try/catch/finally implementation to export to the caller
our $IMPL;

BEGIN {
  # Syntax::Keyword::Try is faster, safer, and better than the source filter
  # in every way. If it's available, just use it and be done with all this.
  if (0 && can_load( modules => { 'Syntax::Keyword::Try' => undef } )) {
    #warn "USING Syntax::Keyword::Try\n";
    $IMPL = "Syntax::Keyword::Try";
  }
  else {
    # but if it is's not installed, fall back to this monstrosity which
    # uses Try::Tiny and mangles the caller's code to (sorta) work like
    # Syntax::Keyword::Try...
    #warn "USING Try::Tiny + Source Filtering\n";
    $IMPL = "Try::Tiny";
  }
}

use if $IMPL eq "Try::Tiny", "Filter::Simple";
use if $IMPL eq "Try::Tiny", "Text::Balanced" => qw( extract_codeblock );
use if $IMPL eq "Try::Tiny", "Try::Tiny" => ();


sub import {
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

# TODO: store $_ in a var so it (maybe?) can behave the same... not sure if
# that is possible...

sub setup_filter {

  # Let Filter::Simple strip out all comments and strings to make it easier
  # to extract try/catch/finally code-blocks correctly.
  FILTER_ONLY(
    code_no_comments => sub {

      # work on a copy of the original, build up new codefrom that
      my $code_to_filter = $_;
      my $filtered_code;

      # find try/catch/finally keywords followed by a code-block, and extract the block
      while ( $code_to_filter =~ / ( .*? ) \b( try | catch | finally ) \s* ( [{] .* ) /msx ) {
        my ($before_kw, $kw, $after_kw) = ($1, $2, $3);
        my ($code_block, $remainder) = extract_codeblock($after_kw, "{}");

        # rebuild the code with our modifications...
        $filtered_code .= $before_kw;

        # if it's the try keyword, wrap the whole thing in a do-block and capture
        # the return value from the try function (localised to allow nesting).
        # Also wrap the block in a do to avoid confusing the perl parser. If
        # return isn't invoked in the inner -do-block, the sentinel will be
        # returned, indicating we shouldn't return from the outer do-block later.
        if ( $kw eq 'try' ) {
          $filtered_code .= "do { local \@$R = $kw { do $code_block; return \$$S; }";
        }
        # catch blocks get the sentinel treatment, plus shoving the exception
        # back into $@ for compatability with Syntax::Keyword::Try. Yes, this
        # is disgusting. But if you're using this module you're just as much
        # a monster as I am.
        elsif ( $kw eq 'catch' ) {
          $filtered_code .= "$kw { local \$@ = \$_; do $code_block; return \$$S; }"
        }
        # finally blocks neither support returning, nor do they see the contents
        # of $@, so, really... we can just leave them alone!
        else {
          $filtered_code .= "$kw $code_block";
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
      $_ = $filtered_code . $code_to_filter;
    }
  );
}

setup_filter() if $IMPL eq "Try::Tiny";

1 && "This was an awful idea."; # truth
