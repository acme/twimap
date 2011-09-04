#!/home/acme/perl-5.12.3/bin/perl
use strict;
use warnings;
use 5.12.0;
use lib 'lib';
use App::Twimap;
use Data::Dumper;
use Test::More;
use Test::Differences::Color;

my $twimap = App::Twimap->new();

my $tweet = {
    'retweeted' => 0,
    'source' =>
        '<a href="http://www.echofon.com/" rel="nofollow">Echofon</a>',
    'favorited'     => 0,
    'coordinates'   => undef,
    'place'         => undef,
    'retweet_count' => 0,
    'entities'      => {
        'hashtags'      => [],
        'user_mentions' => [],
        'urls'          => [
            {   'display_url'  => 'lockerz.com/s/135515455',
                'expanded_url' => 'http://lockerz.com/s/135515455',
                'url'          => 'http://t.co/kkxnMoL',
                'indices'      => [ 10, 29 ]
            }
        ]
    },
    'truncated'                 => 0,
    'created_at'                => 'Sat Sep 03 19:39:51 +0000 2011',
    'in_reply_to_status_id_str' => undef,
    'contributors'              => undef,
    'text'                      => 'Breakfast http://t.co/kkxnMoL',
    'in_reply_to_user_id'       => undef,
    'user'                      => {
        'friends_count'       => 505,
        'follow_request_sent' => 0,
        'profile_image_url' =>
            'http://a3.twimg.com/profile_images/427205513/arty_normal.jpg',
        'profile_background_image_url_https' =>
            'https://si0.twimg.com/profile_background_images/38511862/antisocial.gif',
        'profile_sidebar_fill_color' => 'e0ff92',
        'profile_background_color'   => '6699cc',
        'notifications'              => 0,
        'url'                        => 'http://thegestalt.org/simon/',
        'id'                         => 9066762,
        'is_translator'              => 0,
        'following'                  => 1,
        'screen_name'                => 'deflatermouse',
        'lang'                       => 'en',
        'location'                   => 'San Francisco',
        'followers_count'            => 583,
        'statuses_count'             => 1852,
        'name'                       => 'Simon Wistow',
        'description'                => '',
        'favourites_count'           => 2,
        'profile_background_tile'    => 0,
        'listed_count'               => 44,
        'contributors_enabled'       => 0,
        'profile_link_color'         => '0000ff',
        'profile_image_url_https' =>
            'https://si0.twimg.com/profile_images/427205513/arty_normal.jpg',
        'profile_sidebar_border_color' => '87bc44',
        'created_at'                   => 'Mon Sep 24 09:59:53 +0000 2007',
        'utc_offset'                   => -28800,
        'verified'                     => 0,
        'show_all_inline_media'        => 0,
        'profile_background_image_url' =>
            'http://a3.twimg.com/profile_background_images/38511862/antisocial.gif',
        'default_profile'              => 0,
        'protected'                    => 0,
        'id_str'                       => '9066762',
        'profile_text_color'           => '000000',
        'default_profile_image'        => 0,
        'time_zone'                    => 'Pacific Time (US & Canada)',
        'geo_enabled'                  => 0,
        'profile_use_background_image' => 1
    },
    'id'                      => '110074547411238913',
    'in_reply_to_status_id'   => undef,
    'geo'                     => undef,
    'possibly_sensitive'      => 0,
    'in_reply_to_user_id_str' => undef,
    'id_str'                  => '110074547411238913',
    'in_reply_to_screen_name' => undef
};

my $email = $twimap->tweet_to_email($tweet);

eq_or_diff(
    $email->as_string, 'From: "Simon Wistow" <deflatermouse@twitter>
Subject: Breakfast http://lockerz.com/s/135515455
Date: Sat, 3 Sep 2011 20:39:51 +0100
Message-Id: <110074547411238913@twitter>
In-Reply-To: 
MIME-Version: 1.0
Content-Type: text/html; charset="utf-8"
Content-Disposition: inline

Breakfast <a href="http://lockerz.com/s/135515455">http://lockerz.com/s/135515455</a>
<br/><br/>
<a href="http://c0013938.cdn1.cloudfiles.rackspacecloud.com/x2_813cd3f" title="x2_813cd3f"><img alt="x2_813cd3f" height="79" src="http://c0013942.cdn1.cloudfiles.rackspacecloud.com/x2_813cd3f" width="79" /></a><br/><br/>

<a href="https://twitter.com/deflatermouse/status/110074547411238913">https://twitter.com/deflatermouse/status/110074547411238913</a>'
);

done_testing();
