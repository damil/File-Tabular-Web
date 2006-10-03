#----------------------------------------------------------------------
sub beforeUpdates { # 
#----------------------------------------------------------------------
  my $self = shift;
  
  my $handler = undef;
  my $handlers = $self->{cfg}->get('handlers_update');
  if (my $hook = $handlers->{'before'}) {
    $handler = eval $hook or $self->error("beforeUpdate : $@");
  }


  # SUPER

    $handler->($self, $record) if $handler;
  }
}
