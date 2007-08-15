#!perl
use strict;
use warnings;
no warnings 'uninitialized';
use CGI;
use File::Copy;

use Test::More tests => 11;


BEGIN {
#  use lib "../lib";
  use_ok( 'File::Tabular::Web' );
}

my $DIR = "t";
# my $DIR = ".";

# get a fresh copy of the data file
copy("$DIR/htdocs/html/entities_src.txt", "$DIR/htdocs/html/entities.txt")
  or die "copy: $!";

# setup environment for CGI
my $url = "html/entities.tdb";
$ENV{PATH_INFO}       = $url;
$ENV{PATH_TRANSLATED} = "$DIR/htdocs/$url";
$ENV{DOCUMENT_ROOT}   = "$DIR/htdocs";
$ENV{REQUEST_METHOD}  = "GET";
$ENV{REMOTE_USER}     = "tst_file_tabular_web";

sub response {
  my $query = shift;

  # will capture response in a string
  my $response;
  local *STDOUT;
  open STDOUT, ">", \$response;

  # reinitialize CGI
  CGI::initialize_globals();

  # call the handler
  File::Tabular::Web->handler($query);

  return $response;
}


like(response(""), 
     qr[Welcome], 
     'homepage');

my $search_all = response({S=>"*"});

like($search_all,
     qr[<b>67</b> results found],
     'search all');

like($search_all,
     qr[200],
     'fixed config param');

like($search_all,
     qr[20],
     'default config param');

like(response("S=grave"), 
     qr[<b>10</b> results found], 
     'search grave');

like(response("L=221"), 
     qr[Entity named <b>Yacute</b>],
     'long');

like(response("M=221"), 
     qr[<input name="Name" value="Yacute">],
     'modify');

{
  local $ENV{REQUEST_METHOD}  = "POST";
  like(response({M => 221}), 
       qr[Updated.*221],
       'update');
}

like(response("D=221"), 
     qr[Deleted.*221],
     'delete');

like(response("S=221"), 
     qr[<b>0</b> results found],
     'check deleted');
