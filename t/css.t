use lib '.';
use t::Helper;
use Mojo::Loader 'data_section';
use Mojolicious::Plugin::AssetPack::Util 'checksum';

plan skip_all => 'cpanm CSS::Minifier::XS' unless eval 'require CSS::Minifier::XS;1';

my $t = t::Helper->t(pipes => [qw(Css Combine)]);
my @assets = qw(d/x.css d/y.css d/already-min.css);

$t->app->asset->process;
$t->app->asset->process('xyz.css' => @assets);

# TODO: Is there a way to handle when both an input asset and a topic is called "app.css"?
# $t->app->asset->process('out.css' => 'app.css'); TODO: Is there a way to fix

$t->get_ok('/')->status_is(200)
  ->element_exists(qq(link[href="/asset/d508287fc7/css-0-one.css"]))
  ->element_exists(qq(link[href="/asset/ec4c05a328/css-0-two.css"]));

$t->get_ok($t->tx->res->dom->at('link')->{href})->status_is(200)->content_like(qr{aaa});

$ENV{MOJO_MODE} = 'Test_minify_from_here';
$t = t::Helper->t(pipes => ['Css']);
$t->app->asset->process('app.css' => @assets);
my $file = $t->app->asset->store->file('cache/x-026c9c3a29.css');
isa_ok($file, 'Mojo::Asset::File');
ok -e $file->path, 'cached file exists';

Mojo::Util::monkey_patch('CSS::Minifier::XS', minify => sub { die 'Not cached!' });
$t = t::Helper->t(pipes => [qw(Css Combine)]);
$t->app->asset->process('app.css' => @assets);

$t->app->routes->get('/inline' => 'inline');
$t->get_ok('/inline')->status_is(200)
  ->content_like(qr/\.one\{color.*\.two\{color.*.skipped\s\{/s);

$t->app->asset->process('app.css' => @assets);

$t->get_ok('/')->status_is(200)
  ->element_exists(qq(link[href="/asset/bb424de34b/app.css"]));

$t->get_ok($t->tx->res->dom->at('link')->{href})->status_is(200)
  ->header_is('Cache-Control', 'max-age=31536000')->header_is('Content-Type', 'text/css')
  ->content_like(qr/\.one\{color.*\.two\{color.*.skipped\s\{/s);

done_testing;

__DATA__
@@ index.html.ep
%= asset 'app.css'
@@ inline.html.ep
%= stylesheet sub { asset->processed('app.css')->map('content')->join }
@@ assetpack.def
! app.css
# some comment
< css-0-one.css       #some inline comment
<   css-0-two.css # other comment
@@ app.css
.err { content: "in conflict with topic ! app.css?"; }
@@ d/x.css
.one { color: #111; }
@@ d/y.css
.two { color: #222; }
@@ d/already-min.css
.skipped { color: #222; }
