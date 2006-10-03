=begin comment

CHANGES


## TODO : ADD in each decis *.app
    [filters]
    htmlDecis      = decisHtmlFilterFactory, 1
    autoDecisLinks = autoDecisLinks

TODO : create logger in new()

TODO: HTTP headers out of template

     - rename getCGI => param

=end comment

=cut




package File::Tabular::Web;

our $VERSION = "0.11"; 


use strict;
use warnings;
no warnings 'uninitialized';
use locale;
use Carp;
use CGI;
use Template;
use POSIX 'strftime';
use File::Basename;
use List::Util      qw/min/;
use List::MoreUtils qw/uniq any all/;
use AppConfig       qw/:argcount/;
use File::Tabular;
use Search::QueryParser;

my %app_cache;

#----------------------------------------------------------------------
sub process { # create a new instance and immediately process request
#----------------------------------------------------------------------
  my $self;
  eval { $self = new(@_);  $self->dispatch_request; 1;}
    or do {
      $self ||= {};  # fake object just in case the new() method failed
      $self->{msg} = "<b><font color=red>ERROR</font></b> : $@";
      print "Content-type: text/html\n\n\n";

      # try displaying through msg view..
      eval {$self->{app}{tmpl}->process($self->tmpl_name('msg'), 
                                        {self => $self})}
        # .. or else fallback with simple HTML page
        or print "<html>$self->{msg}</html>\n";

    };
}


#----------------------------------------------------------------------
sub new { 
#----------------------------------------------------------------------
  my $class = shift;


  my $cgi =  shift; 

  $cgi = CGI->new() unless $cgi and $cgi->isa('CGI'); # for ModPerl
  $cgi = CGI->new() if not $cgi;

  my $path = $cgi->path_translated || $ENV{SCRIPT_FILENAME}; # for ModPerl

  my $path = $cgi->path_translated;



  my $app = $app_cache{$path} ||= new_app($path);

  my $self = {};
  bless $self, ($app->{class} || $class);

  $self->{cgi}  = $cgi;
  $self->{user} = $cgi->remote_user() || "Anonymous";
  $self->{url}  = $cgi->url(-path => 1);
  $self->{msg}  = undef;
  $self->{app}  = $app;
  $self->{cfg}  = $self->{app}{cfg}; # shortcut

  return $self->initialize_request;
}


#----------------------------------------------------------------------
sub initialize_request {
#----------------------------------------------------------------------
  my $self = shift;

  # setup some general parameters
  my %builtin_defaults = (max    => 500,   # max records retrieved	
			  count  => 50,    # how many records in a single slice
			  sortBy => "",	   # default sort criteria
			 );
  while (my ($k, $v) = each %builtin_defaults) {
    $self->{$k} 
      = $self->{cfg}->get("fixed_$k")   || # fixed value in config, or
	$self->param($k)               || # given in CGI param, or 
        $self->{cfg}->get("default_$k") || # default value in config, or
        $v;                                # builtin default
  }
  return $self;
}

#----------------------------------------------------------------------
sub new_app { 
#----------------------------------------------------------------------
  my $config_file = shift;

  my $app = {};

  # find apache directory, one level above document_root
  ($app->{apache_dir}) = ($ENV{DOCUMENT_ROOT} =~ m[(.*)[/\\]]); 

  # initialise from config file
  my $cfg     = read_config($config_file);
  $app->{cfg} = $cfg;

  @{$app}{qw(appname dir suffix)} = fileparse($config_file, qr/\.[^.]*$/);


  $app->{tmpl_dir} =  $cfg->get("fixed_tmpl_dir") 
                   || $cfg->get("default_tmpl_dir") 
		   || "lib/tmpl/tdb";

  $app->{upload_fields} = $cfg->get('fields_upload'); # hashref
  $app->{time_fields}   = $cfg->get('fields_time');   # hashref
  my $dataFile          = $cfg->get("dataFile") || "$app->{appname}.txt";
  $app->{dataFile}      = $app->{dir} . $dataFile;
  $app->{queueDir}      = $cfg->get('fixed_queueDir'); 

  # load additional Perl code requested in config
  my $modules_ref       = $cfg->get('perl_use');    # only keys, no values
  $app->{class}         = $cfg->get('perl_class');  # optional base class
  my $requires_ref      = $cfg->get('perl_require');# only keys, no values
  my $eval_ref          = $cfg->get('perl_eval');   # ref to array of code
  {
    local @INC = ($app->{dir}, @INC);
    foreach my $module (grep {$_} (keys %$modules_ref, $app->{class})) {
      eval "use $module" or croak $@; 
    }
    foreach my $required (grep {$_} keys %$requires_ref) {
      require $required or croak $!;
    }
    foreach my $code (@$eval_ref) {
      eval $code or croak $@; 
    }
  }

  # [filters] config section, see L<Template::Filters>
  my %filters = $cfg->varlist('^filters_', 1);
  foreach my $filter (keys %filters) {
    my ($func, $dynamic_flag) = split /\s*,\s*/, $filters{$filter};
    no strict 'refs';

    my $func_ref = \&$func or croak "filter: unknown function, $func";
    $filters{$filter} = [$func_ref, $dynamic_flag];
  }

  # initialize template toolkit object
  $app->{tmpl} = Template->new({
    INCLUDE_PATH => [$app->{dir}, "$app->{apache_dir}/$app->{tmpl_dir}"],
    FILTERS      => \%filters,
   });

  return $app;
}






