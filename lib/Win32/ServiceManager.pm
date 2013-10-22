package Win32::ServiceManager;

# ABSTRACT: Manage Windows Services

use Moo;
use IPC::System::Simple 'capture';
use Win32::Service qw(StartService StopService GetStatus GetServices);
use Time::HiRes 'sleep';

has use_nssm_default => (
    is => 'ro',
    default => sub { 1 },
);

has use_perl_default => (
    is => 'ro',
    default => sub { 1 },
);

has non_blocking_default => (
   is => 'ro',
   default => sub { 1 },
);

has nssm_bits => (
   is => 'ro',
   default => sub { 64 },
);

has nssm_path => (
   is => 'ro',
   lazy => 1,
   builder => '_build_nssm_path',
);

sub _build_nssm_path { 'nssm_' . $_[0]->nssm_bits . q(.exe) }

sub _nssm_install {
   $_[0]->nssm_path, 'install', $_[1], $_[2], ($_[3] ? $_[3] : ())
}

sub _sc_install {
   qw(sc create), $_[1], qq(binpath= "$_[2]") . ($_[3] ?  " $_[3]" : ''),
}

sub _sc_configure {
   qw(sc config), $_[1], qq(DisplayName= "$_[2]"),
   qq(type= own start= auto) . $_[0]->_depends($_[3])
}

sub _depends {
   my ($self, $depends) = @_;

   return '' unless $depends;

   my $d = $depends;
   $d = join '\\', @$depends if ref $depends;

   return qq( depend= "$d");
}

sub _sc_failure { qw(sc failure), $_[1], 'reset= 60', 'actions= restart/60000' }

sub _sc_description { qw(sc description), $_[1], $_[2] }

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
      capture($self->_nssm_install($name, $command, $args))
   } else {
      capture($self->_sc_install($name, $command, $args))
   }

   capture($self->_sc_configure($name, $display, $depends));
   capture($self->_sc_failure($name));
   capture($self->_sc_description($name, $description)) if $description;
}

sub start_service {
   my ($self, $name, $options) = @_;

   die 'name is required!' unless $name;
   $options ||= {};

   my $non_blocking = $self->non_blocking_default;
   $non_blocking = $options->{non_blocking} if exists $options->{non_blocking};

   StartService('', $name) or die "failed to start service <$name>";
   return if $non_blocking;

   my $starting = $self->get_status($name)->{current_state} eq 'start pending';
   while ($starting) {
      sleep 0.05;
      $starting = $self->get_status($name)->{current_state} eq 'start pending';
   }
}

sub stop_service {
   my ($self, $name, $options) = @_;

   die 'name is required!' unless $name;
   $options ||= {};

   my $non_blocking = $self->non_blocking_default;
   $non_blocking = $options->{non_blocking} if exists $options->{non_blocking};

   StopService('', $name) or die "failed to stop service <$name>";
   return if $non_blocking;

   my $stopping = $self->get_status($name)->{current_state} eq 'stop pending';
   while ($stopping) {
      sleep 0.05;
      $stopping = $self->get_status($name)->{current_state} eq 'stop pending';
   }
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

   my $non_blocking = $self->non_blocking_default;
   $non_blocking = $options->{non_blocking} if exists $options->{non_blocking};

   $self->stop_service($name, { non_blocking => 0 });
   $self->start_service($name, { non_blocking => $non_blocking });
}

my @statuses = (
   undef, # starts at 1
   'stopped',
   'start pending',
   'stop pending',
   'running',
   'continue pending',
   'pause pending',
   'paused',
);

sub get_status {
   my ($self, $name, $options) = @_;

   my %ret;
   GetStatus('', $name, \%ret);

   # more statuses will be added when I (or others) need them
   # http://msdn.microsoft.com/en-us/library/windows/desktop/ms685996%28v=vs.85%29.aspx
   return {
      current_state => $statuses[$ret{CurrentState}],
   }
}

sub get_services {
   my %ret;
   GetServices('', \%ret);

   \%ret
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
 $sc->start_service('LynxWebServer01', { non_blocking => 0 });
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

 $sc->start_service('GRWeb1', { non_blocking => 1 });

Starts a service with the passed name.  The second argument is an optional
hashref with the following options:

=over 2

=item * C<non_blocking>

(defaults to the value of L</non_blocking_default>)  Set this to false if you want to
block until the service starts.

=back

=head2 stop_service

 $sc->stop_service('GRWeb1', { non_blocking => 1 });

Stops a service with the passed name.  The second argument is an optional
hashref with the following options:

=over 2

=item * C<non_blocking>

(defaults to the value of L</non_blocking_default>)  Set this to false if you want to
block until the service stops.

=back


=head2 restart_service

 $sc->restart_service('GRWeb1', { non_blocking => 1 });

Stops and starts a service with the passed name.  The second argument is an optional
hashref with the following options:

=over 2

=item * C<non_blocking>

(defaults to the value of L</non_blocking_default>)  Set this to false if you want to
block until the service starts.  (Note that the blocking until the service has
stopped is required.)

=back

=head2 get_status

 $sc->start_service('GRWeb1')
    unless $sc->get_status('GRWeb1')->{current_state} eq 'running';

Returns the status info about the specified service.  The status info is a hash
containing the following keys:

=over 2

=item * C<current_state>

Can be any of the following

=over 2

=item * C<stopped>

=item * C<start pending>

=item * C<stop pending>

=item * C<running>

=item * C<continue pending>

=item * C<pause pending>

=item * C<paused>

=back

=back

Note that there is much more information that could be included in
C<get_status>, but I've only needed the C<current_state> so far.  If you need
something else I will gladly add more information to the returned hash, or
better yet, send a patch.

=head2 get_services

 my $services = $sc->get_services;
 say "$_ is installed!" for keys %$services;

Returns a hashref of services.  Keys are the display name, values are the real
name.

=head2 delete_service

 $sc->delete_service('GRWeb1');

Deletes a service

=head1 ATTRIBUTES

=head2 use_nssm_default

The default value of C<use_nssm> for the L</create_service> method.

=head2 use_perl_default

The default value of C<use_perl> for the L</create_service> method.

=head2 idempotent_default

Set this to true (default) to idempotently start, stop, delete, and create
services.

=head2 non_blocking_default

Set this to true (default) to asyncronously to start or stop services.
Sometimes blocking is better as it allows for restarts, for example.

=head2 nssm_path

Set this to the path to nssm (default is just C<nssm_64.exe>, or C<nssm_32.exe>
if you set L</nssm_bits> to 32).

=head2 nssm_bits

L</nssm> comes in both 32 and 64 bit flavors.  This specifies when of the
bundled C<nssm> binaries to use.  (default is 64)

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

=head1 CAVEAT LECTOR

I have used this at work and am confident in it, but it has only been used on
Windows Server 2008.  The tests can do no better than ensure the generated
strings are as expected, instead of ensuring that a service was correctly
created or started or whatever.

Additionally, in my own work when I get an error from C<sc> I just report it
and move forward.  Because of this I have done very little to make exceptions
useful.  I am open to making them objects but again, I do not need that myself,
so B<Patches Welcome!>
