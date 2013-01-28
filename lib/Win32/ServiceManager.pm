package Win32::ServiceManager;

use Moo;
use IPC::System::Simple 'capture';

has nssm_wrap_default => (
    is => 'ro',
    default => sub { 1 },
);

has use_perl_default => (
    is => 'ro',
    default => sub { 1 },
);

has use_sc_default => (
   is => 'ro',
   default => sub { 1 },
);

has nssm_path => (
   is => 'ro',
   default => sub { 'nssm.exe' },
);

sub create_service {
   my ($self, %args) = @_;

   my $nssm = $self->nssm_wrap_default;
   $nssm = $args{nssm} if exists $args{nssm};

   my $use_perl = $self->use_perl_default;
   $use_perl = $args{use_perl} if exists $args{use_perl};

   my ($command, $args);

   if ($use_perl) {
      $command = $^X;
      die 'command is required!' unless $args{command};
      $args = $args{command} . ($args{args} ? " $args{args}" : '')
   } else {
      $command = $args{command} or die 'command is required!';
      $args = $args{args};
   }

   my $name    = $args{name}    or die 'name is required!';
   my $display = $args{display} or die 'display is required!';

   my $depends = $args{depends};
   my $description = $args{description};

   if ($nssm) {
      capture($self->nssm_path, 'install', $name, $command,
         ($args ? $args : ())
      )
   } else {
      capture(
         qw(sc create), $name,
         qq(binpath= "$command") . ($args ?  " $args" : ''),
      )
   }

   capture(
      qw(sc config), $name, qq(DisplayName= "$display"),
      qq(type= own start= auto) . ($depends ? qq( depend= "$depends") : '')
   );

   capture(qw(sc failure), $name, 'reset= 60', 'actions= restart/60000');
   capture(qw(sc description), $name, $description) if $description;
}

1;