#----------------------------------------------------------------------
sub read_config { # read configuration file through Appconfig
#----------------------------------------------------------------------
  my $config_file = shift;

  my $cfg = AppConfig->new({
        CASE   => 1,
	CREATE => 1, 
	ERROR  => sub {my $fmt = shift;
                       croak(sprintf("AppConfig : $fmt\n", @_))
                         unless $fmt =~ /no such variable/;
                     },
        GLOBAL => {ARGCOUNT => ARGCOUNT_ONE},
       });

  $cfg->define(fieldSep => {DEFAULT => "|"});
  foreach my $var (qw/perl_use      perl_require   
		      fields_upload fields_default fields_time
		      handlers_prepare  handlers_update/) {
    $cfg->define($var => {ARGCOUNT => ARGCOUNT_HASH});
  }
  $cfg->define(perl_eval => {ARGCOUNT => ARGCOUNT_LIST});

  $cfg->file($config_file); # or croak "AppConfig: open $config_file: $^E";
  # BUG : AppConfig does not return any error code if ->file(..) fails !!

  return $cfg;
}



#----------------------------------------------------------------------
sub find_operation { # returns a ref to the named function
#----------------------------------------------------------------------
  my $self = shift;
  my $operation_name = shift or return undef; 

  no strict 'refs';
  my $code_ref = $self->can($operation_name)    # find either a method ..
              || *{$operation_name}{CODE}       # .. or a loaded function
    or croak "no such operation : $operation_name";

  return $code_ref;
}




#----------------------------------------------------------------------
sub dispatch_request { # look at CGI args and choose appropriate handling
#----------------------------------------------------------------------
  my $self = shift;

  # 1) alias expansion
  $self->expand_aliases;

  # 2) data access
  $self->open_data;

  # 3) data preparation
  my $preparation_phase = $self->find_operation($self->param('PRE'));
  $preparation_phase->($self) if $preparation_phase;

  # 4) pre-check rights
  my $perm = $self->param('PC');
  not($perm) or $self->can_do($perm) or 
    croak "No permission '$perm' for $self->{user}";

  # 5) data manipulation
  my $manipulation_phase = $self->find_operation($self->param('OP'));
  $manipulation_phase->($self) if $manipulation_phase;

  # 6) view
  if ($self->{redirect_target}) {
    print $self->{cgi}->redirect($self->{redirect_target});
  }
  else {
    my $view = $self->param('V');
    $view = 'msg' if $self->{msg}; # force message view if there is a message
    print $self->{cgi}->header;
    $self->display($view);
  }
}


