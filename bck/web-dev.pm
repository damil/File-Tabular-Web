package File::Tabular::Web;

our $VERSION = "0.01"; 

=head1 NAME

File::Tabular::Web - turn a tabular file into a CGI web application

=head1 INTRODUCTION

This is a web application framework based on L<CGI> and L<File::Tabular>. 
Given a data file and a collection of viewing templates, 
it supplies services for searching, displaying and updating the
data, possibly linked with attached documents.
Attached documents can be indexed with L<Search::Indexer>,
so that search queries will find information either in the
metadata (fields within the tabular file) or in the fulltext.

In order to build a new application, all the webmaster has to do is
supply the data (a tabular .txt file), supply a configuration file
(possibly empty), and supply HTML templates (written in
L<Template|Template Toolkit (TT2)> format) ... so far no single line
of Perl is needed. However, application-specific Perl handlers can be
hooked up into the framework if you want to perform particular tasks
(like validating data, dealing with attached documents on the server,
etc.)



=head1 SYNOPSIS

=head2 Setting up the framework

In your apache/cgi-bin (or apache/perl if running under mod_perl Registry) :
create a file named "tdb" containing 

   use File::Tabular::Web;
   File::Tabular::Web->process;

In your Apache configuration (httpd.conf) :

  Action file-tabular-web /cgi-bin/tdb # (or /perl/tdb)
  AddHandler file-tabular-web .tdb

Thus, any file ending with ".tdb" in your htdocs tree will be treated as
a File::Tabular::Web application. The handler will be called automatically
and will read configuration instructions in the ".tdb" file.

Of course you can choose whatever name you like instead of "tdb" for file 
suffixes and for the two-lines script; "tdb" was suggested because it 
evokes a "Text DataBase" and does
not conflict with other common suffixes. 
Similarly, the C<file-tabular-web> handler name can be arbitrarily changed.


=head2 Setting up a particular application

We'll take for example a simple people directory application.
First create directory "apache/htdocs/people". 

=head3 Data file and configuration file

Export your list of people in a flat text file. If you export from
an Excel Spreadsheet, do NOT export as CSV format ; choose 
"text (tab-separated)" instead.


  [fixed]
  count = 30 # size result slices 
  fieldSep = '\t'
  .. CONTINUE HERE


  ..


=head3 Views

.. templates for short, long, modif, etc.


=head1 REQUEST HANDLING

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



=head1 CONFIGURATION FILE

The configuration file will be parsed by B<Appconfig>.
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
on a per-record basis : writing C<< $fieldname >> means that 
users can access records in which the content of  C<< $fieldname >>
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
passed to L<POSIX/strftime|POSIX strftime(). Ex :

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
current directory, or in C<< <apache_dir>/lib/tmpl >>.

=over

=item short

Template for the "short" display of records (typically 
a table for presenting search results). 

=item long

Template for the "long" display of records (typically 
for a detailed presentation of a single record ). 

=item modif

