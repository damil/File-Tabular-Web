#!perl -T

use Test::More tests => 3;

BEGIN {
	use_ok( 'File::Tabular::Web' );
	use_ok( 'File::Tabular::Web::Attachments' );
	use_ok( 'File::Tabular::Web::Attachments::Indexed' );
}

diag( "Testing File::Tabular::Web $File::Tabular::Web::VERSION, Perl $], $^X" );
