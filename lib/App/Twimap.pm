package App::Twimap;
use Moose;
use DateTime;
use DateTime::Format::Strptime;
use Email::Date::Format qw(email_date);
use Email::MIME;
use Email::MIME::Creator;
use Encode;
use HTML::Entities;
use Web::oEmbed::Common;
has 'mail_imapclient' => ( is => 'ro', isa => 'Mail::IMAPClient' );
has 'net_twitter'     => ( is => 'rw', isa => 'Net::Twitter' );

my $parser = DateTime::Format::Strptime->new(
    pattern  => '%a %b %d %T %z %Y',
    locale   => 'en_GB',
    on_error => 'croak',
);

sub tweet_to_email {
    my ( $self, $tweet ) = @_;

    my $tid = $tweet->{id};

    my $epoch       = $parser->parse_datetime( $tweet->{created_at} )->epoch;
    my $date        = email_date($epoch);
    my $name        = encode_utf8( $tweet->{user}->{name} );
    my $screen_name = encode_utf8( $tweet->{user}->{screen_name} );

    my $in_reply_to_status_id = $tweet->{in_reply_to_status_id};
    my $in_reply_to
        = $in_reply_to_status_id
        ? "<$in_reply_to_status_id\@twitter>"
        : '';
    my $url = "https://twitter.com/$screen_name/status/$tid";
    my $text;
    if ( $tweet->{retweeted_status} ) {
        $text
            = 'RT @'
            . $tweet->{retweeted_status}->{user}->{screen_name} . ': '
            . $tweet->{retweeted_status}->{text};
    } else {
        $text = $tweet->{text};
    }

    my $subject = $text;

    my $html;

    if ( $tweet->{entities} && $tweet->{entities}->{urls} ) {
        foreach my $entity ( @{ $tweet->{entities}->{urls} } ) {
            my $expanded_url = $entity->{expanded_url} || $entity->{url};
            next unless $expanded_url;
            substr(
                $subject,
                $entity->{indices}->[0],
                $entity->{indices}->[1] - $entity->{indices}->[0]
            ) = $expanded_url;
            substr(
                $text,
                $entity->{indices}->[0],
                $entity->{indices}->[1] - $entity->{indices}->[0]
            ) = qq{<a href="$expanded_url">$expanded_url</a>};
            my $consumer = Web::oEmbed::Common->new();
            $consumer->set_embedly_api_key('0123ABCD0123ABCD0123ABCD');
            my $response = $consumer->embed($expanded_url);
            $html = encode_utf8( $response->render ) if $response;
        }
    }

    my $utf8_subject = encode_utf8( decode_entities($subject) );
    my $utf8_text    = encode_utf8($text);

    my $body;
    if ($html) {
        $body
            = qq{$utf8_text\n<br/><br/>\n$html<br/><br/>\n\n<a href="$url">$url</a>};
    } else {
        $body = qq{$utf8_text\n<br/><br/>\n<a href="$url">$url</a>};
    }

    my $email = Email::MIME->create(
        attributes => {
            content_type => "text/html",
            disposition  => "inline",
            charset      => "utf-8",
        },
        header => [
            From => Email::Address->new(
                $name, "$screen_name\@twitter", "($screen_name)"
            ),
            Subject       => $utf8_subject,
            Date          => $date,
            'Message-Id'  => "<$tid\@twitter>",
            'In-Reply-To' => $in_reply_to,
        ],
        body => $body,
    );
}

1;
