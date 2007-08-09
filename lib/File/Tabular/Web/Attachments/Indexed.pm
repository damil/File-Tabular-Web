package File::Tabular::Web::Attachments::Indexed;

use base File::Tabular::Web::Attachments;
use strict;
use warnings;
no warnings 'uninitialized';

use Carp;


sub app_initialize {
  my $self = shift;

  $self->SUPER::app_initialize;

  my $cfg = $self->{app}{cfg};
  $self->{app}{ixDocNumField} = $cfg->get('fields_indexedDocNum');
}


#----------------------------------------------------------------------
sub words_queried { 
#----------------------------------------------------------------------
  my $self = shift;
  my $search_fulltext = $self->param('SFT') || "";
  return ("$self->{search_string_orig} $search_fulltext" =~ m([\w/]+)g);
}


#----------------------------------------------------------------------
sub log_search {
#----------------------------------------------------------------------
  my $self = shift;
  return if not $self->{logger};

  my $msg = sprintf "[%s][%s] $self->{user}", 
    $self->{search_string_orig},
    $self->param('SFT');
  $self->{logger}->info($msg);
}


#----------------------------------------------------------------------
sub before_search {
#----------------------------------------------------------------------
  my ($self) = @_;

  $self->SUPER::before_search;

  my $search_fulltext = $self->param('SFT') or return;

  $self->{app}{ixDocNumField} 
    or croak "missing [fields]indexedDocNum in config";


  $self->{indexer} ||= Search::Indexer->new( # will croak in case of failure
    dir          => $self->{dir},
    preMatch     => $self->{cfg}->get('preMatch'),
    postMatch    => $self->{cfg}->get('postMatch')
   );

  my $result = $self->{indexer}->search($search_fulltext, "true");

  # MAYBE add some logging here (time for fulltext search, #docs found)

  if ($result) {                # nonempty results
    $self->{results}{killedWords} = join ", ", @{$result->{killedWords}};
    $self->{results}{regex} = $result->{regex};

    my $doc_ids = join "|", keys %{$result->{scores}}
      or return;                # no scores, no results

    $self->{search_string} = "$self->{app}{ixDocNumField} ~ '^(?:$doc_ids)\$'";

    # TODO MAYBE: optimize if ixDocNumField is the first field
    # my $docNumColumn = $self->{data}->ht->{$docNumField} or
    # $search_string = "~'^(?:$tmp)(?:\\Q$FS\\E|\$)'" if $docNumColumn == 1;


    $self->{search_string} .= " AND ($self->{search_string_orig})" 
      if $self->{search_string_orig};
  }
  $self->{fulltext_result} = $result;

  return $self;
}

#----------------------------------------------------------------------
sub search { # call parent search(), add fulltext scores into results
#----------------------------------------------------------------------
  my $self = shift;
  $self->SUPER::search;

  my $fulltext_result = $self->{fulltext_result} or return;

  # merge scores into results 
  $self->{data}->ht->add('score'); # new field for storing 'score'

  foreach my $r (@{$self->{results}{records}}) {
    my $docId = $r->{$self->{app}{ixDocNumField}};
    $r->{score} = $fulltext_result->{scores}{$docId};
  }
  $self->{sortBy} ||= "score : -num"; # default sorting by decreasing scores
}


#----------------------------------------------------------------------
sub sort_and_slice { 
#----------------------------------------------------------------------
  my $self = shift;

  $self->SUPER::sort_and_slice;
  $self->add_excerpts;
}



#----------------------------------------------------------------------
sub add_excerpts { # add text excerpts from attached files
#----------------------------------------------------------------------
  my $self = shift;
  return unless $self->getCGI('SFT'); # nothing to do if no fulltext

  $self->{data}->ht->add('excerpts'); # need new field in the Hash::Type

  foreach my $r (@{$self->{results}{records}}) {
    my $buf = $self->{app}{ixDocContent}->($self, $r);
    my $excerpts = $self->{indexer}->excerpts($buf, $self->{results}->{regex});
    $r->{excerpts} = join(' / ', @$excerpts);
  }
}



######################################################################
sub after_delete {
######################################################################
  my ($self, $record)= @_;

  $self->SUPER::after_delete($record);
  $self->delete_from_index($record);
}


# REPLACE BY GENERIC CODE (NOT DEPENDENT FROM MINUTES)
sub delete_from_index {
  my ($self, $record)= @_;  
  $self->enqueue("del", $record);
}




#----------------------------------------------------------------------
sub params_for_next_slice { 
#----------------------------------------------------------------------
  my ($self, $start) = @_;

  return ("SFT=" . $self->param('SFT'),
          $self->SUPER::params_for_next_slice($start));
}

