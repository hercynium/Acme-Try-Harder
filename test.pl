#!/usr/bin/env perl
#
# To get the filtered code, try this:
#  perl -c -MFilter::ExtractSource test.pl | grep -v '^use Acme::Try::Harder;'
#
use strict;
use warnings;
use lib './lib';
use Acme::Try::Harder;
use Data::Dumper;

print "BEGIN\n";

sub foo {
  try {
    print "TRYING\n";
    #return "YAAY!";
    die "EXCEPTION\n";
  }
  catch {
    print "CAUGHT: $@";
    # should return this value from the sub
    return "YAAY!!"
  }
  finally {
    # should always output
    print "FINALLY\n";
    # finally doesn't support return
    return "IMPOSSIBLE!"
  }
  print "OOPS!\n";
  return "FAIL";
}

my $x = foo();
print "RETURNED: " . Dumper $x;

# returning from outside a sub makes no sense.
try { print "TRYING AGAIN\n"; die "EXCEPTION\n" }
catch { print "CAUGHT: $@" }
finally { print "FINALLY\n" }

print "END\n";


