use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'File::Tabular::Web',
    license             => 'perl',
    dist_author         => 'Laurent Dami <laurent.dami@justice.ge.ch>',
    dist_version_from   => 'lib/File/Tabular/Web.pm',
    requires => {
        'Carp'                => 0,
        'CGI'                 => 0,
        'Template'            => 0,
        'AppConfig'           => 0,
        'POSIX'               => 0,
        'File::Basename'      => 0,
        'File::Path'          => 0,
        'List::Util'          => 0,
        'List::MoreUtils'     => 0,
        'File::Tabular'       => 0.71,
        'Search::QueryParser' => 0.92,
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'File-Tabular-Web-*' ],
);

$builder->create_build_script();
