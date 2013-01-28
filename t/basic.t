#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Win32::ServiceManager;

ok(my $sm = Win32::ServiceManager->new, 'instantiate');

done_testing;
