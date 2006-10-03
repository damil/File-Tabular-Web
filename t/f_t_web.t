#!perl
use strict;
use warnings;
no warnings 'uninitialized';
use CGI;
use File::Copy;

use Test::More tests => 9;

BEGIN {
	use_ok( 'File::Tabular::Web' );
}

# get a fresh copy of the data file
copy("t/htdocs/html/entities_src.txt", "t/htdocs/html/entities.txt")
  or die "copy: $!";

# setup environment for CGI
my $url = "html/entities.tdb";
$ENV{PATH_INFO}       = $url;
$ENV{PATH_TRANSLATED} = "t/htdocs/$url";
$ENV{DOCUMENT_ROOT}   = "t/htdocs";
$ENV{REQUEST_METHOD}  = "GET";
$ENV{REMOTE_USER}     = "tst_file_tabular_web";

sub response {
  my $query = shift;

  my $response;
  local *STDOUT;
  open STDOUT, ">", \$response;

  my $cgi = CGI->new($query);
  File::Tabular::Web->process($cgi);
  return $response;
}


like(response(""), 
     qr[Welcome], 
     'homepage');

like(response("S=*"), 
     qr[<b>67</b> results found],
     'search all');

like(response("S=grave"), 
     qr[<b>10</b> results found], 
     'search grave');

like(response("L=221"), 
     qr[Entity named <b>Yacute</b>],
     'long');

like(response("M=221"), 
     qr[<input name="Name" value="Yacute">],
     'modify');

like(response("U=221"), 
     qr[Updated.*221],
     'update');

like(response("D=221"), 
     qr[Deleted.*221],
     'delete');

like(response("S=221"), 
     qr[<b>0</b> results found],
     'check deleted');
