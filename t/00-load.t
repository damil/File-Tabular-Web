#!perl -T

use Test::More tests => 3;

BEGIN {
	use_ok( 'File::Tabular::Web' );
	use_ok( 'File::Tabular::Web::Attachments' );
}

diag( "Testing File::Tabular::Web $File::Tabular::Web::VERSION, Perl $], $^X" );


SKIP: {
  eval {require Search::Indexer};
  skip "Search::Indexer does not seem to be installed", 1
    if $@;

  use_ok( 'File::Tabular::Web::Attachments::Indexed' );
}
