#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'File::Tabular::Web' );
}

diag( "Testing File::Tabular::Web $File::Tabular::Web::VERSION, Perl $], $^X" );
