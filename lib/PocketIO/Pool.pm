package PocketIO::Pool;

use strict;
use warnings;

use Scalar::Util qw(blessed);

use PocketIO::Connection;
use PocketIO::Message;

use constant DEBUG => $ENV{POCKETIO_POOL_DEBUG};

sub new {
    my $class = shift;

    my $self = {@_};
    bless $self, $class;

    $self->{connections} = {};
    $self->{rooms} = {};

    return $self;
}

sub find_connection {
    my $self = shift;
    my ($conn) = @_;

    my $id = blessed $conn ? $conn->id : $conn;

    return $self->{connections}->{$id};
}

sub add_connection {
    my $self = shift;
    my $cb   = pop @_;

    my $conn = $self->_build_connection(@_);

    $self->{connections}->{$conn->id} = $conn;

    DEBUG && warn "Added connection '" . $conn->id . "'\n";

    return $cb->($conn);
}

sub join {
    my ($self, $conn, $room) = @_;

    $self->{rooms}{$room} //= {};
    $self->{rooms}{$room}{$conn->id} = $conn;
}

sub leave {
    my ($self, $conn, $room) = @_;

    my $id = blessed $conn ? $conn->id : $conn;

    delete $self->{rooms}{$room}{$id};
    delete $self->{rooms}{$room} unless keys %{$self->{rooms}{$room}};
}

sub remove_connection {
    my $self = shift;
    my ($conn, $cb) = @_;

    my $id = blessed $conn ? $conn->id : $conn;

    delete $self->{connections}->{$id};
    foreach my $room ( keys %{$self->{rooms}} ) {
        $self->leave($conn, $room);
    }

    DEBUG && warn "Removed connection '" . $id . "'\n";

    return $cb->() if $cb;
}

sub send {
    my $self = shift;

    foreach my $conn ($self->_connections) {
        next unless $conn->is_connected;

        $conn->socket->send(@_);
    }

    return $self;
}

sub emit {
    my $self  = shift;
    my $event = shift;

    $event = PocketIO::Message->new(
        type => 'event',
        data => {name => $event, args => [@_]}
    );

    $self->send($event);

    return $self;
}

sub room_send {
    my $self = shift;
    my $room = shift;

    foreach my $conn ( $self->_room_connections($room) ) {
        next unless $conn->is_connected;
        $conn->socket->send(@_);
    }
}
sub room_emit {
    my $self  = shift;
    my $room  = shift;
    my $event = shift;

    $event = PocketIO::Message->new(
        type => 'event',
        data => {name => $event, args => [@_]}
    );

    $self->room_send($room, $event);

    return $self;
}

sub broadcast {
    my $self    = shift;
    my $invoker = shift;

    foreach my $conn ($self->_connections) {
        next unless $conn->is_connected;
        next if $conn->id eq $invoker->id;

        $conn->socket->send(@_);
    }

    return $self;
}

sub _room_connections {
    my ($self, $room) = @_;

    return unless exists $self->{rooms}{$room};

    return values %{$self->{rooms}{$room}};
}

sub _connections {
    my $self = shift;

    return values %{$self->{connections}};
}

sub _build_connection {
    my $self = shift;

    return PocketIO::Connection->new(
        @_,
        pool                => $self,
        on_connect_failed   => sub { $self->remove_connection(@_) },
        on_reconnect_failed => sub {
            my $conn = shift;

            $conn->disconnected;

            $self->remove_connection($conn);
        }
    );
}

1;
__END__

=head1 NAME

PocketIO::Pool - Connection pool

=head1 DESCRIPTION

L<PocketIO::Pool> is a connection pool.

=head1 METHODS

=head2 C<new>

=head2 C<find_connection>

=head2 C<add_connection>

=head2 C<remove_connection>

=head2 C<connections>

=head2 C<send>

=head2 C<broadcast>

=cut
