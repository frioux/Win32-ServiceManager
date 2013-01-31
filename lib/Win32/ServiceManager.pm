package Win32::ServiceManager;

use Moo;
use IPC::System::Simple 'capture';

has use_nssm_default => (
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

   my $nssm = $self->use_nssm_default;
   $nssm = $args{use_nssm} if exists $args{use_nssm};

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

sub start_service {
   my ($self, $name, $options) = @_;

   die 'name is required!' unless $name;
   $options ||= {};

   my $sc = $self->use_sc_default;
   $sc = $options->{use_sc} if exists $options->{use_sc};

   capture( ($sc ? 'sc' : 'net' ), 'start', $name )
}

sub stop_service {
   my ($self, $name, $options) = @_;

   die 'name is required!' unless $name;
   $options ||= {};

   my $sc = $self->use_sc_default;
   $sc = $options->{use_sc} if exists $options->{use_sc};

   capture( ($sc ? 'sc' : 'net' ), 'stop', $name )
}

sub delete_service {
   my ($self, $name) = @_;

   die 'name is required!' unless $name;

   capture( qw(sc delete), $name )
}

sub restart_service {
   my ($self, $name, $options) = @_;

   die 'name is required!' unless $name;
   $options ||= {};

   my $sc = $self->use_sc_default;
   $sc = $options->{use_sc} if exists $options->{use_sc};

   $self->stop_service($name, { use_sc => 0 });
   $self->start_service($name, { use_sc => $sc });
}

1;

__END__

=pod

=head1 SYNOPSIS

 use Win32::ServiceManager;
 use Path::Class 'file';

 my $dir = file(__FILE__)->parent->absolute;
 my $sc = Win32::ServiceManager->new(
    nssm_path => $dir->file(qw( cgi exe nssm.exe ))->stringify,
 );

 $sc->create_service(
    name => 'LynxWebServer01',
    display => 'Lynx Web Server 1',
    description => 'Handles Web Requests on port 3001',
    command =>
       $dir->file(qw( App script server.pl ))->stringify .
          ' -p 3001',
 );
 $sc->start_service('LynxWebServer01', { use_sc => 0 });
 $sc->stop_service('LynxWebServer01');
 $sc->delete_service('LynxWebServer01');

=head1 METHODS

=head2 create_service

 $sc->create_service(
    name        => 'GRWeb1',
    display     => 'Giant Robot Web Worker 1',
    description => 'Handles Giant Robot Web Requests on port 3001',
    use_perl    => 1,
    use_nssm    => 1,
    command     => 'C:\code\GR\script\server.pl -p 3001',
    depends     => [qw(MSSQL Apache2.4)],
 );

Takes a hash of the following arguments:

=over 2

=item * C<name>

(required) The name of the service (which is used when doing a C<sc start> etc.)

=item * C<use_nssm>

(defaults to the value of L<use_nssm_default>)  Set this to start your service with L</nssm>

=item * C<use_perl>

(defaults to the value of L<use_perl_default>)  Set this to create perl
services.  Uses C<$^X>.  If for some reason you want to use a different perl you
will have to set C<use_perl> to false.

=item * C<display>

(required) The display name to give the service

=item * C<description>

(optional) The description to give the service.

=item * C<command>

(required) The command that is effectively your service

=item * C<args>

(optional) Arguments that get passed to the command above.
XXX: do these even make sense?

=item * C<depends>

(optional) List of service names that must be started for your service to
function.  You may either pass a string or an array ref.  A string gets passed
on directly, the array reference gets properly joined together.

=back

Note: there are many options that C<sc> can use to create and modify services.
I have taken the few that we use in my project and forced the rest upon you,
gentle user.  For example, whether you like it or not these services will
restart on failure and start automatically on boot.  I am completely willing to
add more options, but in 4 distinct projects we have never needed more than the
above.  B<Patches Welcome!>

=head2 start_service

 $sc->start_service('GRWeb1', { use_sc => 1 });

Starts a service with the passed name.  The second argument is an optional
hashref with the following options:

=over 2

=item * C<usc_sc>

(defaults to the value of L</use_sc_default>)  Set this to false if you want to
block until the service starts.

=back

=head2 stop_service

 $sc->stop_service('GRWeb1', { use_sc => 1 });

Stops a service with the passed name.  The second argument is an optional
hashref with the following options:

=over 2

=item * C<usc_sc>

(defaults to the value of L</use_sc_default>)  Set this to false if you want to
block until the service stops.

=back


=head2 restart_service

 $sc->restart_service('GRWeb1', { use_sc => 1 });

Stops and starts a service with the passed name.  The second argument is an optional
hashref with the following options:

=over 2

=item * C<usc_sc>

(defaults to the value of L</use_sc_default>)  Set this to false if you want to
block until the service starts.  (Note that the blocking until the service has
stopped is required.)

=back

=head1 ATTRIBUTES

=head2 use_nssm_default

The default value of C<use_nssm> for the L</create_service> method.

=head2 use_perl_default

The default value of C<use_perl> for the L</create_service> method.

=head2 use_sc_default

Set this to true (default) to use C<sc> to start or stop services.  C<sc> is
faster, but asyncronous.  Sometimes using ye olde C<net> is better as it allows
for restarts, for example.

=head2 nssm_path

Set this to the path to nssm (default is just 'nssm.exe').

=head1 nssm

L<nssm|http://nssm.cc> is a handy service wrapper for Windows.  Instead of
adding hooks directly to your program to handly Windows service signals, this
program runs your program for you and intercepts the signals and acts
appropriately.  It is open source and clocks in at less than two megabytes of
RAM.  The code is at C<git://git.nssm.cc/nssm/nssm.git>.

=head1 PRO-TIPS

The best way to use this module is to subclass it for your software.  So for
example we have a subclass that looks something like the following:

 package Lynx::ServiceManager

 use Moo;
 extends 'Win32::ServiceManager';

 our $DIR = file(__FILE__)->parent->absolute;
 sub create_catalyst_service {
    my ($self, $i) = @_;

    $self->create_service(
       name => "LynxWebServer$i",
       display => "Lynx Web Server $i",
       description => 'Handles Web Requests on port 3001',
       command =>
          $dir->file(qw( App script server.pl ))->stringify .
             " -p 300$i",
    );

 }

 sub start_catalyst_service { $_[0]->start_service("LynxWebServer$_[1]", $_[2]) }

 ...

The above makes it very easy for use to start, stop, add, and remove catalyst
services.