Template for editing a record (typically this will be a form
with an action to call C<< [% self.url('modif') %] >>.

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


=cut


use strict;
use warnings;
no warnings 'uninitialized';
use locale;

use CGI;
use Template;
use Search::Indexer;
use Search::QueryParser;
use File::Tabular;
use AppConfig qw(:argcount);
use File::Basename;
use lib '../..';
use GE::Justice::AnyDoc2Txt;
use Time::HiRes 'gettimeofday';
use POSIX 'strftime';


my %fileCache;
my %objectCache;


=head1 PUBLIC METHODS

=over


=item C<< process([$cgi]) >>

This is the main public method. It creates a 
C<File::Tabular::CGI> instance and processes the request
specified in CGI parameters, as explained below.

The optional C<$cgi> argument should be an instance of L<CGI>;
if you supply none, it will be created automatically.


=cut


######################################################################
sub process { # create a new instance and immediately process request
######################################################################
  my $self = new(@_);
  $self->dispatchRequest;
#   printf STDERR "FILES %s\n", join(";", keys %fileCache);
#   printf STDERR "OBJECTS %s\n", join(";", keys %objectCache);
}


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

=cut

######################################################################
sub can_do {
######################################################################
  my ($self, $action, $record) = @_;

  my $can    = $self->{cfg}->get("permissions_$action");
  my $cannot = $self->{cfg}->get("permissions_no_$action") || "nobody";

  for ($can, $cannot) {
    $_ = (not $_) ||              # matches everybody if nothing specified
         $self->userMatch($_) ||  # or if acl list matches user name
         (/\$(\S+)\b/i &&         # or if acl list contains a field name ...
	  defined($record) && defined($record->{$1}) &&
	  $self->userMatch($record->{$1})); # ... and field content matches
  }

  return $can and not $cannot;
}


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

=cut

######################################################################
sub url { # give back various urls (to be used by templates)
######################################################################
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

=back


=head1 PRIVATE METHODS

Below are methods for internal use within the class. 
Normally no reason to call them directly ; 
they are documented just in case you should ever 
redefine them in subclasses.

=over

=item C<< new([$cgi]) >>

Creates a new instance of C<< File::Tabular::CGI >>, associates it 
with a C<< CGI >> object (either newly created or received as optional
argument) and with a C<< Template >> object, 
and reads the configuration file.

=cut


######################################################################
sub new { # fake constructor (using cache)
######################################################################
  my $class = shift;
  my $cgi =  shift;

  $cgi = CGI->new() if not $cgi;
  my $path_translated = $cgi->path_translated;

  my $self = $objectCache{$path_translated} ||= $class->real_new($cgi);

  # update $self with current request 
  $self->{cgi}  = $cgi;
  $self->{user} = $cgi->remote_user() || "Anonymous";
  $self->{url}  = $cgi->url(-path => 1);
  $self->{msg}  = undef;

  # setup some general parameters
  my %builtin_defaults = (max => 500,                # max records retrieved	
			  count => 50,               # how many records in a single slice
			  sortBy => "",	             # default sort criteria
			 );
  while (my ($k, $v) = each %builtin_defaults) {
    $self->{$k} = $self->{cfg}->get("fixed_$k")   || # fixed value in config, or
                  $self->getCGI($k)               || # given in CGI param, or 
		  $self->{cfg}->get("default_$k") || # default value in config, or
                  $v;                                # builtin default
  }

  return $self;
}



######################################################################
sub real_new { # real constructor
######################################################################
  my $class = shift;
  my $cgi =  shift;

  my $self = {};
  bless $self, $class;

  # get dir and name of config file (from path_info)
  @{$self}{qw(tdbname dir suffix)} = 
    fileparse($cgi->path_translated, qr/\.[^.]*$/);

  # read configuration file
  $self->{cfg} = $self->getConfig;

  $self->{tmpl_dir} = $self->{cfg}->get("fixed_tmpl_dir") 
                   || $self->{cfg}->get("default_tmpl_dir") 
		   || "lib/tmpl/tdb";

  $self->{upload_fields} = $self->{cfg}->get('fields_upload'); # hashref
  $self->{time_fields} = $self->{cfg}->get('fields_time'); # hashref
  $self->{dataFile} = $self->{dir} . $self->{cfg}->get("dataFile");
  $self->{queueDir} = $self->{cfg}->get('fixed_queueDir'); 

  # find apache directory, one level above document_root
  ($self->{apache_dir}) = ($ENV{DOCUMENT_ROOT} =~ m[(.*)[/\\]]); 

  # initialize template toolkit object
  $self->{tmpl} = Template->new(
	{INCLUDE_PATH => [$self->{dir}, "$self->{apache_dir}/$self->{tmpl_dir}"],
	 FILTERS      => {htmlDecis => [\&decisHtmlFilterFactory, 1],
			  autoDecisLinks => \&autoDecisLinks}});

  return $self;
}

=item C<< getConfig() >>

Reads configuration file in C<< Appconfig >> format.
Complains from C<< Appconfig >> about undefined variables
are discarded; other errors are propagated to the user.

=cut

######################################################################
sub getConfig { # read configuration file through Appconfig
######################################################################
  my $self = shift;

  # TODO : under mod_perl, cfg could be put into a global cache 
  my $cfg = AppConfig->new({
	CREATE => 1, 
	ERROR => sub {my $fmt = shift;
		      $self->error(sprintf("AppConfig : $fmt\n", @_))
			unless $fmt =~ /no such variable/;
		    },
        GLOBAL => {ARGCOUNT => ARGCOUNT_ONE}});

  $cfg->define(
     fieldSep => {DEFAULT => "|"}, 
     dataFile => {DEFAULT => "$self->{tdbname}.txt"},
     fields_upload    => {ARGCOUNT => ARGCOUNT_HASH},
     fields_default   => {ARGCOUNT => ARGCOUNT_HASH},
     fields_time      => {ARGCOUNT => ARGCOUNT_HASH},
     handlers_prepare => {ARGCOUNT => ARGCOUNT_HASH},
     handlers_update  => {ARGCOUNT => ARGCOUNT_HASH},
     );

  my $configFile = "$self->{dir}$self->{tdbname}$self->{suffix}";
  $cfg->file($configFile) or $self->error("(AppConfig) open $configFile : $^E");
  return $cfg;
}


######################################################################
sub dispatchRequest { # look at CGI args and choose appropriate handling
######################################################################
  my $self = shift;

  $self->expandAliases;
  $self->openData;

  # Data preparation phase
  my $pre = $self->getCGI('PRE');
  for ($pre) {
    /build/   	 and do {$self->buildEmptyRecord;       last};
    /search/	 and do {$self->search;                 last};
    /key/	 and do {$self->searchKey;              last};
    /^$/	 and last;

    # otherwise
    my $code = $self->{cfg}->get('handlers_prepare')->{$_}
      or $self->error("no prepare handler for '$_'");
    my $handler = eval $code or $self->error("prepare handler for '$_' : $@");
    $handler->($self);
  }

  # Post-check for proper access rights
  $self->postCheckRights;

  # Data manipulation / presentation phase
  my $op = $self->getCGI('OP');
  for ($op) {
    /delete/   	 and do {$self->delete;                  last};
    /update/   	 and do {$self->update;                  last};
    /postSearch/ and do {$self->postSearch;              last};
    /^$/	 and last;
    $self->error("dispatchRequest : unknown operation : '$_'"); # otherwise
  }


  # Display phase
  my $view = $self->getCGI('V');
  $view = 'msg' if $self->{msg};
  for ($view) {
    /redirect/ and do {print $self->{cgi}->redirect($self->getCGI('DEST')); last;};
    #otherwise
    $self->display($view);
  }
}

######################################################################
sub expandAliases { # normalize request, expanding aliases into CGI params
######################################################################
  my $self = shift;

  $self->{cgi}->param(V => 'home') unless $self->getCGI('V'); # default value

  # HACK : choose PRE handler, empty record if param contains '#' (autonum)
  # THIS IS GE::Justice SPECIFIC CODE, NEED TO GENERALIZE
  my $U_PRE = ($self->getCGI('U') =~ /#/) ? "build" : "key";

  my %aliases = (
     S => "SS=%s&PRE=search&PC=read&OP=postSearch&V=short", # search and display "short" view
     L => "SS=%s&PRE=key&PC=read&OP=&V=long",    # display "long" view of one single record
     M => "SS=%s&PRE=key&PC=modif&OP=&V=modif",   # display modify view (form for update)
     A => "SS=&PRE=build&PC=add&OP=&V=modif",  # add new record
     X => "SS=&PRE=&OP=&PC=search&V=download",        # display all records in "download view"
	     # NOTE : we don't set S => "*", this would be inefficient. Instead, 
	     # rows will be fetched from within the download template, i.e.
	     #  [% WHILE row = tdb.data.fetchrow %] ... display data row
     D => "SS=%s&PRE=key&OP=delete&V=",    # delete found records
     U => "SS=%s&PRE=$U_PRE&OP=update&V=",    # update
     H => "SS=&PRE=&OP=&V=home",         # display home page
     F => "SS=Decision:%s&PRE=search&PC=read&OP=&V=long",   # display attached file
  );

  while (my ($letter, $alias) = each %aliases) { # try each alias letter
    next if not defined $self->{cgi}->param($letter); 
    foreach my $newParam (split(/&/, sprintf($alias, $self->getCGI($letter)))) {
      $self->{cgi}->param(split(/=/, $newParam, -1));
    }
    last;
  }
}

######################################################################
sub openData { # open File::Tabular object on data file
######################################################################
  my $self = shift;

  my $openString = $self->{dataFile};
  my @openParams;

  # TODO : cleaner way to set options

  my $options = {
       preMatch      => $self->{cfg}->get('preMatch'),
       postMatch     => $self->{cfg}->get('postMatch'),
       autoNumField  => $self->{cfg}->get('fields_autoNum'),
       avoidMatchKey => $self->{cfg}->get('avoidMatchKey'),
       fieldSep      => $self->{cfg}->get('fieldSep'),
       recordSep     => $self->{cfg}->get('recordSep')
  };

  my $jFile = $self->{cfg}->get('journal');
  $options->{journal} = "$self->{dir}$jFile" if $jFile;


  if ($self->getCGI("OP") =~ /delete|update/) {
    @openParams = ("+< $openString");
  }
  elsif ($self->{cfg}->get('useFileCache')) {

    # get file last modification time
    my $mtime = (stat $openString)[9] or 
      $self->error("couldn't stat $openString");

    # delete cache entry if too old
    if ($fileCache{$openString} &&  
	  $mtime > $fileCache{$openString}->{mtime}) {
      delete $fileCache{$openString};	              
    }

    # create cache entry if necessary
    $fileCache{$openString} ||= do {
      
      open my $fh, $openString or 
	$self->error("open $openString : $^E");
      local $/ = undef;
      my $content = <$fh>;	# slurps the whole file into memory
      close $fh;
      {mtime => $mtime, content =>$content}; # return from do{} block
    };

    # will open from the memory copy
    @openParams = ('<', \$fileCache{$openString}->{content});
  }
  else {
    @openParams = ($openString);
  }

  $self->{data} = new File::Tabular(@openParams, $options) or
    $self->error("open @openParams : $^E");
}

######################################################################
sub searchKey { # search one single record
######################################################################
  my $self = shift;

  my $query = "K_E_Y:" . $self->getCGI('SS');
  my ($records, $lineNumbers) = $self->{data}->fetchall(where => $query);
  my $count = @$records;
  $self->{results} = {count => $count, 
		      records=>$records, 
		      lineNumbers=>$lineNumbers};
}

######################################################################
sub search { # search records and display results
######################################################################
  my $self = shift;

  my $search_string = $self->getCGI('SS');
  my $search_fulltext = $self->getCGI('SFT');
  my $docNumField;		# field holding indexed document numbers


  my @wordsQueried = ("$search_string $search_fulltext" =~ m([\w/]+)g);

  my $LOG;

  open $LOG, ">> $self->{dataFile}.request.log" or 
    $self->error("open >> $self->{dataFile}.request.log : $^E") 
      if $self->{cfg}->get('log_requests');

  print $LOG (scalar localtime), " [$search_string] [$search_fulltext] $self->{user}\n" if $LOG;

  $self->can_do("search") or 
    $self->error("no 'search' permission for $self->{user}");

  my $fulltext_result = undef;
  $self->{results} = {count => 0, records => [], lineNumbers => []};

  if ($search_fulltext) {
    $docNumField = $self->{cfg}->get('fields_indexedDocNum') or
      $self->error("missing [fields]indexedDocNum in configuration file");
    my $docNumColumn = $self->{data}->ht->{$docNumField} or
      $self->error("invalid [fields]indexedDocNum in configuration file");

    $self->{indexer} ||= new Search::Indexer(
       dir          => $self->{dir},
       preMatch     => $self->{cfg}->get('preMatch'),
       postMatch    => $self->{cfg}->get('postMatch')
    );
    $fulltext_result = $self->{indexer}->search($search_fulltext, "true");

    print $LOG (scalar localtime), " END FULLTEXT [$search_fulltext] \n"  if $LOG;
    print $LOG "REGEX : $fulltext_result->{regex}\n"  if $LOG;

    if ($fulltext_result){ # nonempty results
      $self->{results}{killedWords} = join ", ", @{$fulltext_result->{killedWords}};
      $self->{results}{regex} = $fulltext_result->{regex};

      my $oldSS = $search_string;
      my $tmp = join "|", keys %{$fulltext_result->{scores}}
	or return; # no scores, no results
      my $FS = $self->{data}{fieldSep};

      $search_string = "$docNumField ~ '^(?:$tmp)\$'";
      # optimize if $docNumField is the first field
      $search_string = "~'^(?:$tmp)(?:\\Q$FS\\E|\$)'" if $docNumColumn == 1;
      $search_string .= " AND ($oldSS)" if $oldSS;
    }
  }

  return if $search_string =~ /^\s*$/; # no query, no results

  my $qp = new Search::QueryParser;

  # compile query with an implicit '+' prefix in front of every item 
  my $parsedQ = $qp->parse($search_string, '+') or 
    $self->error("error parsing query : $search_string");
  my $filter;

  eval {$filter = $self->{data}->compileFilter($parsedQ);} or
    $self->error("error in query : $@ ," . $qp->unparse($parsedQ) . " ($search_string)");

  # perform the search
  @{$self->{results}}{qw(records lineNumbers)} = 
    $self->{data}->fetchall(where => $filter);
  $self->{results}{count} = @{$self->{results}{records}};

  print $LOG (scalar localtime), " END SEARCH [$search_string] \n"  if $LOG;

  # merge scores into results 
  $self->{data}->ht->add('score'); # new field for storing 'score'
  if ($search_fulltext) {
    foreach my $r (@{$self->{results}{records}}) {
      my $docId = $r->{$docNumField};
      $r->{score} = $fulltext_result->{scores}{$docId};
    }
    $self->{sortBy} ||= "score : -num";
  }


  # VERY CHEAP way of generating regex for doc display
  $self->{results}{wordsQueried} = join "|", grep {length($_)>2} @wordsQueried;

}


######################################################################
sub postSearch { 
######################################################################
  my $self = shift;


  # affichage direct d'un document attaché
  # TODO : this code should probably go elsewhere
  my $doc_param = $self->getCGI('doc');
  if ($doc_param and $self->{results}{count} == 1) {
    my $fileUrl = $self->{cgi}->path_info;
    $fileUrl =~ s(/[^/]+$)(/$doc_param/$self->{results}{records}[0]{$doc_param});
    $fileUrl =~ s/(doc|rtf)$/html/i;
    $self->{cgi}->param(V => "redirect"); # for "dispatchRequest"
    $self->{cgi}->param(DEST => $fileUrl); # for "dispatchRequest"
    return;
  }

  $self->sortAndSlice;
  $self->addExcerpts;
}


######################################################################
sub sortAndSlice { # sort results, then just keep the desired slice
######################################################################
  my $self = shift;

  delete $self->{results}{lineNumbers}; # not going to use those

  # sort results
  if ($self->{sortBy}) {
    eval {
      my $cmpfunc = $self->{data}->ht->cmp($self->{sortBy});
      $self->{results}{records} = [sort $cmpfunc @{$self->{results}{records}}];
    }
      or $self->error("sortBy : $@");
  }

  # restrict to the desired slice
  my $start_record = $self->getCGI('start') || 0;
  my $end_record = min($start_record + $self->{count} - 1,
		       $self->{results}{count} - 1);
  $self->{results}{records} = 
    [ @{$self->{results}{records}}[$start_record ... $end_record] ];

  # for user display : record numbers starting with 1, not 0 
  $self->{results}{start} = $start_record + 1;
  $self->{results}{end}   = $end_record + 1,

  my $urlreq = "?S=" . $self->getCGI('SS') .
               "&SFT=" . $self->getCGI('SFT') .
	       "&sortBy=$self->{sortBy}" .
	       "&count=$self->{count}";
  if ($start_record > 0) {	
    my $prev_idx = $start_record - $self->{count};
    $prev_idx = 0 if $prev_idx < 0;
    $self->{results}{prev_link} = uri_escape("$urlreq&start=$prev_idx");
  }
  if ((my $next_idx = $start_record + $self->{count}) < $self->{results}{count}) { 
    $self->{results}{next_link} = uri_escape("$urlreq&start=$next_idx");
  }
}

######################################################################
sub addExcerpts { # add text excerpts from attached files
######################################################################
  my $self = shift;
  return unless $self->getCGI('SFT'); # nothing to do if no fulltext

  $self->{data}->ht->add('excerpts'); # need new field in the Hash::Type

  my $code = $self->{cfg}->get("fields_indexedDocContent") or
    $self->error("missing [fields] indexedDocContent in config file");
  my $handler = eval $code or 
    $self->error("indexedDocContent handler : $@");

  foreach my $r (@{$self->{results}{records}}) {
    my $buf = $handler->($self, $r);
    my $excerpts = $self->{indexer}->excerpts($buf, $self->{results}->{regex});
    $r->{excerpts} = join(' / ', @$excerpts);
  }
}

######################################################################
sub display { # display results in the requested view
######################################################################
  my ($self, $view) = @_;

  my $tmplName = $self->tmplName($view);
  $self->{tmpl}->process($tmplName, {self => $self, found => $self->{results}})
    or $self->error($self->{tmpl}->error());
}


######################################################################
sub buildEmptyRecord { 
######################################################################
  my $self = shift;
  my $record = {};
  my $defaults = $self->{cfg}->get("fields_default");
  $record->{$_} = $defaults->{$_} foreach $self->{data}->headers;
  $self->{results} = {count => 1, records => [$record], lineNumbers => [-1]};
}

######################################################################
sub delete {
######################################################################
  my $self = shift;
  my $found = $self->{results};
  
  foreach my $record (@{$found->{records}}) {
    $self->error("No permission 'delete' for $self->{user}")
      if not $self->can_do("delete", $record);
  }

  eval {$self->{data}->splices(map {($_, 1, undef)} @{$found->{lineNumbers}})}
    or $self->error("File::Tabular::delete  : $@"); 

  my $msg = "Deleted:<br>";
  foreach my $record (@{$found->{records}}) {
    $msg .= join("|", @{$record}{$self->{data}->headers}) . "<br>";

    # suppression des éventuels fichiers associés à la ligne détruite
  
    foreach my $upld (keys %{$self->{upload_fields}}) {
      my $filename = $record->{$upld};
      next if not $filename;
      my $r = unlink("$self->{dir}$upld/$filename");
      $msg .= "Le fichier associé $filename " . 
	($r ? "a été supprimé<BR>" : "n'a pas pu être supprimé<BR>");
    }
    $self->enqueue("del", $record);
  }
  $self->{msg} = $msg;
}

######################################################################
sub update {
######################################################################
  my $self = shift;
  my $found = $self->{results};
  my %upldFiles;
  my $dir = $self->{dir};

  foreach my $record (@{$found->{records}}) {
    $self->error("No permission 'modif' for $self->{user}")
      if not $self->can_do("modif", $record);
  }

  $self->fixAutoNum;

  $self->{msg} = "Updated:<br><br>";

  $self->beforeUpdates;

  # now update the records
  my @spliceArgs;
  for (my $i = 0; $i < $found->{count}; $i++) {
    my $lineNo = $found->{lineNumbers}[$i];
    defined($lineNo) or 
      $self->error("bad line Number building splices, i=$i, count=$found->{count}");
    my $deleteLine = $lineNo > -1 ? 1 : 0; # lineNo == -1 means "append"
    push @spliceArgs, $lineNo, $deleteLine, $found->{records}[$i];
  }
  eval {$self->{data}->splices(@spliceArgs)} or do {
    my $err = $@;
    unlink("$dir$_.new") foreach keys %{$self->{results}{upldFiles}};
    $self->error("update : $err");
  };

  my @headers = $self->{data}->headers;
  foreach my $record (@{$found->{records}}) {
    $self->{msg} .= join("|", @{$record}{@headers}) . "<br>";

    my $id = $record->{Id}; # TODO : generaliser 
    $self->{msg} .= "<a href='?S=K_E_Y:$id'>Fiche $id</a><br>";
  }

  $self->afterUpdates;

}


######################################################################
sub beforeUpdates { # 
######################################################################
  my $self = shift;
  my $dir = $self->{dir};

  my $handler = undef;
  my $handlers = $self->{cfg}->get('handlers_update');

  if (my $hook = $handlers->{'before'}) {
    $handler = eval $hook or $self->error("beforeUpdate : $@");
  }
  
  foreach my $record (@{$self->{results}{records}}) {
    # remember names of old files (in case we must delete them later)
    my %oldFile;
    foreach (grep {$record->{$_}} keys %{$self->{upload_fields}}) {
      $oldFile{$_} = "$_/$record->{$_}";
    }

    # copy defined CGI params into record ..
    foreach my $field ($self->{data}->headers) {
      next if exists $self->{upload_fields}{$field}; # .. except the upload fields
      my $val = $self->getCGI($field);
      $record->{$field} = $val unless not defined $val;
    }

    # force username into user field (if any)
    my $userField = $self->{cfg}->get('fields_user');
    $record->{$userField} = $self->{user} if $userField;
    

    # force current time into time fields (if any)
    my %tf = %{$self->{time_fields}};
    while (my ($k, $fmt) = each %tf) {
      $record->{$k} = strftime($fmt, localtime);
    } 
    

    # now deal with uploads
    foreach my $upld (keys %{$self->{upload_fields}}) { 
      my $upldFile = $self->getCGI($upld) or next; # do nothing if empty upload

      my $mkName = undef;
      if (my $upld_hook = $self->{upload_fields}{$upld}) {
	$mkName = eval $upld_hook or 
	  $self->error("invalid upload rule for $upld: $upld_hook : $@");
      };
      my $fileName = $mkName ? &$mkName($self, $record, $upldFile) 
	: fileparse($upldFile);	# ignore directories
      my $newFile = "$upld/$fileName";
      $self->error("upload $upld : file $dir$newFile already exists") 
	if -e "$dir$newFile" and $newFile ne $oldFile{$upld};

      $self->error("can't upload several files to same server location : $newFile")
	if exists $self->{results}{upldFiles}{$newFile};

      $self->{results}{upldFiles}{$newFile} = $oldFile{$upld};
      $record->{$upld} = $fileName;
      $self->uploadToFile($upld, $dir, "$newFile.new") or 
	$self->error("uploadToFile $upld : $^E");
      $self->{msg} .= "file $upldFile uploaded to $dir$newFile<br>";
    }
    &$handler($self, $record) if $handler;
  }
}

######################################################################
sub afterUpdates {
######################################################################
  my $self = shift;

  my $upldFiles = $self->{results}{upldFiles};
  my $dir = $self->{dir};

  # rename uploaded files and delete old versions
  foreach my $file (keys %$upldFiles) {
    rename "$dir$file.new", "$dir$file" or 
      $self->error("rename $dir$file.new => $dir$file : $^E");
    my $oldFile = $upldFiles->{$file};
    if ($oldFile) {
      if ($oldFile eq $file) {
	$self->{msg} .= "old file $oldFile has been replaced<br>";
      }
      else {
	my $r = unlink "$dir$oldFile";	
	$self->{msg} .= $r ? "removed old file $dir$oldFile<br>" : "remove $dir$oldFile : $^E<br>";
      }
    }
  }

  foreach my $record (@{$self->{results}{records}}) {
    $self->enqueue("upd", $record);
  }

}


######################################################################
sub postCheckRights {
######################################################################
  my $self = shift;
  my $perm = $self->{cgi}->param('PC');
  if ($perm and not $self->can_do($perm)) {
    $self->error("No permission 'perm' for $self->{user}");
  }
}

######################################################################
sub fixAutoNum { 
######################################################################
  my $self = shift;

  # if this is a new record
  if ($self->{cfg}->get('fields_autoNum') and $self->getCGI('U') =~ /#/) {
    while ($self->{data}->fetchrow) {} # do nothing, just make sure autonum
                                       # gets updated
  }
}

######################################################################
sub tmplName { # for a given operation, find associated template name
######################################################################
  my $self = shift;
  my $op = shift;

  my $tmplName = $self->{cfg}->get("template_$op") if $self->{cfg};
  $tmplName ||= "$self->{tdbname}_$op.tt";
  return $tmplName;
}


######################################################################
sub error {
######################################################################
  my ($self, $msg) = @_;
  $self->{msg} = "<b><font color=red>ERROR</font></b><br>$msg";
  ($self->{cfg} and $self->{tmpl} and
    $self->{tmpl}->process($self->tmplName('msg'), {self => $self}))
    or do {
      print "Content-type: text/html\n\n<html>$self->{msg}</html>";
    };

  exit;
}

######################################################################
sub print_help
######################################################################
{
    print <DATA>;		# impression de la doc HTML ci-dessous
}

######################################################################
sub getCGI {
######################################################################
  my ($self, $p) = @_;

  my @vals = $self->{cgi}->param($p);
  return undef if not @vals;

  my $val = join(' ', @vals);	# join multiple values
  $val =~ s/^\s+//;		# remove initial spaces
  $val =~ s/\s+$//;		# remove final spaces
  return $val;
}

######################################################################
sub uri_escape { # encode 
######################################################################
    my $uri = shift;
    $uri =~ s{([^;\/?:@&=\$,A-Za-z0-9\-_.!~*'()])}
             {sprintf("%%%02X", ord($1))         }ge;
    return $uri;
}

######################################################################
sub uploadToFile { # 
######################################################################
  my ($self, $upld, $dir, $path) = @_;
  my $fh = $self->{cgi}->upload($upld);
  $self->mkdirs($dir, $path);
  open W, ">$dir$path" or $self->error("open >$dir$path : $^E");
  my $buf;
  binmode($fh); binmode(W);
  while (read($fh, $buf, 4096)) {print W $buf;}
  close W;
}

######################################################################
sub userMatch {
######################################################################
  my $self = shift;
  my $list = shift;
  return ($list =~ /\b\Q$self->{user}\E\b/i);
}


######################################################################
sub mkdirs { # create all missing directories in $path
######################################################################
  my ($self, $base, $path) = @_;

  my @dirs = split m!/!, $path;
  pop @dirs;			# drop last component (filename)

  foreach my $dir (@dirs) {
    $base .= "/$dir";
    -d $base or mkdir($base, 0777) or $self->error("mkdir $base : $^E");
  }
}

######################################################################
sub min { 
######################################################################
  my ($v1, $v2) = @_;
  return $v1 < $v2 ? $v1 : $v2;
}

######################################################################
sub enqueue { # enqueue ops on attached files, for later indexing
######################################################################
  my ($self, $op, $record) = @_;

  return if not $self->{queueDir};
  
  my ($seconds, $microsec) = gettimeofday;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = localtime($seconds);
  $mon+=1;
  $year+=1900;
  my $filename = sprintf "%s/$self->{queueDir}/%02d%02d%02d_%02d%02d%02d_%06d_%s.evt", 
    $self->{apache_dir},
    $year, $mon, $mday, $hour, $min, $sec, $microsec, $op;
  open Q, ">$filename" or $self->error("enqueue $filename : $^E");
  print Q <<__EOF__;
OP $op
DIR $self->{dir}
TDB $self->{tdbname}
ID $record->{Id}
__EOF__

  print Q "INTEGRAL FichierWord/$record->{FichierWord}\n"
    if $record->{FichierWord};
  print Q "BLANCHI  FichierWordBlanchi/$record->{FichierWordBlanchi}\n"
    if $record->{FichierWordBlanchi};
  close Q;
}



######################################################################
sub decisHtmlFilterFactory { # should really belong somewhere else
######################################################################
  my ($context, $highlight, $pdf_file) = @_;

  use GE::Justice::Regexes;

  return sub {
    my $html = shift;

    # remove initial and final markup
    $html =~ s[^.*?<div id=txtDecis>][]s;
    $html =~ s[</div>\s*</body>\s*</html>][];


    # remove smart tags of MS Word
    $html =~ s[</?st[^>]+>][]g;

    # remove hard-coded hrefs
    $html =~ s[<a href.*?>(.*?)</a>][$1]g;

    # replace PRE tags by P tags
    $html =~ s[<(/?)PRE>][<$1P>]ig;

    $html = autoDecisLinks($html);

    if ($highlight) {

      # highlight selected words
      $html =~ s[\b($highlight)\b][<span class="HL">$1</span>]ig;

      # remove highlight within hrefs
      $html =~ s[(href|src)=
		 (
		 (
		 [^>]+?                  # anything not closing the tag
		 <span\ class="HL">     # highlight code
		 .*?                    # highlighted content
		 </span>                # end highlight code
		)+                      # can happen many times
		)]
	[$1 . "=" . pruneSpan($2)]xeg;
    }


    my @links;
    push @links, qq{<a href="#EF">En fait</a>} if $html =~ m[name="EF"];
    push @links, qq{<a href="#ED">En droit</a>} if $html =~ m[name="ED"];
    push @links, qq{<a href="#PCM">Par ces motifs</a>} if $html =~ m[name="PCM"];
    my $links = "";
    $links = '<span style="float:right">'
           . join("<br>", @links)
           . '</span>'
	     if @links;
    return $links . $html;
  }
}


######################################################################
sub autoDecisLinks { # should really belong somewhere else
######################################################################
  my $html = shift;

    # remove all hrefs
    $html =~ s[<a +href.*?>(.*?)</a>][$1]ig;

    # insert automatic hrefs

    my $decis_ge = qr[[A-Z]{3,}/\d+/\d+];

    #   liens sur autres décisions (genevoises, ATF publiés, ATF non publiés)
    $html =~ s[$A_ATF|$ATFregex|$decis_ge][<a href="/perl/decis/$&">$&</a>]gs;

    #   liens sur lois cantonales ou fédérales
    $html =~ s[$gelex_regex|\bRS\s+\d+(?:\.\d+)*][<a href="/perl/JmpLex/$&">$&</a>]g;

  return $html;
}





sub pruneSpan {
  my $txt = shift;
  $txt =~ s[</?span.*?>][]g;
  return $txt;
}

1;

=head1 TODO

  - can_do : deal with groups GE-JUSTICE
  - print doc if no path_info
  - path to global templates : option
  - find better security model for action 'add'
  - doc : show example of access to fileTabular->mtime->{hour}
  - server-side record validation using "F::T where syntax" (f1 > val, etc.)
    or using code hook
  - cache cfg if running under mod_perl Registry
  - generalize buildEmptyRecord (design config params)
  - template for $self->delete (either default or user-supplied)
  - support for path given without PATH_INFO : still useful ??
      context : 1) mod_perl ; 2) Apache handler (cgi-bin) ; 3) cgi-bin/tdb/path
  - config property for allowing/disallow multiple Delete or multiple Update
  - view abstraction for direct display of attached doc 
  - update : how to handle name conflicts : field names / builtin 
    names (sortBy, score, excerpts, etc.)
  - better abstraction for PRE handler according to U=.. (build/search)
  - remove direct link to GE::Justice::AnyDoc2Txt, need abstracted converter
  - more clever generation of wordsQueried in search
  - remove direct call to $upld_field/...
  - enqueue : remove GE::Justice dependencies (FichierWord, etc.)

=cut

__DATA__

This will be the doc
