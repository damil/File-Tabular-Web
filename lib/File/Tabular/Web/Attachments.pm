=begin TODO

  - override "display" to accept V=UploadField
     => would redirect to attached file

  - support for multiple files under same field

=end TODO

=cut


package File::Tabular::Web::Attachments;

use base 'File::Tabular::Web';
use strict;
use warnings;

use File::Path;
use File::Basename;
use Scalar::Util qw/looks_like_number/;


#----------------------------------------------------------------------
sub app_initialize {
#----------------------------------------------------------------------
  my $self = shift;

  $self->SUPER::app_initialize;

  # field names specified as "upload fields" in config
  $self->{app}{upload_fields} = $self->{app}{cfg}->get('fields_upload');
}


#----------------------------------------------------------------------
sub open_data {
#----------------------------------------------------------------------
  my $self = shift;

  $self->SUPER::open_data;

  # upload fields must be present in the data file
  my %data_headers = map {$_ => 1} $self->{data}->headers;
  my @upld = keys %{$self->{app}{upload_fields}};
  my $invalid = join ", ", grep {not $data_headers{$_}} @upld;
  die "upload fields in config but not in data file: $invalid" if $invalid;
}


#----------------------------------------------------------------------
sub before_update { # 
#----------------------------------------------------------------------
  my ($self, $record) = @_;

  my @upld = keys %{$self->{app}{upload_fields}};

  # remember names of old files (in case we must delete them later)
  foreach my $field (grep {$record->{$_}} @upld) {
    $self->{old_path}{$field} = $self->upload_path($record, $field);
  }

  # call parent method
  $self->SUPER::before_update($record);

  # find out about next autoNum (WARN: breaks encapsulation of File::Tabular!)
  if ($self->{cfg}->get('fields_autoNum')) {
    $self->{next_autoNum} = $self->{data}{autoNum};
  }

  # now deal with file uploads
  $self->do_upload_file($record, $_) foreach @upld;
}

#----------------------------------------------------------------------
sub do_upload_file { # 
#----------------------------------------------------------------------
  my ($self, $record, $field) = @_;

  my $remote_name = $self->param($field)
    or return;  # do nothing if empty

  my $src_fh;

  if ($self->{apache2_request}) {
    require Apache2::Upload;
    $src_fh = $self->{apache2_request}->upload($field)->fh;
  }
  else {
    my @upld_fh = $self->{cgi}->upload($field); # may be an array 

    # TODO : some convention for deleting an existing attached file
    # if @upload_fh == 0 && $remote_name =~ /^( |del)/ {...}

    # no support at the moment for multiple files under same field
    @upld_fh < 2  or die "several files uploaded to $field";
    $src_fh = $upld_fh[0];
  }

  # compute server name and server path
  $record->{$field} = $self->upload_name($record, $field, $remote_name);
  my $path          = $self->upload_path($record, $field);
  my $old_path      = $self->{old_path}{$field};

  # avoid clobbering existing files
  not -e $path or $path eq $old_path
    or die "upload $field : file $path already exists"; 

  # check that upload path is unique
  not exists $self->{results}{uploaded}{$path}
    or die "multiple uploads to same server location : $path";

  # remember new and old path
  $self->{results}{uploaded}{$path} = $old_path;

  # do the transfer
  my ($filename, $dir) = fileparse($path);
  -d $dir or mkpath $dir; # will die if can't make path
  open my $dest_fh, ">$path.new" or die "open >$path.new : $!";
  binmode($dest_fh), binmode($src_fh);
  my $buf;
  while (read($src_fh, $buf, 4096)) { print $dest_fh $buf;}

  $self->{msg} .= "file $remote_name uploaded to $path<br>";
}


#----------------------------------------------------------------------
sub after_update {
#----------------------------------------------------------------------
  my ($self, $record) = @_;

  my $uploaded = $self->{results}{uploaded};

  # rename uploaded files and delete old versions
  while (my ($path, $old_path) = each %$uploaded) {
    rename "$path.new", "$path" or die "rename $path.new => $path : $!";
    if ($old_path) {
      if ($old_path eq $path) {
	$self->{msg} .= "old file $old_path has been replaced<br>";
      }
      else {
	my $unlink_ok = unlink $old_path;	
	$self->{msg} .= $unlink_ok ? "<br>removed old file $old_path<br>" 
                                   : "<br>remove $old_path : $^E<br>";
      }
    }
  }
}




#----------------------------------------------------------------------
sub rollback_update { # undo what was done by "before_update"
#----------------------------------------------------------------------
  my ($self, $record) = @_;
  my $uploaded = $self->{results}{uploaded};
  foreach my $path (keys %$uploaded) {
    unlink($path);
  }
}




