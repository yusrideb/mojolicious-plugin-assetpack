package Mojolicious::Plugin::AssetPack::Pipe::Store;
use Mojo::Base 'Mojolicious::Plugin::AssetPack::Pipe';
use Mojolicious::Plugin::AssetPack::Util qw(checksum diag DEBUG);

use Mojo::Util qw(url_escape url_unescape);

use constant DEV_MODE    => 'n';
use constant INPUT       => 'i';
use constant MINIFY_MODE => 'm';
use constant NOT_IN_USE  => 'x';

has _db => sub {
  my $self = shift;
  my $pipes = checksum join ':', map {ref} @{$self->assetpack->pipes};
  my %db;

  if (my $asset = $self->assetpack->store->asset($self->_db_asset->url)) {
    diag 'Load "%s" = 1', $asset->path || $asset->url if DEBUG;
    $self->_db_asset($asset);

    # $line = "$url = $input_sum,$normal_sum,$minified_sum\n"
    for my $row (split /\n/, $asset->content) {
      diag "db >>> $row" if DEBUG > 2;
      my ($url, $sums) = split /\s+/, $row, 2;
      $url = url_unescape $url;
      $db{$url}{$1} = $2 while ($sums =~ /(\w)=(\w+)/g);
    }
  }

  $self->{pipes_changed} = ($db{pipes}{p} && $db{pipes}{p} ne $pipes) ? 1 : 0;
  $db{pipes} = {NOT_IN_USE() => 0, p => $pipes};

  return \%db;
};

has _db_asset => sub { shift->assetpack->store->asset_class->new(url => 'assetpack.db') };

sub after_process {
  my ($self, $assets) = @_;
  my $db    = $self->_db;
  my $index = $self->assetpack->minify ? MINIFY_MODE : DEV_MODE;
  my $store = $self->assetpack->store;

  $assets->each(
    sub {
      my ($asset, $i) = @_;
      my $url = $asset->url;
      my $prev = $db->{$url}{$index} || '';
      $db->{$url}{$index} = $asset->checksum;
      $store->save($asset, {path => _cached_path($asset, $index)})
        if $prev ne $asset->checksum;
    }
  );

  my @db = map {
    my $row = $db->{$_};
    my $url = url_escape $_, '^A-Za-z0-9\-._~/';
    $row->{NOT_IN_USE()} //= 1;
    $row = join ' ', $url, map {"$_=$row->{$_}"} sort keys %$row;
    diag "db <<< $row" if DEBUG;
    "$row\n";
  } sort keys %$db;

  $store->save($self->_db_asset->content(join '', @db));
}

sub before_process {
  my ($self, $assets) = @_;
  my $db    = $self->_db;
  my $index = $self->assetpack->minify ? MINIFY_MODE : DEV_MODE;
  my $store = $self->assetpack->store;

  $self->app->log->warn('[AssetPack::Store] Pipes changed.') if $self->{pipes_changed};
  $assets->each(
    sub {
      my ($asset, $i) = @_;
      my $url = $asset->url;
      $db->{$url}{INPUT()}      = $asset->checksum;
      $db->{$url}{NOT_IN_USE()} = 0;
      return unless my $cached = $store->asset(_cached_path($asset, $index));
      return unless $cached->checksum eq ($db->{$url}{$index} || '');
      $asset->content($cached->content)->processed(1);
      if ($self->{pipes_changed}) {
        $self->app->log->warn(
          sprintf '[AssetPack::Store] Cached asset %s might be invalid.',
          $cached->url);
      }
    }
  );
}

sub _cached_path {
  my ($asset, $index) = @_;
  sprintf 'cache/%s-%s.%s', $_[0]->name, checksum($_[0]->url),
    $index eq MINIFY_MODE ? 'min' : 'dev';
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::AssetPack::Pipe::Store - Load and save assets

=head1 DESCRIPTION

L<Mojolicious::Plugin::AssetPack::Pipe::Store> will load and save assets from
the store.

=head1 METHODS

=head2 after_process

See L<Mojolicious::Plugin::AssetPack::Pipe/after_process>.

=head2 before_process

See L<Mojolicious::Plugin::AssetPack::Pipe/before_process>.

=head1 SEE ALSO

L<Mojolicious::Plugin::AssetPack>.

=cut
