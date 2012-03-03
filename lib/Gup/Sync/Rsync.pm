use strict;
use warnings;
package Gup::Sync::Rsync;
use Moo;
use Sub::Quote;
use Time::HiRes qw( usleep );

extends 'Gup::Sync';

has host => (
    is       => 'ro',
    isa      => quote_sub( q{
        $_[0] =~ /^(?:[A-Za-z0-9_-]|\.)*$/ or die "Improper host: '$_[0]'\n";
    } ),
    required => 1,
);

has user => (
    is       => 'ro',
    isa      => quote_sub( q{
        $_[0] =~ /^(?:[A-Za-z0-9_-]|\.)*$/ or die "Improper user: '$_[0]'\n";
    } ),
    required => 1,
);

has dir => (
    is       => 'ro',
    isa      => quote_sub( q{
        $_[0] =~ /^(?:[A-Za-z0-9_-]|\.|\/)+$/ or die "Improper dir: '$_[0]'\n";
    } ),
    required => 1,
);

has args => (
    is       => 'ro',
    default  => quote_sub(q{'-ac'}),
    isa      => quote_sub( q{
        $_[0] =~ /^(?:[A-Za-z0-9_-]|\.|\/)*$/ or die "Improper args: '$_[0]'\n";
    } ),
);

sub sync_dir {
    my $self = shift;
    my $args = $self->args;
    my $host = $self->host;
    my $user = $self->user;
    my $path = $self->dir.'/';

    $path = $host.':'.$path
        if $host ne '';
    $path = $user.'@'.$path
        if $host ne '' && $user ne '';

    # currently we hardcode rsync
    my $cmd = System::Command->new(
        'rsync',
        $args,
        $path,'.',
        '--quiet',
        '--delete',
        '--exclude','.git',
    );

    print 'Geting data...';
    while( not $cmd->is_terminated() ){ print '.'; usleep(500000); }
    print " done\n";
}

1;