#----------------------------------------------------------------------
sub after_delete {
#----------------------------------------------------------------------
  my ($self, $record)= @_;

  $self->SUPER::after_delete($record);

  # suppress files attached to deleted record
  my @upld = keys %{$self->{app}{upload_fields}};
  foreach my $field (@upld) {
    my $path = $self->upload_path($record, $field) 
      or next;
    my $unlink_ok = unlink "$path";	
    my $msg = $unlink_ok ? "was suppressed" : "couldn't be suppressed ($!)";
    $self->{msg} .= "Attached file $path $msg<br>";
  }
}


#----------------------------------------------------------------------
sub upload_name { # default implementation; override in subclasses
#----------------------------------------------------------------------
  my ($self, $record, $field, $remote_name)= @_;

  # just keep the trailing part of the remote name
  $remote_name =~ s{^.*[/\\]}{};

  my $upload_name = $remote_name;

  # get the id of that record; if creating, cheat by guessing next autoNum
  my $autonum_char = $self->{data}{autoNumChar};
  my $key_field    = ($self->{data}->headers)[0];
  my $key_val      = $record->{$key_field};
  $key_val =~ s/$autonum_char/$self->{next_autoNum}/;

  if (looks_like_number($key_val)) {
    my $subdir = sprintf "%05d", int($key_val / 100);
    $upload_name =  "$subdir/${key_val}_${remote_name}";
  }

  return $upload_name;
}


#----------------------------------------------------------------------
sub upload_path { # default implementation; override in subclasses
#----------------------------------------------------------------------
  my ($self, $record, $field)= @_;

  return join "/", $self->{app}{dir}, $field, $record->{$field};
}


#----------------------------------------------------------------------
sub download_url { # default implementation; override in subclasses
#----------------------------------------------------------------------
  my ($self, $record, $field)= @_;

  return join "/", $field, $record->{$field};
}

1;

__END__


=head1 NAME

File::Tabular::Web::Attachments - Support for attached document in a File::Tabular::Web application

=head1 DESCRIPTION

This subclass adds support for attached documents in a 
L<File::Tabular::Web|File::Tabular::Web> application.
One or several fields of the tabular file may hold 
names of attached documents; these documents can be 
downloaded from or uploaded to the Web server.


=head2 Phases of file upload

When updating a record with attached files,
files are first transfered to temporary locations by the 
L</before_update> method.
Then the main record is updated as usual through the 
L<File::Tabular::Web/update|parent method>.
Finally, files are renamed to their final location
by the L</after_update> method.
If the update operation failed, files are destroyed
by the L</rollback_update> method.


=head1 CONFIGURATION FILE

There is one single addition to the configuration file.

=head2 [fields]

  upload <field_name_1>
  upload <field_name_2>
  ...

Declares C<< field_name_1 >>, C<< field_name_2 >>, etc. 
to be upload fields.


=head1 WRITING TEMPLATES

  - downloading files : just relative URL
  - uploading files : don't remember multipart-data



=head1 METHODS

=head2 app_initialize

Calls the L<File::Tabular::Web/app_initialize|parent method>.
In addition, parses the C<upload> variable in C<< [fields] >> section,
putting the result in the hash ref 
C<< $self->{app}{upload_fields} >>.


=head2 open_data

Calls the L<File::Tabular::Web/open_data|parent method>.
In addition, checks that fields declared as upload
fields are really present in the data.

=head2 before_update

Calls the L<File::Tabular::Web/before_update|parent method>.
In addition, uploads submitted files to a temporary name in the application 
directory.

=head2 after_update

Calls the L<File::Tabular::Web/after_update|parent method>,
then renames the uploaded files to their final location.

=head2 rollback_update

Unlinks the uploaded files.


=head2 after_delete

Calls the L<File::Tabular::Web/after_delete|parent method>,
then suppresses files attached to the deleted record.


=head2 do_upload_file

Internal method for implementing the file transfer.
Checks that we are not going to clobber an existing
file on the server.


=head2 upload_name

  my $name = $self->upload_name($record, $field_name, $remote_name)

Returns the partial pathname that will be stored in the record field.
The default implementation takes the numeric id of the record
(if any) and concatenates it with the C<$remote_name>;
furthermore, this is put into subdirectories by ranges 
of 100 numbers : so for example file C<foo.txt> in 
record with id C<1234> will become
C<00012/1234_foo.txt>.
This behaviour may be redefined in subclasses.

=head3 upload_path

  my $path = $self->upload_path($record, $fieldname)

Returns a full pathname to the attached document.
The default implementation concatenates the application
directory, the C<$fieldname> (corresponding to a subdirectory),
and then the file name stored in C<<  $record->{$fieldname} >>.
This behaviour may be redefined in subclasses.


=head3 download_url

  my $url = $self->download_url($record, $fieldname)

Returns an url to the attached document, relative
to the application url. So it can be used in templates
as follows

  [% SET download_url = self.download_url(record, fieldname); %]
  [% IF download_url %]
    <a href="[% download_url %]">Attached document</a>
  [% END; # IF download_url %]




