#!/usr/bin/perl -w
#
# logfeed
# http://jblevins.org/projects/logfeed/
#
# Author: Jason Blevins <jrblevin@sdf.lonestar.org>
# License: MIT
# Created: January 15, 2008

package logfeed;

use vars qw! $log_file $feed_title $base_url $feed_path $feed_subtitle
             $feed_icon $author_name $author_uri $author_email $feed_author
             %ignore %match $num_entries $reverse_dns $ip $host $rfc931
             $user $time $utc_date $req $code $sz $ref $short_ref $ua $mode
             $proto $entry $colon $log_re $time_re !;

use strict;
use FileHandle;
use File::stat;
use CGI qw/:standard/;
use Time::Local;
use File::ReadBackwards;

my $version = '1.16';

my $colon = ":";

my %month2num = (
    'Jan' => '01',
    'Feb' => '02',
    'Mar' => '03',
    'Apr' => '04',
    'May' => '05',
    'Jun' => '06',
    'Jul' => '07',
    'Aug' => '08',
    'Sep' => '09',
    'Oct' => '10',
    'Nov' => '11',
    'Dec' => '12',
);

# Log regular expressions.  Example:
#
# 122.152.128.49 - - [31/Dec/2007:16:05:21 -0500] "GET /robots.txt HTTP/1.1" 200 114 "-" "Baiduspider+(+http://www.baidu.com/search/spider_jp.html)"
$log_re = qr/^(\S+) (\S+) (\S+) \[([^\]\[]+)\] \"([^"]*)\" (\S+) (\S+) \"?([^"]*)\"? \"([^"]*)\"/;
$time_re = qr#^(\d{2})/(\w{3})/(\d{4}):(\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})$#;


# Escape HTML
my %escape = ( '<' => '&lt;', '>' => '&gt;', '&' => '&amp;', '"' => '&quot;' );
my $escape_re  = join '|' => keys %escape;

# Determine the feed name
my $conf = param('conf');

# Try to load the corresponding configuration file
status(404, "No configuration given") unless ($conf);
%match = ();
%ignore = ();
status(404, "Invalid configuration file") unless (my $return = do "$conf");

# Defaults for optional configuration variables
$num_entries = 50 || $num_entries;
$reverse_dns = 0 || $reverse_dns;
$feed_subtitle = $feed_subtitle ? "  <subtitle>$feed_subtitle</subtitle>" : '';
$feed_icon = $feed_icon ? "  <icon>$feed_icon</icon>" : '';
$author_uri = $author_uri ? "<uri>$author_uri</uri>" : '';
$author_email = $author_email ? "<uri>$author_uri</uri>" : '';
$entry = '<entry>
    <id>$base_url$feed_path$colon$utc_date</id>
    <title>$host: $req</title>
    <author>
      <name>$author_name</name>
      $author_uri$author_email
    </author>
    <updated>$utc_date</updated>
    <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">
    <ul>
      <li><strong>Date:</strong> $utc_date</li>
      <li><strong>User:</strong> $user</li>
      <li><strong>Host:</strong> $host</li>
      <li><strong>User Agent:</strong> $ua</li>
      <li><strong>Referrer:</strong> <a href="$ref">$ref</a></li>
      <li><strong>File:</strong> <a href="$base_url$req">$base_url$req</a></li>
      <li><strong>Size:</strong> $sz</li>
      <li><strong>Status:</strong> $code</li>
    </ul>
    </div>
    </content>
    <link rel="alternate" href="$ref"/>
  </entry>
' unless $entry;

# When running as a CGI script, set the content type
if ($ENV{'SCRIPT_NAME'}) {
    print "Content-Type: application/atom+xml\r\n\r\n"
}

# Try to open the log file
my $log = File::ReadBackwards->new($log_file) or
  status(404, "Error reading log");

# <updated>: derive by stat()ing the file for its mtime:
my $updated_utc_date = time_to_utc(stat($log_file)->mtime);

# Print the header
print "<?xml version=\"1.0\" encoding=\"iso-8859-1\"?>
<feed xmlns=\"http://www.w3.org/2005/Atom\">
  <link rel=\"self\" href=\"$base_url$feed_path\"/>
  <id>$base_url$feed_path</id>
  <generator uri=\"http://jblevins.org/projects/logfeed/\" version=\"$version\">logfeed</generator>
  <updated>$updated_utc_date</updated>
  <title>$feed_title</title>
  $feed_subtitle
  $feed_icon";

