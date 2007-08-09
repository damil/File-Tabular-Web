=begin TODO

  - override "display" to accept V=UploadField
     => would redirect to attached file

=end TODO

=cut


package File::Tabular::Web::Attachments;

use base File::Tabular::Web;
use strict;
use warnings;
no warnings 'uninitialized';

use Carp;
use File::Path;
use File::Basename;


#----------------------------------------------------------------------
sub app_initialize {
#----------------------------------------------------------------------
  my $self = shift;

  $self->SUPER::app_initialize;

  my $cfg = $self->{app}{cfg};
  $self->{app}{upload_fields} = $cfg->get('fields_upload'); # hashref
}








#----------------------------------------------------------------------
sub before_update { # 
#----------------------------------------------------------------------
  my ($self, $record) = @_;
  my $dir = $self->{app}{dir};

  # TODO : replace "handlers" in config  by some OO structure

  my $handler = undef;
  my $handlers = $self->{cfg}->get('handlers_update');

  if (my $hook = $handlers->{'before'}) {
    $handler = eval $hook or $self->error("before_update : $@");
  }
  

  # remember names of old files (in case we must delete them later)
  my %oldFile;
  foreach (grep {$record->{$_}} keys %{$self->{upload_fields}}) {
    $oldFile{$_} = "$_/$record->{$_}";
  }

  # copy defined CGI params into record ..
  foreach my $field ($self->{data}->headers) {

    # .. except the upload fields
    next if exists $self->{upload_fields}{$field}; 

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

      
    my $name_generator = $self->upload_name_generator($upld);

    my $fileName 
      = $name_generator ? $name_generator->($self, $record, $upldFile) 
        : fileparse($upldFile);	# ignore directories

    my $upload_name
      = $self->final_upload_name($dir, $upld, $fileName, $oldFile{$upld});


    not exists $self->{results}{upldFiles}{$upload_name}
      or croak "can't upload several files "
        . "to same server location : $upload_name";


    $self->{results}{upldFiles}{$upload_name} = $oldFile{$upld};
    $record->{$upld} = $fileName;
    $self->uploadToFile($upld, $dir, "$newFile.new") or 
      $self->error("uploadToFile $upld : $^E");
    $self->{msg} .= "file $upldFile uploaded to $dir$newFile<br>";
  }
  &$handler($self, $record) if $handler;

}


#----------------------------------------------------------------------
sub rollback_update {
#----------------------------------------------------------------------
  my $self = shift;
  unlink("$dir$_.new") foreach keys %{$self->{results}{upldFiles}};
}


#----------------------------------------------------------------------
sub upload_name_generator {
#----------------------------------------------------------------------
  my ($self, $upld) = @_;
  my $name_generator = undef;
  if (my $upld_hook = $self->{upload_fields}{$upld}) {
    $name_generator = eval $upld_hook or 
      croak "invalid upload rule for $upld: $upld_hook : $@";
  };
  return $name_generator;
}


#----------------------------------------------------------------------
sub final_upload_name {
#----------------------------------------------------------------------
  my ($self, $dir, $upld, $fileName, $old_path) = @_;

  my $upload_name = "$upld/$fileName";

  not -e "$dir/$upload_name"
    or $upload_name eq $old_path
      or croak "upload $upld : file $dir/$upload_name already exists"; 

  return $upload_name;
}


#----------------------------------------------------------------------
sub after_update {
#----------------------------------------------------------------------
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
    $self->after_update_single_record($record);
  }
}

#----------------------------------------------------------------------
sub after_update_single_record {
#----------------------------------------------------------------------
  # override in subclasses
}


#----------------------------------------------------------------------
sub uploadToFile { # 
#----------------------------------------------------------------------
  my ($self, $upld, $dir, $path) = @_;

  # source
  my $source_fh = $self->{cgi}->upload($upld);

  # destination
  my ($name, $fullpath) = fileparse(join("/", $dir, $path));
  -d $fullpath or mkpath $fullpath; 
  open my $dest_fh, ">$fullpath$name" or croak "open >$fullpath$name : $^E";

  # copy
  my $buf;
  binmode($_) for $source_fh, $dest_fh;
  while (read($source_fh, $buf, 4096)) {print $dest_fh $buf;}
}




#----------------------------------------------------------------------
sub after_delete {
#----------------------------------------------------------------------
  my ($self, $record)= @_;

  # suppress files attached to deleted record
  foreach my $upld (keys %{$self->{upload_fields}}) {
    my $filename = $record->{$upld};
    next if not $filename;
    my $r   = unlink("$self->{dir}$upld/$filename");
    my $msg = $r ? "was suppressed" : "couldn't be suppressed ($!)";
    $self->{msg} .= "Attached file $filename $msg<br>";
  }
}



__END__




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
