#!/usr/bin/env perl

use strict;
use warnings;
use lib './lib';
use Try::Tiny;
use Try::Filter;
use Data::Dumper;

print "BEGIN\n";

sub foo {
  try {
    print "TRYING\n";
    #return "YAAY!";
    die "EXCEPTION\n";
  }
  catch {
    print "CAUGHT: $_";
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
print Dumper $x;

try { print "TRYING AGAIN\n"; die "EXCEPTION\n" }
catch { print "CAUGHT: $_"; return "YAAY!!!" }
finally { print "FINALLY\n"; return "IMPOSSIBLE!" }


print "END\n";