#----------------------------------------------------------------------
BEGIN { # persistent data private to expand_aliases()

# ALIAS EXPANSION TABLE : each single letter alias is expanded into 
# several CGI params : (SS, PRE, PC, OP, V). See L</dispatch_request>
# for the meaning of those. Values of expansions are either constants, 
# or functional transformations of the supplied CGI argument. Aliases are :
#   S => search and display "short" view
#   L => display "long" view of one single record
#   M => display modify view (form for update)
#   A => add new record
#   D => delete record (no PC, permissions checked within 'delete' method)
#   U => update        (no PC, permissions checked within 'update' method)
#   X => display all records in "download view"
#      # NOTE : we don't set SS => "*", this would be inefficient. Instead,
#      # rows will be fetched from within the download template, i.e.
#      # [% WHILE row = app.data.fetchrow %] ... display data row
#
#   H => display home page
#   F => display attached file

  my $id_func   = sub {shift};
  my $upd_func  = sub {my $val = shift; 
		       return $val =~/#/ ? 'empty_record' : 'search_key';},
  my $file_func = sub {"Decision:$_[0]"}; # PG-GE specific;TODO: move elsewhere

  my @alias_headers = 
    qw/   SS           PRE              PC      OP             V        /;
#         ==           ===              ==      ==             =
  my %aliases = (
    S => [$id_func,   'search',        'read', 'post_search', 'short'   ],
    L => [$id_func,   'search_key',    'read', '',            'long'    ],
    M => [$id_func,   'search_key',    'read', '',            'modif'   ],
    A => [$id_func,   'empty_record',  'add',  '',            'modif'   ],
    D => [$id_func,   'search_key',    '',     'delete',      ''        ],
    U => [$id_func,   $upd_func,       '',     'update',      ''        ],
    X => ['',         '',              '',     '',            'download'],
    H => ['',         '',              '',     '',            'home'    ],
    F => [$file_func, 'search',        'read', '',            'long'    ],
   );

  
  #----------------------------------------------------------------------
  sub expand_aliases { # normalize request, expanding aliases into CGI params
  #----------------------------------------------------------------------
    my $self = shift;

    $self->{cgi}->param(V => 'home') unless $self->param('V'); # default value

    my ($alias, @others) = grep {defined $self->{cgi}->param($_)} keys %aliases
      or return; # no alias to expand
    croak "alias expansion conflict" if @others; # can't expand several

    my $passed_value = $self->param($alias);
    my $expansion = $aliases{$alias};

    for my $ix (0 .. $#alias_headers) { # OK, do each expansion
      my $new_param = $alias_headers[$ix];
      my $new_val   = $expansion->[$ix];
      if (UNIVERSAL::isa($new_val, 'CODE')) { # expansion is a func transform
        $new_val = $new_val->($passed_value);
      }
      $self->{cgi}->param($new_param => $new_val); # inject into CGI param
    }
  }
}
#----------------------------------------------------------------------


#----------------------------------------------------------------------
sub open_data { # open File::Tabular object on data file
#----------------------------------------------------------------------
  my $self = shift;

  my $file_name = $self->{app}{dataFile};

  # choose how to open the file
  my @openParams = 
    ($self->param("OP") =~ /delete|update/) ? ("+< $file_name") : # open RW
    (not $self->{cfg}->get('useFileCache'))  ? ($file_name)      : # open ROnly
       do { my $content = _cached_content($file_name);
	    ('<', \$content);                      #  open from the memory copy
	  };

  # set up options for creating File::Tabular object
  my %options;
  my @config_opts = qw/preMatch postMatch avoidMatchKey fieldSep recordSep/;
  $options{$_} = $self->{cfg}->get($_) foreach @config_opts;

  $options{autoNumField} = $self->{cfg}->get('fields_autoNum');
  my $jFile = $self->{cfg}->get('journal');
  $options{journal} = "$self->{dir}$jFile" if $jFile;

  # do it
  $self->{data} = new File::Tabular(@openParams, \%options);
  $self->{data}->ht->add('score'); # new field for storing 'score'
}


#----------------------------------------------------------------------
BEGIN {
  my %datafile_cache; #  persistent data private to _cached_content

  #----------------------------------------------------------------------
  sub _cached_content {
  #----------------------------------------------------------------------
    my $file_name = shift;

    # get file last modification time
    my $mtime = (stat $file_name)[9] or croak "couldn't stat $file_name";

    # delete cache entry if too old
    if ($datafile_cache{$file_name} &&  
	  $mtime > $datafile_cache{$file_name}->{mtime}) {
      delete $datafile_cache{$file_name};	              
    }

    # create cache entry if necessary
    $datafile_cache{$file_name} ||= do {
      open my $fh, $file_name or croak "open $file_name : $^E";
      local $/ = undef;
      my $content = <$fh>;	# slurps the whole file into memory
      close $fh;
      {mtime => $mtime, content => $content}; # return val from do{} block
    };

    return $datafile_cache{$file_name}->{content};
  }
}
#----------------------------------------------------------------------



#----------------------------------------------------------------------
sub search_key { # search one single record
#----------------------------------------------------------------------
  my $self = shift;

  my $query = "K_E_Y:" . $self->param('SS');
  my ($records, $lineNumbers) = $self->{data}->fetchall(where => $query);
  my $count = @$records;
  $self->{results} = {count       => $count, 
		      records     => $records, 
		      lineNumbers => $lineNumbers};
}


#----------------------------------------------------------------------
sub words_queried {
#----------------------------------------------------------------------
  my $self = shift;
  my $search_string   = $self->param('SS');
  return ($search_string =~ m([\w/]+)g);
}



sub log_search {
  my $self = shift;
  return if not $self->{logger};

  my $msg = "[$self->{search_string}] $self->{user}";
  $self->{logger}->info($msg);
}


sub prepare_search_string {
  my $self = shift;
  $self->{search_string} = $self->param('SS') || "";
  return $self;
}

sub end_search_hook {}

#----------------------------------------------------------------------
sub search { # search records and display results
#----------------------------------------------------------------------
  my $self = shift;

  $self->can_do("search") or 
    croak "no 'search' permission for $self->{user}";

  $self->prepare_search_string;
  $self->log_search;

  $self->{results} = {count       => 0, 
		      records     => [], 
		      lineNumbers => []};

  return if $self->{search_string} =~ /^\s*$/; # no query, no results

  my $qp = new Search::QueryParser;

  # compile query with an implicit '+' prefix in front of every item 
  my $parsedQ = $qp->parse($self->{search_string}, '+') or 
    croak "error parsing query : $self->{search_string}";

  my $filter;

  eval {$filter = $self->{data}->compileFilter($parsedQ);} or
    croak("error in query : $@ ," . $qp->unparse($parsedQ) 
                                  . " ($self->{search_string})");

  # perform the search
  @{$self->{results}}{qw(records lineNumbers)} = 
    $self->{data}->fetchall(where => $filter);
  $self->{results}{count} = @{$self->{results}{records}};

  $self->end_search_hook;
  
  # VERY CHEAP way of generating regex for highlighting results
  my @words_queried = uniq(grep {length($_)>2} $self->words_queried);
  $self->{results}{wordsQueried} = join "|", @words_queried;
}


#----------------------------------------------------------------------
sub post_search { 
#----------------------------------------------------------------------
  my $self = shift;

  $self->sortAndSlice;
}


#----------------------------------------------------------------------
sub sortAndSlice { # sort results, then just keep the desired slice
#----------------------------------------------------------------------
  my $self = shift;

  delete $self->{results}{lineNumbers}; # not going to use those

  # sort results
  if ($self->{sortBy}) {
    eval {
      my $cmpfunc = $self->{data}->ht->cmp($self->{sortBy});
      $self->{results}{records} = [sort $cmpfunc @{$self->{results}{records}}];
    }
      or croak "sortBy : $@";
  }

  # restrict to the desired slice
  my $start_record = $self->param('start') || 0;
  my $end_record   = min($start_record + $self->{count} - 1,
			 $self->{results}{count} - 1);
  $self->{results}{records} = 
    [ @{$self->{results}{records}}[$start_record ... $end_record] ];

  # for user display : record numbers starting with 1, not 0 
  $self->{results}{start} = $start_record + 1;
  $self->{results}{end}   = $end_record + 1;


  # compute links to previous/next slice
  my $urlreq = "?S=" . $self->param('SS') .
               "&SFT=" . $self->param('SFT') .
	       "&sortBy=$self->{sortBy}" .
	       "&count=$self->{count}";
  my $prev_idx = $start_record - $self->{count};
     $prev_idx = 0 if $prev_idx < 0;
  my $next_idx = $start_record + $self->{count};

  $self->{results}{prev_link} = uri_escape("$urlreq&start=$prev_idx")
    if $start_record > 0;
  $self->{results}{next_link} = uri_escape("$urlreq&start=$next_idx")
    if $next_idx < $self->{results}{count};
}


#----------------------------------------------------------------------
sub display { # display results in the requested view
#----------------------------------------------------------------------
  my ($self, $view) = @_;

  my $tmpl_name = $self->tmpl_name($view);

  $self->{app}{tmpl}->process($tmpl_name, {self => $self, 
                                           found => $self->{results}})
    or croak $self->{app}{tmpl}->error();
}


#----------------------------------------------------------------------
sub empty_record { 
#----------------------------------------------------------------------
  my $self = shift;
  my $record = {};
  my $defaults = $self->{cfg}->get("fields_default");
  $record->{$_} = $defaults->{$_} foreach $self->{data}->headers;
  $self->{results} = {count => 1, records => [$record], lineNumbers => [-1]};
}




#----------------------------------------------------------------------
sub delete {
#----------------------------------------------------------------------
  my $self = shift;
  my $found = $self->{results};
  
  all {$self->can_do("delete", $_)} @{$found->{records}} or
    croak "No permission 'delete' for $self->{user}";

  my @to_delete = map {($_, 1, undef)} @{$found->{lineNumbers}};
  $self->{data}->splices(@to_delete);

  $self->{msg} = "Deleted:<br>";
  my @headers = $self->{data}->headers;
  foreach my $record (@{$found->{records}}) {
    my @values = @{$record}{@headers};
    $self->{msg} .= join("|", @values) . "<br>";
    $self->delete_record($record);
  }
}


sub delete_record {}


#----------------------------------------------------------------------
sub update {
#----------------------------------------------------------------------
  my $self = shift;
  my $found = $self->{results};
  my %upldFiles;
  my $dir = $self->{dir};

  all {$self->can_do("modif", $_)} @{$found->{records}} or
    croak "No permission 'delete' for $self->{user}";

  $self->fixAutoNum;
  $self->beforeUpdates;

  # for each record, prepare update instructions (@spliceArgs) and message
  $self->{msg} = "Updated:<br><br>";
  my @headers = $self->{data}->headers;
  my @spliceArgs;
  for (my $i = 0; $i < $found->{count}; $i++) {
    my $line_nb   = $found->{lineNumbers}[$i]; # will be -1 if empty_record
    my $record    = $found->{records}[$i];
    my $to_delete = $line_nb == -1 ? 0         # no previous line to delete
                                   : 1;        # replace previous line
    push @spliceArgs, $line_nb, $to_delete, $record;

    my $data_line = join("|", @{$record}{@headers});
    my $id = $record->{$headers[0]};
    $self->{msg} .= "<a href='?S=K_E_Y:$id'>Record $id</a>: $data_line<br>";
  }

  # do the updates
  eval {$self->{data}->splices(@spliceArgs)} or do {
    my $err = $@;
    $self->cancel_before_updates;
    croak $err;
  };

  $self->afterUpdates;
}


#----------------------------------------------------------------------
sub beforeUpdates { # 
#----------------------------------------------------------------------
  my $self = shift;

  foreach my $record (@{$self->{results}{records}}) {

    # copy defined CGI params into record ..
    foreach my $field ($self->{data}->headers) {
      my $val = $self->param($field);
      $record->{$field} = $val unless not defined $val;
    }

    # force username into user field (if any)
    my $userField = $self->{cfg}->get('fields_user');
    $record->{$userField} = $self->{user} if $userField;

    # force current time into time fields (if any)
    while (my ($k, $fmt) = each %{$self->{time_fields}}) {
      $record->{$k} = strftime($fmt, localtime);
    } 
  }
}


#----------------------------------------------------------------------
sub afterUpdates {
#----------------------------------------------------------------------
}


#----------------------------------------------------------------------
sub fixAutoNum { 
#----------------------------------------------------------------------
  my $self = shift;

  # if this is a new record
  if ($self->{cfg}->get('fields_autoNum') and $self->param('U') =~ /#/) {
    while ($self->{data}->fetchrow) {} # do nothing, just make sure autonum
                                       # gets updated
  }
}

#----------------------------------------------------------------------
sub can_do {
#----------------------------------------------------------------------
  my ($self, $action, $record) = @_;

  my $allow  = $self->{cfg}->get("permissions_$action");
  my $forbid = $self->{cfg}->get("permissions_no_$action") || "nobody";

  for ($allow, $forbid) {
    $_ = (not $_)                 # matches everybody if nothing specified
       || $self->user_match($_)   # or if acl list matches user name
       ||(   /\$(\S+)\b/i         # or if acl list contains a field name ...
	  && defined($record)                   # ... and got a specific record
          && defined($record->{$1})             # ... and field is defined
	  && $self->user_match($record->{$1})); # ... and field content matches
  }

  return $allow and not $forbid;
}



#----------------------------------------------------------------------
sub url { # give back various urls (to be used by templates)
#----------------------------------------------------------------------
  my ($self, $which) = @_;

  for ($which) {
    /add/      and return "$self->{url}?A";
    /all/      and return "$self->{url}?S=*";
    /home/     and return "$self->{url}?H";
    /download/ and return "$self->{url}?X";
    /\S/       and return "bad url arg : $_";
    return $self->{url};	# otherwise
  }
}

#----------------------------------------------------------------------
sub tmpl_name { # for a given operation, find associated template name
#----------------------------------------------------------------------
  my $self = shift;
  my $op   = shift;

  my $tmpl_name =  $self->{cfg}->get("template_$op") if $self->{cfg};
  $tmpl_name ||= "$self->{app}{appname}_$op.tt";
  return $tmpl_name;
}


#----------------------------------------------------------------------
sub print_help {
#----------------------------------------------------------------------
  print "sorry, no help at the moment";
}

#----------------------------------------------------------------------
sub param {
#----------------------------------------------------------------------
  my ($self, $p) = @_;

  my @vals = $self->{cgi}->param($p);
  return undef if not @vals;

  my $val = join(' ', @vals);	# join multiple values
  $val =~ s/^\s+//;		# remove initial spaces
  $val =~ s/\s+$//;		# remove final spaces
  return $val;
}





#----------------------------------------------------------------------
sub user_match {
#----------------------------------------------------------------------
  my $self = shift;
  my $list = shift;
  return ($list =~ /\b\Q$self->{user}\E\b/i);
}




######################################################################
#                            UTILITY FUNCTIONS                       #
######################################################################

#----------------------------------------------------------------------
sub uri_escape { # encode 
#----------------------------------------------------------------------
    my $uri = shift;
    $uri =~ s{([^;\/?:@&=\$,A-Za-z0-9\-_.!~*'()])}
             {sprintf("%%%02X", ord($1))         }ge;
    return $uri;
}







1;


__DATA__

=head1 NAME

File::Tabular::Web - turn a tabular file into a web application

=head1 INTRODUCTION

This is an Apache web application framework based on
L<File::Tabular|File::Tabular> and
L<Search::QueryParser|Search::QueryParser>.  It offers builtin
services for searching, displaying and updating a flat tabular
datafile.  It may run either under mod_perl Registry or under plain
old cgi-bin.

Setting up the framework just requires two directives within the
Apache configuration.  Once this is done, all the webmaster has to do
in order to build a new application is to supply the data (a tabular
.txt file) and run the helper script C<ftw_new_app.pl>, which
automatically builds configuration and template files for that
application.  These files can then be edited for specific adaptations.
No single line of Perl is needed, and the new URL becomes immediately
active, without webserver configuration nor restart.

For more advanced uses, application-specific Perl handlers can be
hooked up into the framework for performing particular tasks.
Furthermore, subclassing can be used for extending the builtin 
services. In particular, see the companion
L<File::Tabular::Web::Attachments|File::Tabular::Web::Attachments>
module, which provides services for attaching documents
and indexing them through  L<Search::Indexer|Search::Indexer>,
therefore providing a mini-framework for storing electronic documents.


=head1 QUICKSTART

=head2 Setting up the framework

Install the C<File::Tabular::Web> module in your local Perl site.

In your apache/cgi-bin (or apache/perl if running under mod_perl Registry) :
create a file named "ftw" containing 

   use File::Tabular::Web;
   File::Tabular::Web->process;

In your Apache configuration (httpd.conf), add directives :

  Action file-tabular-web /cgi-bin/ftw # (or /perl/ftw)
  AddHandler file-tabular-web .ftw

and restart the server.

Now any file ending with ".ftw" in your htdocs tree will be treated as
a File::Tabular::Web application. The handler will be called automatically
and will read configuration instructions in the ".ftw" file.
Therefore new applications can be installed without any further
changes in the Apache configuration.

Of course you can choose whatever name you like instead of "ftw" for file 
suffixes and for the two-lines script; "ftw" was suggested because it 
does not conflict with other common suffixes. 
Similarly, the C<file-tabular-web> handler name can be arbitrarily changed.


=head2 Setting up a particular application

We'll take for example a simple people directory application.
First create directory F<apache/htdocs/people>.

Export your list of people in a flat text file named
F<apache/htdocs/people/dir.txt>.
If you export from an Excel Spreadsheet, do NOT export as CSV format ; 
choose "text (tab-separated)" instead. The datafile should contain
one line per record, with a character like '|' or TAB as field 
separator, and field names on the first line 
(see L<File::Tabular|File::Tabular> for details).

Run the helper script

  perl ftw_new_app.pl --fieldSep \\t apache/htdocs/people/dir.txt

This will create in the same directory a configuration file C<dir.ftw>,
and a collection of HTML templates C<dir_short.tt>, C<dir_long.tt>,
C<dir_modif.tt>, etc. The C<--fieldSep> option specifies which
character acts as field separator (the default is '|');
other option are available, see

  perl ftw_new_app.pl --help

for a list.

The URL C<http:://your.web.server/people/dir.ftw>
is now available to access the application.
You may first test the default layout, and then customize
the templates to suit your needs.

Note : initially all files are placed in the same directory, because
it is simple and convenient; however, data and templates files
are not really web resources and therefore should not theoretically
belong to the htdocs tree. If you want a more structured architecture,
you may move these files to a different location, and specify
within the configuration how to find them (see instructions below).


=head1 WEB API

=head2 Phases of a request

Each request to this web application framework goes through the following
phases :

=over

=item B<initialisation phase> 

this is where the configuration file is read 

=item B<alias expansion> 

CGI parameters are inspected and alias-expanded into
specific handlers for the following phases

=item B<data connection> 

opening the data file

=item B<data preparation phase> 

building a result set, either from searching existing records,
or by building a new record. A first check of user access
rights may happen during this phase.

=item B<post-check phase> 

checking if the user has proper access rights to perform the
desired operation on the result set (this may involve inspecting
each record).

=item B<data manipulation phase> 

operations on the result set : deletions, updates, or just
sorting and slicing the results after a search.

=item B<display phase> 

presenting the results, most commonly through an HTML template
in TT2 format.

=back


Parameters to the Web request determine what will be performed
a each of these phases. I<Core parameters> directly program 
those phases; I<aliases> offer a shorter API where each
alias is translated into a collection of core parameters.

=head2 Core parameters

=head3 PRE

This specifies how to perform the data preparation phase. Usually this is
mapped to methods L</search>, L</search_key> or L</empty_record>; but
it is also possible to specifiy user-defined methods.

=head3 PC

This specifies how to perform the post-check phase (calling
C<< $self->can_do($self->param('PC')) >> do decide
whether or not the connected user has a right to do this operation). 

=head3 SS

Contains the search string.

=head3 OP

This specifies which operation will be performed
during  data manipulation phase. Builtin operations
are L</post_search>, L</delete> and L</update>.
Of course it is also possible to specifiy user-defined methods.


=head3 V

Name of the view (i.e. template) that will be used to display
the results.


=head2 Aliases

=head3 H

  http://myServer/some/app.ftw?H

Displays the homepage of the application (through template C<home.tt>).
Equivalent to 

  http://myServer/some/app.ftw?V=home

=head3 S

  http://myServer/some/app.ftw?S=<criteria>

Searches records matching the specified criteria, and displays them 
through the C<short.tt> template. Here are some example of search criteria :

  word1 word2 word3                 # records containing these 3 words anywhere
  +word1 +word2 +word3              # idem
  word1 word2 -word3                # containing word1 and word2 but not word3
  word1 AND (word2 OR word3)        # obvious
  "word1 word2 word3"               # sequence
  word*                             # word completion
  field1:word1 field2:word2         # restricted by field
  field1 == val1  field2 > val2     # relational operators (will inspect the
                                    #   shape of supplied values to decide
                                    #   about string/numeric/date comparisons)
  field~regex                       # regex

See L<Search::QueryParser> and L<File::Tabular> for 
more details.

Equivalent to 

  http://myServer/some/app.ftw?PRE=search&SS=<criteria>&OP=post_search&V=short


=head3 L

  http://myServer/some/app.ftw?L=<key>

Finds the record with the given key and displays it through the
C<long.tt> template.

Equivalent to 

  http://myServer/some/app.ftw?PRE=search_key&SS=<key>&V=long


=head3 M

  http://myServer/some/app.ftw?M=key

Finds the record with the given key and displays it through the
C<modif.tt> template (typically this will be a form
with an action to call the update URL (C<?U=key>).

Equivalent to 

  http://myServer/some/app.ftw?PRE=search_key&SS=<key>&V=modif


=head3 U

  http://myServer/some/app.ftw?U=<key>&field1=val1&field2=val2&...

Finds the record with the given key
and updates it with given field names and values.
Of course these can be (and even should be) passed through
POST method instead of GET.
After update, displays an update message through the C<msg.tt> template.

Equivalent to 

  http://myServer/some/app.ftw?PRE=search_key&SS=<key>&OP=update


=head3 A

  http://myServer/some/app.ftw?A

Displays a form for creating a new record, through the 
C<modif.tt> template. Fields may be filled by default values
given in the configuration file.

Equivalent to 

  http://myServer/some/app.ftw?PRE=empty_record&PC=add&V=modif


=head3 D

  http://myServer/some/app.ftw?D=<key>

Deletes record with the given key.
After deletion, displays an update message through the C<msg.tt> template.

Equivalent to 

  http://myServer/some/app.ftw?PRE=search_key&SS=<key>&OP=delete

=head3 X

  http://myServer/some/app.ftw?X

Display all records throught the C<download.tt> template.

Equivalent to 

  http://myServer/some/app.ftw?V=download

=head2 Other URL possibilities

  http://myServer/some/app.ftw?PRE=search&SS=<criteria>&OP=delete
  
  http://myServer/some/app.ftw?PRE=search&SS=<criteria>&<field>=<val>&OP=update




=head1 WRITING TEMPLATES

This section assumes that you already know how to write
templates for the Template Toolkit (see L<Template>).

The path for searching templates includes the application directory
(where the configuration file resides) and the directory
specified within the configuration file by parameters
C<< [fixed]tmpl_dir >> or C<< [default]tmpl_dir >>, or, by
default, C<Apache/lib/tmpl/tdb>.

Values passed to templates are as follows :

=over

=item C<self>

handle to the C<File::Tabular::Web> object; from there you can access
C<self.cfg> (configuration information), C<self.cgi> (CGI request object)
and C<self.msg> (last message).


=item C<found>

structure containing the results. Fields within this structure are :

=over

=item C<count>

how many records were retrieved

=item C<records>

arrayref containing a slice of records

=item C<start>

index of first record in the returned slice

=item C<end>

index of last record in the returned slice

=item C<next_link>

href link to the next slice of results (if any)

=item C<prev_link>

href link to the previous slice of results (if any)

=back



=back




=head1 PUBLIC METHODS

=head2 C<process>

  File::Tabular::Web->process;

This is the main entry point into the module. It creates a new request
object, initializes it from information passed through the URL and
through CGI parameters, and processes the request. In case of error,
and HTML error page is generated.

=head1 PRIVATE METHODS

=head2 C<new>

Creates a new C<File::Tabular::Web> object, which represents a web
request. Reads PATH_INFO and CGI parameters, 
and loads the configuration directives for that web application.

=head2 C<initialize_request>

Set up some general properties for the request, from information
collected from configuration directives.


=head2 C<new_app>

Creates a Perl structure representing a ftw web application,
after having read the configuration directives.

=head2 C<read_config>

Set up L<AppConfig|AppConfig> and read the configuration file.

=head2 C<find_operation>

Requests are mapped to sequences of "operations". An operation 
corresponds either to an internal method, or to a loaded function.
So C<find_operation> finds out which.

=head2 C<dispatch_request>

Decides which sequence of operations should be called, and call them.

=head2 C<expand_aliases>

An "alias" is a single-letter CGI argument that acts as a shortcut
for a sequence of operations. This method inspects CGI arguments
and expands the first alias found.

=head2 C<open_data>

Retrieves the name of the datafile, decides whether it
should be opened for readonly or for update, and 
creates a corresponding L<File::Tabular|File::Tabular> object. 
The datafile may be cached in memory if directive C<useFileCache> is
activated.


=head1 CONFIGURATION FILE

The configuration file will be parsed by L<Appconfig|Appconfig>.
This file format supports comments (starting with C<#>), 
continuation lines (through final C<\>), "heredoc" quoting
style for multiline values, and section headers similar
to a Windows INI file. All details about the configuration
file format can be found in L<Appconfig::File>.

Below is the list of the various recognized sections and parameters.

=head2 Global section

The global section (without any section header) can contain
general-purpose parameters that can be retrieved later from 
the viewing templates through C<< [% self.cfg.<param> %] >>;
this is useful for example for setting a title or other
values that will be common to all templates.

=over

=item useFileCache

If true, the whole datafile will be slurped into memory and reused
across requests.



=back

=head2 [fixed] / [default]

The B<fixed> and B<default> sections contain some parameters
that control the behaviour of the application ; it is your choice
to either put them in the B<fixed> section (values will never change)
or to put them in the B<default> section (default values can be 
overriden by CGI parameters).

The parameters are :

=over

=item C<< max >>

Maximum number of records handled in searches (records above that number
will be dropped).

=item C<< count >>

Size of a result slice (number of records displayed at a time
when presenting results of a search).

=item C<< sortBy >>

Sort criteria, like for example C<< someField: -num, otherField: alpha >>.
See L<File::Tabular/search> for the exact syntax of 
sort specifications.


=back


=head2 [permissions]

The B<permissions> section specifies access control rights for the
applications. For each entry listed below, you can give a list of users
[or groups], separated by commas or spaces : these are the "permanent"
rights, valid for all data records. In addition, rights can be granted
on a per-record basis : writing C<< $fieldname >> (starting
with a literal dollar sign) means that 
users can access records in which the content of  C<< fieldname >>
matches their username. 

Here are the possible entries for positive rights :

=over

=item C<< add >>

Right to add new records.

=item C<< delete >>

Right to delete records.

=item C<< modif >>

Right to modify records.

=item C<< search >>

Right to search records.

=back

Each of the entries above also has a corresponding entry for negative
rights, written C<< no_add >>, C<< no_delete >>, etc.; so that you can
selectively prevent some users to perform specific actions.


=head2 [fields]

=over

=item C<< indexedDocNum <field> >>

Name of the field which holds the I<document Number>.

=item C<< indexedDocContent = sub {my ($self, $record) = @_; ...; return $buf;} >>

Handler to get the textual content from an attached indexed document.
The handler should return a buffer with the textual representation of 
the document content.

=item C<< indexedDocFile <field> >>

Name of the field which holds the I<document filename>.

=item C<< upload <field> >>

Just declares C<< field >> to be an upload field.

=item C<< upload <field> = sub {my ($self, $record, $upldClientName) = @_; ...; return $newname;} >>

Declares C<< field >> to be an upload field, and supplies a hook to choose
the server-side name of the uploaded file. The supplied C<< sub >> should 
return a pathname.

=item C<< time <field> = <format>  >>

Declares C<< field >> to be a I<time field>, which means that whenever
a record is updated, the current local time will be automatically
inserted in that field. The I<format> argument will be
passed to L<POSIX strftime()|POSIX/strftime>. Ex :

  time DateModif = %d.%m.%Y    
  time TimeModif = %H:%M:%S

=item C<< user = <field>  >>

Declares C<< field >> to be a I<user field>, which means that whenever
a record is updated, the current username will be automatically
inserted in that field.

=item C<< autonum <field>  >>

Activates autonumbering for new records ; the number will be
stored in the given field.

=item C<< default <field> = <value> >>

Default values for some fields ; will be inserted into new records.

=back

=head2 [template]

This section specifies where to find templates for various views.
The specified locations will be looked for either in the
current directory, or in C<< <apache_dir>/lib/tmpl/app >>.

=over

=item short

Template for the "short" display of records (typically 
a table for presenting search results). 

=item long

Template for the "long" display of records (typically 
for a detailed presentation of a single record ). 

=item modif

Template for editing a record (typically this will be a form
with an action to call the update URL (C<?U=key>).

=item msg

Template for presenting special messages to the user 
(messages after a record update or deletion, or error messages).

=item home

Homepage for the application.

=back



=head2 [handlers]

In this section, you can insert your own code for various phases
of the request cycle. This code will be B<eval>'d and can
then be called in the URLs.

=over

=item C<< prepare <handlerName> = sub {my $self=shift; ...} >>

Registers a handler for the I<data preparation> phase.
The handler can then be called by passing
a B<PRE> parameter with value B<handlerName>.


=item C<< update before = sub {my $self=shift; my $r=shift; ...} >>

Registers a handler that will be called automatically
before updating a record. The record is passed as second argument.


=back

=head2 [filters]


Specifies filters for the Template Toolkit.
Each filter takes the form

  filter_name = function_name, dynamic_flag

where C<filter_name> is the name seen within templates, 
C<function_name> is the Perl function implementing the filter,
and C<dynamic_flag> is either 0 or 1 depending on whether the filter
is static or dynamic (see L<Template::Filters>).

=head2 [perl]

The C<perl> provides several ways to dynamically load code into the
current interpreter. If running under mod_perl, be sure to know what
you are doing, since the loaded code might interfere with code already
loaded into the server. Also beware that packages or functions loaded
in this way will not be recognized properly by 
L<Apache::Reload|Apache::Reload>, so you will need to fully restart 
Apache in case of any change in the code.

=over

=item C<< class My::File::Tabular::Web::Subclass >>

Will dynamically load the specified module and use it as 
class for the current C<app> object.


=item C<< use Some::Module qw/import list/ >>

Will dynamically load the specified module. An import list may
be specified, i.e. C<< use Some::Module qw/foo :bar/ >>.


=item C<< require some/file.pl >>


=item C<< eval "some code" >>


=back




=head1 PUBLIC METHODS

=over


=item C<< process([$cgi]) >>

This is the main public method. It creates a 
C<File::Tabular::Web> instance and processes the request
specified in CGI parameters, as explained below.

The optional C<$cgi> argument should be an instance of L<CGI>;
if you supply none, it will be created automatically.


=item B<< can_do($action, [$record]) >>

This method is meant to be called from within templates; it
tells whether the current user has permission to do 
C<$action> (which might be 'edit', 'delete', etc.).
See explanations below about how permissions are specified
in the initialisation file.
Sometimes permissions are setup in a record-specific way
(for example one data field may contain the names of 
authorized users); the second optional argument 
is meant for those cases, so that C<can_do()> can inspect the current
data record.

=item B<< url([$which]) >>

This method is meant to be called from within templates.
It returns the url to the current web application.
The optional argument C<$which> specifies a particular
entry point into the application :

=over

=item add

create a new record

=item all

display all records

=item home

display homepage

=item download

display "download page"

=back

=back


=head1 PRIVATE METHODS

Below are methods for internal use within the class. 
Normally there is no reason to call them directly ; 
they are documented just in case you should ever 
redefine them in subclasses.

=over

=item C<< new([$cgi]) >>

Creates a new instance of C<< File::Tabular::CGI >>, associates it 
with a C<< CGI >> object (either newly created or received as optional
argument) and with a C<< Template >> object, 
and reads the configuration file.

=item C<< read_config() >>

Reads configuration file in C<< Appconfig >> format.
Complains from C<< Appconfig >> about undefined variables
are discarded; other errors are propagated to the user.

=cut











=back

=head1 TODO

  - can_do : deal with groups GE-JUSTICE
  - print doc if no path_info
  - path to global templates : option
  - find better security model for action 'add'
  - doc : show example of access to fileTabular->mtime->{hour}
  - server-side record validation using "F::T where syntax" (f1 > val, etc.)
    or using code hook
  - cache cfg if running under mod_perl Registry
  - generalize empty_record (design config params)
  - template for $self->delete (either default or user-supplied)
  - support for path given without PATH_INFO : still useful ??
      context : 1) mod_perl ; 2) Apache handler (cgi-bin) ; 3) cgi-bin/app/path
  - config property for allowing/disallow multiple Delete or multiple Update
  - view abstraction for direct display of attached doc 
  - update : how to handle name conflicts : field names / builtin 
    names (sortBy, score, excerpts, etc.)
  - better abstraction for PRE handler according to U=.. (build/search)
  - remove direct link to GE::Justice::AnyDoc2Txt, need abstracted converter
  - more clever generation of wordsQueried in search
  - remove direct call to $upld_field/...
  - enqueue : remove GE::Justice dependencies (FichierWord, etc.)





