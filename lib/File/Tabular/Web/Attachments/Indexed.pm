package File::Tabular::Web::Attachments::Indexed;

use base qw/File::Tabular::Web::Attachments/;
use strict;
use warnings;
no warnings 'uninitialized';

use Carp;


#----------------------------------------------------------------------
sub app_initialize {
#----------------------------------------------------------------------
  my $self = shift;

  $self->SUPER::app_initialize;

  # indexed fields are specified as "[fields]upload field=indexed" in config
  my $upld_ref = $self->{app}{upload_fields};
  my @indexed = grep {$upld_ref->{$_} =~ /indexed/} values %$upld_ref;

  @indexed < 2 or die "currently no support for multiple indexed fields";

  $self->{app}{indexed_fields} = \@indexed;
}


#======================================================================
#                 REQUEST HANDLING : SEARCH METHODS                   #
#======================================================================

#----------------------------------------------------------------------
sub words_queried { 
#----------------------------------------------------------------------
  my $self = shift;
  return ("$self->{search_string_orig} $self{search_fulltext}" =~ m([\w/]+)g);
}


#----------------------------------------------------------------------
sub log_search {
#----------------------------------------------------------------------
  my $self = shift;
  return if not $self->{logger};

  my $msg = sprintf "[%s][%s] $self->{user}", 
    $self->{search_string_orig},
    $self->{search_fulltext},
  $self->{logger}->info($msg);
}


#----------------------------------------------------------------------
sub before_search {
#----------------------------------------------------------------------
  my ($self) = @_;

  $self->SUPER::before_search;


  # searches into the fulltext index are passed through param 'SFT'
  $self->{search_fulltext} = $self->param('SFT') or return;

  $self->{app}{indexer} ||= Search::Indexer->new( 
    dir          => $self->{app}{dir},
    preMatch     => $self->{cfg}->get('preMatch'),
    postMatch    => $self->{cfg}->get('postMatch'),
   );

  my $result = $self->{app}{indexer}
                    ->search($search_fulltext, "implicit_plus");

  # MAYBE add some logging here (time for fulltext search, #docs found)

  if ($result) {                # nonempty results
    $self->{results}{killedWords} = join ", ", @{$result->{killedWords}};
    $self->{results}{regex} = $result->{regex};

    # HACK : build a regex with all document ids, and add that into
    # the search string. Not efficient if the result set is large;
    # will require more clever handling in File::Tabular::compile_query 
    # using some kind of representation for sets of integers (bit vectors
    # or Set::IntSpan::Fast)

    my $doc_ids       = join "|", keys %{$result->{scores}}
      or return;                # no scores, no results

    # my $doc_num_field = ($self->{data}->headers)[0];
    # $self->{search_string} = "$doc_num_field ~ '^(?:$doc_ids)\$'";
    # ASSUMES the document number is the record key, stored in firest field

    $self->{search_string} = "~'^(?:$tmp)\\b'" 
    $self->{search_string} .= " AND ($self->{search_string_orig})" 
      if $self->{search_string_orig};
  }
  $self->{fulltext_result} = $result;

  return $self;
}



#----------------------------------------------------------------------
sub search { # call parent search(), add fulltext scores into results
#----------------------------------------------------------------------
  my ($self) = @_;

  $self->SUPER::search;

  my $fulltext_result = $self->{fulltext_result} or return;

  # merge scores into results 
  $self->{data}->ht->add('score'); # new field for storing 'score'

  foreach my $record (@{$self->{results}{records}}) {
    my $doc_id       = $record->{$self->{app}{ixDocNumField}};
    $record->{score} = $fulltext_result->{scores}{$doc_id};
  }
  $self->{orderBy} ||= "score : -num"; # default sorting by decreasing scores
}


#----------------------------------------------------------------------
sub sort_and_slice { 
#----------------------------------------------------------------------
  my ($self) = @_;

  $self->SUPER::sort_and_slice;
  $self->add_excerpts;
}



#----------------------------------------------------------------------
sub add_excerpts { # add text excerpts from attached files
#----------------------------------------------------------------------
  my ($self) = @_;

  $self->{fulltext_result} or return;

  # need new field in the Hash::Type to store the excerpts
  $self->{data}->ht->add('excerpts'); 

  # add excerpts into each displayed record
  my $regex = $self->{results}->{regex};
  foreach my $record (@{$self->{results}{records}}) {
    my $buf = $self->indexed_doc_content($self, $record);
    my $excerpts = $self->{indexer}->excerpts($buf, $regex);
    $record->{excerpts} = join(' / ', @$excerpts);
  }
}



#----------------------------------------------------------------------
sub indexed_doc_content { # returns plain text representation of the doc.
#----------------------------------------------------------------------
  my ($self, $record) = @_;
  die 'Method "indexed_doc_content" should be redefined in your subclass';
}


#----------------------------------------------------------------------
sub params_for_next_slice { 
#----------------------------------------------------------------------
  my ($self, $start) = @_;

  return ("SFT=$self->{search_fulltext}",
          $self->SUPER::params_for_next_slice($start));
}



#======================================================================
#                 REQUEST HANDLING : UPDATE METHODS                   #
#======================================================================

# TODO : CODE FOR INDEXING AT UPDATES



#======================================================================
#                 REQUEST HANDLING : DELETE METHODS                   #
#======================================================================

#----------------------------------------------------------------------
sub after_delete {
#----------------------------------------------------------------------
  my ($self, $record)= @_;

  $self->SUPER::after_delete($record);
  $self->delete_from_index($record);
}


# REPLACE BY GENERIC CODE (NOT DEPENDENT FROM MINUTES)
sub delete_from_index {
  my ($self, $record)= @_;  
  $self->enqueue("del", $record);
}








1;

__END__

=head1 NAME

File::Tabular::Web::Attachments::Indexed - Fulltext indexing in documents attached to File::Tabular::Web

=head1 DESCRIPTION

This abstract class adds support for 
fulltext indexing in documents attached to a
L<File::Tabular::Web|File::Tabular::Web> application.

You B<must> write a subclass that redefines the 
L</indexed_doc_content> method (for translating
the content of the attached document to plain text) --
this cannot be guessed by the present framework.



=head1 CONFIGURATION

=head2 [fields]

  upload fieldname1
  upload fieldname2 = indexed

Currently only one single upload field can be indexed.

=head1 SUBCLASSING

=cut


