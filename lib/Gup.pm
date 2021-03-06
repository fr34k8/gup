use strict;
use warnings;
package Gup;

use Moo;
use Sub::Quote;
use MooX::Types::MooseLike::Base qw/Str HashRef ArrayRef/;

use Carp;
use Git::Repository;

use File::Path qw(mkpath);
use POSIX qw(strftime);

has name => (
    is       => 'ro',
    isa      => quote_sub( q{
      $_[0] =~ /^(?:[A-Za-z0-9_-]|\.)+$/ or die "Improper repo name: '$_[0]'\n"
    } ),
    required => 1,
);

has configfile => (
    is      => 'ro',
    isa     => Str,
    default => quote_sub(q{'/etc/gup/gup.yaml'}),
);

has repos_dir => (
    is      => 'ro',
    isa     => Str,
    default => quote_sub(q{'/var/gup/repos'}),
);

has repo => (
    is        => 'ro',
    isa       => Str,
    isa       => quote_sub( q{
        ref $_[0] and ref $_[0] eq 'Git::Repository'
            or die 'repo must be a Git::Repository object'
    } ),
    lazy      => 1,
    writer    => 'set_repo',
    predicate => 'has_repo',
    builder   => '_build_repo',
);

has repo_dir => (
    is      => 'ro',
    isa     => Str,
    lazy    => 1,
    builder => '_build_repo_dir',
);

has source_dir => (
    is        => 'ro',
    isa       => Str,
    predicate => 'has_source_dir',
);

has plugins => (
    is      => 'ro',
    isa     => ArrayRef,
    default => quote_sub( q{[]} ),
);

has plugins_args => (
    is      => 'ro',
    isa     => HashRef,
    default => quote_sub( q({}) ),
);

has plugins_objs => (
    is      => 'ro',
    isa     => ArrayRef,
    lazy    => 1,
    builder => '_build_plugins_objs',
);

sub _build_repo {
    my $self = shift;

    Git::Repository->new( work_tree => $self->repo_dir )
}

sub _build_repo_dir {
    my $self = shift;

    File::Spec->catdir( $self->repos_dir, $self->name );
};

sub _build_plugins_objs {
    my $self    = shift;
    my @plugins = ();

    foreach my $plugin ( @{ $self->plugins } ) {
        my $class = "Gup::Plugin::$plugin";

        local $@ = undef;
        eval "use $class";
        $@ and die "Failed loading plugin $class: $@\n";

        my %args =    $self->plugins_args->{$plugin}   ?
                   %{ $self->plugins_args->{$plugin} } :
                   ();

        push @plugins, $class->new(
            gup => $self,
            %args,
        );
    }

    return \@plugins;
}

sub find_plugins {
    my $self = shift;
    my $role = shift;

    $role =~ s/^-/Gup::Role::/;

    return grep { $_->does($role) } @{ $self->plugins_objs };
}

sub sync_repo {
    my $self = shift;

    $self->has_source_dir or croak 'Must provide a source_dir';

    # Run method before_sync on all plunigs with BeforeSync role
    $_->before_sync( $self->source_dir, $self->repo_dir )
        foreach ( $self->find_plugins('-BeforeSync' ) );

    # find all plugins that use a role Sync then run it
    foreach my $plugin ( $self->find_plugins('-Sync' ) ) {
        $plugin->sync( $self->source_dir, $self->repo_dir );
    }

    # Run method before_sync on all plunigs with AfterSync role
    $_->after_sync() foreach ( $self->find_plugins('-AfterSync' ) );

    $self;
}

# TODO: allow to control the git user and email for this
# creates a new repository
sub create_repo {
    my $self     = shift;
    my $repo_dir = $self->repo_dir;

    # make sure it doesn't exist
    -d $repo_dir and croak "Repo dir '$repo_dir' already exists";

    # create it
    mkpath($repo_dir) or croak "Can't mkdir $repo_dir: $!\n";

    # init new repo
    Git::Repository->run( init => $repo_dir );

    $self->repo->run( 'config', '--local', 'user.email', 'you@example.com' );
    $self->repo->run( 'config', '--local', 'user.name', 'Your Name' );

    # create HEAD and first commit
    $self->repo->run( 'symbolic-ref', 'HEAD', 'refs/heads/master' );
    $self->repo->run( commit => '--allow-empty', '-m', 'Initial commit' );

    $self;
}

sub update_repo {
    my $self = shift;

    # Sync repo before
    $self->sync_repo;

    # Commit updates
    $self->commit_updates(@_);

    $self;
}

sub commit_updates {
    my $self = shift;

    @_ % 2 == 0 or croak 'commit_updates() gets a hash as parameter';

    my %opts    = @_ ;
    my $message = defined $opts{'message'} ?
                  $opts{'message'}         :
                  'Gup commit: ' . strftime "%Y/%m/%d - %H:%M", localtime;

    # add all
    $self->repo->run( 'add', '-A' );

    # commit update
    $self->repo->run( 'commit', '-a', '-m', $message );

    $self;
}

1;

