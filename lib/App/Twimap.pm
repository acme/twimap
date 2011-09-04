package App::Twimap;
use Moose;
use DateTime;
use DateTime::Format::Strptime;
use Email::Date::Format qw(email_date);
use Email::MIME;
use Email::MIME::Creator;
use Encode;
use HTML::Entities;
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
            = 'RT '
            . $tweet->{retweeted_status}->{user}->{screen_name} . ': '
            . $tweet->{retweeted_status}->{text};
    } else {
        $text = $tweet->{text};
    }

    if ( $tweet->{entities} && $tweet->{entities}->{urls} ) {
        foreach my $entity ( @{ $tweet->{entities}->{urls} } ) {
            substr(
                $text,
                $entity->{indices}->[0],
                $entity->{indices}->[1] - $entity->{indices}->[0]
            ) = $entity->{expanded_url};
        }
    }

    my $plain_text      = decode_entities($text);
    my $utf8_plain_text = encode_utf8($plain_text);

    my $email = Email::MIME->create(
        attributes => {
            content_type => "text/plain",
            disposition  => "inline",
            charset      => "utf-8",
        },
        header => [
            From    => Email::Address->new( $name, "$screen_name\@twitter" ),
            Subject => $utf8_plain_text,
            Date    => $date,
            'Message-Id'  => "<$tid\@twitter>",
            'In-Reply-To' => $in_reply_to,
        ],
        body => $utf8_plain_text . "\n\n$url",
    );
}

1;
