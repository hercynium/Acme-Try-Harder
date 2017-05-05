#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Acme::Try::Harder;

# try/catch localises $@ (RT118415)
{
   eval { die "oopsie" };
   like( $@, qr/^oopsie at /, '$@ before try/catch' );

   try { die "another failure" } catch {}

   like( $@, qr/^oopsie at /, '$@ after try/catch' );
}

done_testing;
