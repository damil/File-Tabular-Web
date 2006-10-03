package File::Tabular::Web::Attachments;

use base File::Tabular::Web;
use strict;
use warnings;
no warnings 'uninitialized';



######################################################################
#                    OVERRIDDEN PARENT METHODS                       #
######################################################################

sub initialize_request {
  my $self = shift;

  $self->SUPER::initialize_request;

  # TODO : move this to _load_tdb
  $self->{ixDocNumField} = $self->{cfg}->get('fields_indexedDocNum');
  my $ixDocContent       = $self->{cfg}->get("fields_indexedDocContent")
    or croak "missing [fields]indexedDocContent in config";
  $self->{ixDocContent}  = $self->find_operation($ixDocContent);

  return $self;
}





#----------------------------------------------------------------------
sub words_queried { 
#----------------------------------------------------------------------
  my $self = shift;
  my $search_string   = $self->getCGI('SS');
  my $search_fulltext = $self->getCGI('SFT');
  return ("$search_string $search_fulltext" =~ m([\w/]+)g);
}




sub log_search {
  my $self = shift;
  return if not $self->{logger};

  my $msg = sprintf "[%s][%s] $self->{user}", 
    $self->getCGI('SS'),
    $self->getCGI('SFT');
  $self->{logger}->info($msg);
}


sub prepare_search_string {
  my $self = shift;

  my $search_fulltext = $self->getCGI('SFT')
    or return $self->SUPER::prepare_search_string;

  $self->{ixDocNumField} or croak "missing [fields]indexedDocNum in config";


  $self->{indexer} ||= Search::Indexer->new( # will croak in case of failure
    dir          => $self->{dir},
    preMatch     => $self->{cfg}->get('preMatch'),
    postMatch    => $self->{cfg}->get('postMatch')
   );

  my $result = $self->{indexer}->search($search_fulltext, 1);

  if ($result) {                # nonempty results
    $self->{results}{killedWords} = join ", ", @{$result->{killedWords}};
    $self->{results}{regex} = $result->{regex};

    my $doc_ids = join "|", keys %{$result->{scores}}
      or return;                # no scores, no results

    $self->{search_string} = "$self->{ixDocNumField} ~ '^(?:$doc_ids)\$'";
    my $param_SS = $self->getCGI('SS');
    $self->{search_string} .= " AND ($param_SS)" if $param_SS;
  }
  $self->{fulltext_result} = $result;

  return $self;
}


sub end_search_hook {
  my $self = shift;

  my $fulltext_result = $self->{fulltext_result} or return;

  # merge scores into results 
  $self->{data}->ht->add('score'); # new field for storing 'score'

  foreach my $r (@{$self->{results}{records}}) {
    my $docId = $r->{$self->{ixDocNumField}};
    $r->{score} = $fulltext_result->{scores}{$docId};
  }
  $self->{sortBy} ||= "score : -num"; # default sorting by decreasing scores
}







#----------------------------------------------------------------------
sub postSearch { 
#----------------------------------------------------------------------
  my $self = shift;

  # direct display of an attached document
  # TODO : this code should probably go elsewhere
  my $doc_param = $self->getCGI('doc');
  if ($doc_param and $self->{results}{count} == 1) {
    my $subpath = $self->{results}{records}[0]{$doc_param};
    $self->{redirect_target} = "$self->{dir}/$doc_param/$subpath";
    return;
  }

  $self->sortAndSlice;
  $self->addExcerpts;
}



#----------------------------------------------------------------------
sub addExcerpts { # add text excerpts from attached files
#----------------------------------------------------------------------
  my $self = shift;
  return unless $self->getCGI('SFT'); # nothing to do if no fulltext

  $self->{data}->ht->add('excerpts'); # need new field in the Hash::Type

  foreach my $r (@{$self->{results}{records}}) {
    my $buf = $self->{ixDocContent}->($self, $r);
    my $excerpts = $self->{indexer}->excerpts($buf, $self->{results}->{regex});
    $r->{excerpts} = join(' / ', @$excerpts);
  }
}





######################################################################
sub delete_record {
######################################################################
  my ($self, $record)= @_;

  # suppress files attached to deleted record
  foreach my $upld (keys %{$self->{upload_fields}}) {
    my $filename = $record->{$upld};
    next if not $filename;
    my $r   = unlink("$self->{dir}$upld/$filename");
    my $msg = $r ? "was suppressed" : "couldn't be suppressed ($!)";
    $self->{msg} .= "Attached file $filename $msg<br>";
  }
  $self->delete_from_index($record);
}


# REPLACE BY GENERIC CODE (NOT DEPENDENT FROM MINUTES)
sub delete_from_index {
  my ($self, $record)= @_;  
  $self->enqueue("del", $record);
}


#----------------------------------------------------------------------
sub cancel_before_updates {
#----------------------------------------------------------------------
  my $self = shift;
  unlink("$dir$_.new") foreach keys %{$self->{results}{upldFiles}};
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
