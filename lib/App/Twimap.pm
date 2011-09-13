package App::Twimap;
use Moose;
use DateTime;
use DateTime::Format::Strptime;
use Email::Date::Format qw(email_date);
use Email::MIME;
use Email::MIME::Creator;
use Encode;
use HTML::Entities;
use List::Util qw(max);
use LWP::UserAgent;
use Web::oEmbed::Common;
use URI::WithBase;
has 'mail_imapclient' =>
    ( is => 'ro', isa => 'Mail::IMAPClient', required => 1 );
has 'net_twitter' => ( is => 'ro', isa => 'Net::Twitter', required => 1 );
has 'mailbox'     => ( is => 'ro', isa => 'Str',          required => 1 );

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

    my $subject        = $text;
    my $subject_offset = 0;
    my $text_offset    = 0;

    my $html;

    if ( $tweet->{entities} && $tweet->{entities}->{urls} ) {
        foreach my $entity ( @{ $tweet->{entities}->{urls} } ) {
            my $expanded_url = $entity->{expanded_url} || $entity->{url};
            next unless $expanded_url;
            $expanded_url = $self->expand_url($expanded_url);
            substr(
                $subject,
                $entity->{indices}->[0] + $subject_offset,
                $entity->{indices}->[1] - $entity->{indices}->[0]
            ) = $expanded_url;
            $subject_offset
                += length($expanded_url) - length( $entity->{url} );

            my $href = qq{<a href="$expanded_url">$expanded_url</a>};
            substr(
                $text,
                $entity->{indices}->[0] + $text_offset,
                $entity->{indices}->[1] - $entity->{indices}->[0]
            ) = $href;
            $text_offset += length($href) - length( $entity->{url} );

            my $consumer = Web::oEmbed::Common->new();

            #$consumer->set_embedly_api_key('0123ABCD0123ABCD0123ABCD');
            my $response = $consumer->embed($expanded_url);
            $html = encode_utf8( $response->render ) if $response;
        }
    }

    my $utf8_text = encode_utf8($text);

    my $body;
    if ($html) {
        $body
            = qq{$utf8_text\n<br/><br/>\n$html<br/><br/>\n\n<a href="$url">$url</a>};
    } else {
        $body = qq{$utf8_text\n<br/><br/>\n<a href="$url">$url</a>};
    }

    my $from = Email::Address->new( $name, "$screen_name\@twitter",
        "($screen_name)" );

    my @headers = (
        From         => $from,
        Subject      => decode_entities($subject),
        Date         => $date,
        'Message-Id' => "<$tid\@twitter>",
    );
    push @headers, 'In-Reply-To' => $in_reply_to if $in_reply_to;

    my $email = Email::MIME->create(
        attributes => {
            content_type => "text/html",
            disposition  => "inline",
            charset      => "utf-8",
        },
        header_str => \@headers,
        body       => $body,
    );
}

sub imap_tids {
    my $self    = shift;
    my $imap    = $self->mail_imapclient;
    my $mailbox = $self->mailbox;

    warn "Fetching message_ids...";

    $self->select_mailbox;

    my $message_ids
        = $imap->fetch_hash('BODY.PEEK[HEADER.FIELDS (Message-Id)]')
        or die "Fetch hash $mailbox error: ", $imap->LastError;

    my %tids;

    foreach my $uid ( keys %$message_ids ) {
        my $message_id
            = $message_ids->{$uid}->{'BODY[HEADER.FIELDS (MESSAGE-ID)]'};
        my ($tid) = $message_id =~ /Message-Id: <(\d+)\@twitter>/;
        next unless $tid;
        $tids{$tid} = 1;
    }
    return \%tids;
}

sub sync_home_timeline {
    my $self    = shift;
    my $twitter = $self->net_twitter;
    my $tids    = $self->imap_tids;

    my $since_id = max( keys %$tids );
    my $max_id   = 0;
    while (1) {
        warn
            "Fetching home timeline since id $since_id and max_id $max_id...";
        my $tweets;
        my $new_tweets = 0;
        while (1) {
            my $conf = {
                count            => 100,
                include_entities => 1
            };
            $conf->{since_id} = $since_id if $since_id;
            $conf->{max_id}   = $max_id   if $max_id;
            eval {
                $tweets = $twitter->home_timeline($conf);
                warn Dumper( $twitter->get_error ) unless $tweets;
            };
            last unless $@;
            warn $@;
            sleep 10;
        }

        foreach my $tweet (@$tweets) {

            #        warn encode_json($tweet);
            #use Data::Dumper; warn Dumper $tweet;
            #exit;
            my $tid = $tweet->{id};

            $max_id = $tid unless $max_id;
            $max_id = $tid if $tid < $max_id;

            next if $tids->{$tid};
            $new_tweets++;

            #warn $tid . ' ' . $tweet->{text};

            #use YAML;
            #warn Dump $tweet;

            my $email = $self->tweet_to_email($tweet);

            warn $email->as_string;
            $self->append_email($email);
            $tids->{$tid} = 1;
        }
        last unless $new_tweets;
        sleep 30;
    }
}

sub sync_replies {
    my $self    = shift;
    my $twitter = $self->net_twitter;
    my $imap    = $self->mail_imapclient;
    my $mailbox = $self->mailbox;
    my $tids    = $self->imap_tids;

    warn "Fetching in_reply_tos...";

    $self->select_mailbox;

    my @todo;
    my $replies = $imap->fetch_hash('BODY.PEEK[HEADER.FIELDS (IN-REPLY-TO)]')
        or die "Fetch hash $mailbox error: ", $imap->LastError;
    foreach my $uid ( keys %$replies ) {
        my $header = $replies->{$uid}->{'BODY[HEADER.FIELDS (IN-REPLY-TO)]'};
        my ($tid) = $header =~ /In-Reply-To: <(\d+)\@twitter>/;
        next unless $tid;
        push @todo, $tid;
    }

    foreach my $tid (@todo) {
        next if $tids->{$tid};
        warn "fetching $tid...";
        my $tweet = $twitter->show_status( $tid, { include_entities => 1 } );
        my $in_reply_to_status_id = $tweet->{in_reply_to_status_id};
        push @todo, $in_reply_to_status_id if $in_reply_to_status_id;
        my $email = $self->tweet_to_email($tweet);
        $self->append_email($email);
        $tids->{$tid} = 1;
        sleep 30;
    }
}

sub append_email {
    my ( $self, $email ) = @_;
    my $imap    = $self->mail_imapclient;
    my $mailbox = $self->mailbox;
    my $uid     = $imap->append_string( $mailbox, $email->as_string )
        or die "Could not append_string to $mailbox: ", $imap->LastError;
}

sub expand_url {
    my ( $self, $url ) = @_;
    my $ua = LWP::UserAgent->new(
        env_proxy             => 1,
        timeout               => 30,
        agent                 => "Twimap",
        requests_redirectable => [],
    );
    my $res = $ua->get($url);
    return $url unless $res->is_redirect;
    my $location = $res->header('Location');
    return $url unless defined $location;
    unless ( $location =~ /^http/ ) {
        my $uri = URI::WithBase->new( $location, $url )->abs;
        return $self->expand_url($uri);
    }
    return $self->expand_url($location);
}

sub select_mailbox {
    my $self    = shift;
    my $imap    = $self->mail_imapclient;
    my $mailbox = $self->mailbox;
    $imap->select($mailbox)
        or die "Select $mailbox error: ", $imap->LastError;
}

1;
