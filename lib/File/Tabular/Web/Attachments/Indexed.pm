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

  $self->{app}{indexed_field} = $indexed[0];
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
    # ASSUMES the document number is the record key, stored in firest field
    my $doc_ids       = join "|", keys %{$result->{scores}}
      or return;                # no scores, no results
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
    my $buf = $self->indexed_doc_content($record);
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
#                        HANDLING ATTACHMENTS                         #
#======================================================================


#----------------------------------------------------------------------
sub after_add_attachment {
#----------------------------------------------------------------------
  my ($self, $record, $field, $path) = @_;

  if ($field eq $self->{app}{indexed_field}) {
    my $buf  = $self->indexed_doc_content($record);
    delete self->{app}{indexer};
    my $indexer = Search::Indexer->new(dir       => $self->{app}{dir},
                                       writeMode => 1);
    $indexer->add($self->key($record), $buf);
  }
}

#----------------------------------------------------------------------
sub before_delete_attachment {
#----------------------------------------------------------------------
  my ($self, $record, $field, $path) = @_;

  if ($field eq $self->{app}{indexed_field}) {
    delete self->{app}{indexer};
    my $indexer = Search::Indexer->new(dir       => $self->{app}{dir},
                                       writeMode => 1);
    $indexer->remove($self->key($record));
  }
}


#----------------------------------------------------------------------
sub indexed_doc_content {
#----------------------------------------------------------------------
  my ($self, $record) = @_;

  # this is the default implementation, MOST PROBABLY INADEQUATE
  # should be overridden in subclasses

  my $path = $self->upload_fullpath($record, $self->{indexed_field});
  open my $fh, $path or die "open $path: $!";
  local $/;
  my $content = <$fh>; # just return the file content
  return $content;
}




1;

__END__

=head1 NAME

File::Tabular::Web::Attachments::Indexed - Fulltext indexing in documents attached to File::Tabular::Web

=head1 DESCRIPTION

This abstract class adds support for 
fulltext indexing in documents attached to a
L<File::Tabular::Web|File::Tabular::Web> application.

Most probably you should write a subclass that redefines the 
L</indexed_doc_content> method (for translating
the content of the attached document to plain text).
The default implementation just returns the raw file content,
but this is I<most probably inadequate> : if the attached
file is in binary format (like a C<.doc> document), or
even in HTML, some translation process must be programmed,
and cannot be guessed by the present framework.


=head1 RESERVED FIELD NAMES

Records retrieved from a fulltext search will have two 
additional fields : C<score> (how well the document 
matched the query) and C<excerpts> (strings
of text fragments close to the searched words).
Therefore those field names should not be present
as regular fields in the data file.

=head1 CONFIGURATION

=head2 [fields]

  upload fieldname1
  upload fieldname2 = indexed

Currently only one single upload field can be indexed
within a given application.

=head1 METHODS

=head1 SUBCLASSING

=head2 indexed_doc_content


=cut


