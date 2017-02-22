use strict;
use warnings;
package Try::Filter;

use Filter::Simple;
use Text::Balanced qw( extract_codeblock );

# use an object to indicate a code-block never called return
my $S =  __PACKAGE__ . "::SENTINEL";
our $SENTINEL = bless {}, $S;

# return val of a Try::Tiny try/catch construct gets stored here
# so we can return it to the caller if needed.
my $R = __PACKAGE__ . "::RETVAL";
our @RETVAL;


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

      # if it's a try block, capture the return value. localised to allow nesting
      $filtered_code .= "do { local \@$R = " if $kw eq 'try';

      # wrap all non-finally code blocks to return the sentinel if return is
      # not otherwise called. (finally does not support returning a value!)
      $filtered_code .= "$kw { do $code_block; return \$$S; }" unless $kw eq 'finally';

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


1; # && "This was an awful idea."; # truth