my $count = 0;
while (defined(my $line = $log->readline) and ($count < $num_entries) ) {
    ($ip, $rfc931, $user, $time, $req, $code, $sz, $ref, $ua) = $line =~ $log_re;
    ($mode,$req,$proto) = split(' ', $req);

    # Apply ignore filters
    next if $ignore{'ip'} && $ip =~ $ignore{'ip'};
    next if $ignore{'user'} && $user =~ $ignore{'user'};
    next if $ignore{'req'} && $req =~ $ignore{'req'};
    next if $ignore{'code'} && $code =~ $ignore{'code'};
    next if $ignore{'ref'} && $ref =~ $ignore{'ref'};
    next if $ignore{'ua'} && $ua =~ $ignore{'ua'};

    # Apply match filters
    next unless !$match{'ip'} || $ip =~ $match{'ip'};
    next unless !$match{'user'} || $user =~ $match{'user'};
    next unless !$match{'req'} || $req =~ $match{'req'};
    next unless !$match{'code'} || $code =~ $match{'code'};
    next unless !$match{'ref'} || $ref =~ $match{'ref'};
    next unless !$match{'ua'} || $ua =~ $match{'ua'};

    # Parse the date
    $utc_date = logtime_to_utc($time);

    # Reverse DNS lookup
    if ($reverse_dns) {
	my @h = gethostbyaddr(pack('C4',split('\.',$ip)),2);
	$host = @h ? $h[0] : $ip;
    } else {
	$host = $ip;
    }

    # Escape <, >, &, and ":
    $ref =~ s/($escape_re)/$escape{$1}/g;
    $req =~ s/($escape_re)/$escape{$1}/g;
    $ua =~ s/($escape_re)/$escape{$1}/g;

    # Shorten the referrer by omitting CGI parameters
    $short_ref = ($ref =~ m/(.*?)\?.*/) ? $1 : $ref;

    # Print the entry.
    print interpolate($entry);
    $count += 1;
}

$log->close();

print "</feed>\n";


# Converts times of the form "17/Jan/2008:17:15:04 -0500" to the
# format required by the Atom specification.
sub logtime_to_utc {
    my $logtime = shift;
    my ($day, $mo, $yr, $hr, $min, $sec, $pm, $tzhr, $tzmin) = $logtime =~ $time_re;
    $mo = $month2num{$mo};
    my $time = timegm($sec, $min, $hr, $day, $mo, $yr);

    my $offset = $tzhr * 60*60 + $tzmin * 60;
    if ($pm eq "+") {
	$time -= $offset;
    } else {
	$time += $offset;
    }
    time_to_utc($time);
}


# Converts times to the format required by the Atom specification.
sub time_to_utc {
    my $time = shift;
    my @utc = gmtime($time);
    sprintf("%4d-%02d-%02dT%02d:%02d:%02dZ",
	    $utc[5]+1900, $utc[4]+1, $utc[3], $utc[2], $utc[1], $utc[0]);
}

# Return a status code and exit
sub status {
    my ($code, $msg) = @_;
    print "Content-Type: text/plain\r\n" if ($code != 304);
    print "Status: $code $msg\r\n\r\n";
    print "$msg\n" if ($code != 304);
    exit 1;
}

# Borrowed from Blosxom's interpolate() routine.
sub interpolate {
    my $template = shift;
    $template =~ s/(\$\w+(?:::)?\w*)/"defined $1 ? $1 : ''"/gee;
    return $template;
}

__END__

=head1 NAME

log-feed

=head1 SYNOPSIS

Provides a custom Atom 1.0 feed by applying configurable filters to an Apache
log file.  log-feed can be used as a CGI script, running on a server, or as a
standalone script, for example, ran locally by a cron job.

=head1 VERSION

1.16

=head1 AUTHORS

Jason Blevins <jrblevin@sdf.lonestar.org>, http://jblevins.org/

=head1 QUICKSTART

First, create a configuration file, say B<foo>, by using the B<example.conf>
file as a template.  Then run B<log-feed.pl> either locally, as in B<perl
log-feed.pl conf=foo> or as a CGI script: B<log-feed.pl?conf=foo>.

=head1 FURTHER CONFIGURATION

In order to clean up the URLs when running in CGI mode, one could write a
B<.htaccess> file using B<mod_rewrite>.  For example:

    RewriteRule ^feeds/(.*).atom$ feeds/log-feed.cgi?conf=$1.conf

Then, given a config file called, say, B<foo.conf>, the feed would be
made available at B</feeds/foo.atom>.

=head1 BUGS

Address bug reports and comments to the author.

=head1 LICENSE

Copyright (C) 2008 Jason Blevins

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
