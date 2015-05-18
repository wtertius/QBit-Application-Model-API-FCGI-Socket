package Exception::API::FCGI::Socket;
use base qw(Exception::API);

package QBit::Application::Model::API::FCGI::Socket;

use qbit;

use base qw(QBit::Application::Model::API);

use IO::Socket;
use FCGI::Client;
use HTTP::Response;

sub request {
    my ($self, $uri, %params) = @_;

    throw Exception::API::FCGI::Socket gettext("Option 'socket' isn't defined for %s", ref($self))
      unless defined($self->get_option('socket'));
    throw Exception::API::FCGI::Socket gettext('No socket for %s', ref($self)) unless -S $self->get_option('socket');

    my $socket = IO::Socket::UNIX->new("Type" => SOCK_STREAM, Peer => $self->get_option('socket'));
    $socket or die $!;

    my $client = FCGI::Client::Connection->new(sock => $socket, timeout => $self->get_option('timeout', 7));

    my ($stdout, $stderr) = $client->request(
        {
            REQUEST_METHOD => 'GET',
            REQUEST_URI    => $uri,
            QUERY_STRING   => $self->_query_string(%params),
            SCHEME         => 'https',
            SERVER_NAME    => hostname(),
            SERVER_PORT    => 443,
            REMOTE_ADDR    => '127.0.0.1',
        },
        ''
    );

    throw Exception::API::FCGI::Socket $stderr if defined($stderr);
    $socket->close();

    my $response = HTTP::Response->parse($stdout);

    return $response;
}

sub call {
    my ($self, $uri, %params) = @_;

    return $self->get($uri, %params);
}

sub get {
    my ($self,    $uri,     %params)   = @_;
    my ($retries, $content, $response) = (0);

    while (($retries < $self->get_option('attempts', 3)) && !defined($content)) {
        sleep($self->get_option('delay', 1)) if $retries++;
        $response = $self->request($uri, %params);

        if ($response->is_success()) {
            $content = $response->decoded_content();
            last;
        }
        if ($response->code == 408 && !$self->get_option('timeout_retry')) {
            last;
        }
    }

    $self->log(
        {
            socket       => $self->get_option('socket'),
            uri          => $uri,
            query_string => $self->_query_string(%params),
            status       => $response->code,
            response     => $response->headers->as_string,
            (defined($content) ? (content => $content) : (error => $response->status_line)),
        }
    ) if $self->can('log');

    throw Exception::API::FCGI::Socket $response->status_line unless defined($content);

    utf8::decode($content);

    return $content;
}

sub _query_string {
    my ($self, %params) = @_;

    return join('&', map {$_ . '=' . uri_escape($params{$_})} keys(%params)) || '';
}

TRUE;
