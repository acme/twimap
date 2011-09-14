package App::Twimap;
use Moose;
use App::Twimap::Tweet;
use Email::MIME;
use Email::MIME::Creator;
use Encode;
use List::Util qw(max);
use LWP::UserAgent;
use Web::oEmbed::Common;
use URI::WithBase;
has 'mail_imapclient' =>
    ( is => 'ro', isa => 'Mail::IMAPClient', required => 1 );
has 'net_twitter' => ( is => 'ro', isa => 'Net::Twitter', required => 1 );
has 'mailbox'     => ( is => 'ro', isa => 'Str',          required => 1 );

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

        foreach my $data (@$tweets) {
            my $tweet = App::Twimap::Tweet->new( data => $data );
            my $tid = $tweet->id;

            $max_id = $tid unless $max_id;
            $max_id = $tid if $tid < $max_id;

            next if $tids->{$tid};
            $new_tweets++;

            my $email = $tweet->to_email;
            $self->append_email($email);
            $tids->{$tid} = 1;
        }
        last unless $new_tweets;
        warn "sleeping...";
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
        my $data = $twitter->show_status( $tid, { include_entities => 1 } );
        my $tweet = App::Twimap::Tweet->new( data => $data );
        push @todo, $tweet->in_reply_to_status_id
            if $tweet->in_reply_to_status_id;
        my $email = $tweet->to_email;
        $self->append_email($email);
        $tids->{$tid} = 1;
        warn "sleeping...";
        sleep 30;
    }
}

sub append_email {
    my ( $self, $email ) = @_;
    my $imap    = $self->mail_imapclient;
    my $mailbox = $self->mailbox;

    my $uid
        = $imap->append_string( $mailbox, encode_utf8( $email->as_string ) )
        or die "Could not append_string to $mailbox: ", $imap->LastError;
}

sub select_mailbox {
    my $self    = shift;
    my $imap    = $self->mail_imapclient;
    my $mailbox = $self->mailbox;
    $imap->select($mailbox)
        or die "Select $mailbox error: ", $imap->LastError;
}

__PACKAGE__->meta->make_immutable;

1;
