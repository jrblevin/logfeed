#!/usr/bin/perl -w
#
# log-feed
# http://code.jblevins.org/log-feed/
#
# Author: Jason Blevins <jrblevin@sdf.lonestar.org>
# License: MIT
# Created: January 15, 2008
# Last Modified: January 15, 2008 22:12 EST

package logfeed;

use strict;
use File::stat;
use File::ReadBackwards;
use Date::Parse qw/str2time/;
use CGI qw/:standard/;

# Configuration variables
use vars qw! $log_file $feed_title $base_url $feed_path $feed_author
             @ref_ignore @ref_match @req_ignore @req_match @ua_ignore
             @ua_match $feed_author_email $feed_author_uri $feed_subtitle
             $feed_icon $num_entries $reverse_dns $show_ua $show_status
             $show_size $title !;

# Log regexp
my $reg = qr/^(\S+) (\S+) (\S+) \[([^\]\[]+)\] \"([^"]*)\" (\S+) (\S+) \"?([^"]*)\"? \"([^"]*)\"/;

# Escape HTML
my %escape = ( '<' => '&lt;',
	       '>' => '&gt;',
	       '&' => '&amp;',
	       '"' => '&quot;' );
my $escape_re  = join '|' => keys %escape;

my $colon = ":";

# Load the specified configuration file
my $conf = param('feed');
_status(404, "No configuration given") unless ($conf);
_status(404, "Invalid configuration file") unless (my $return = do $conf);

# Default title
$title = '$host: $fn' unless $title;

# Combine match/ignore regular expressions
my $ref_ignore_re  = join '|', @ref_ignore if @ref_ignore;
my $ref_match_re  = join '|', @ref_match if @ref_match;
my $req_ignore_re  = join '|', @req_ignore if @req_ignore;
my $req_match_re  = join '|', @req_match if @req_match;
my $ua_ignore_re  = join '|', @ua_ignore if @ua_ignore;
my $ua_match_re  = join '|', @ua_match if @ua_match;

# When running as a CGI script, set the content type.
if ($ENV{'SCRIPT_NAME'}) {
    print "Content-Type: application/atom+xml\r\n\r\n"
}

# Try to open the log file
my $log = File::ReadBackwards->new($log_file) or
  die "Can't read file: $log_file\n$!";

# <updated>: derive by stat()ing the file for its mtime:
my $updated_utc_date = _date_to_utc(stat("$log_file")->mtime);

# Print the header
print "<?xml version=\"1.0\" encoding=\"iso-8859-1\"?>\n";
print "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n";
print "  <link rel=\"self\" href=\"$base_url$feed_path\"/>\n";
print "  <id>$base_url$feed_path</id>\n";
print "  <icon>$feed_icon</icon>\n" if $feed_icon;
print "  <title>$feed_title</title>\n";
print "  <subtitle>$feed_subtitle</subtitle>\n" if $feed_subtitle;
print "  <author>\n" if $feed_author or $feed_author_email or $feed_author_uri;
print "    <name>$feed_author</name>\n" if $feed_author;
print "    <email>$feed_author_email</email>\n" if $feed_author_email;
print "    <uri>$feed_author_uri</uri>\n" if $feed_author_uri;
print "  </author>\n" if $feed_author or $feed_author_email or $feed_author_uri;
print "  <updated>$updated_utc_date</updated>\n";

my ($line, $ip, $rfc931, $user, $time, $fn, $code, $sz, $ref, $ua, $mode, $proto);


my $count = 0;
while (defined($line = $log->readline) and ($count < $num_entries) ) {
    ($ip, $rfc931, $user, $time, $fn, $code, $sz, $ref, $ua) = $line =~ $reg;
    ($mode,$fn,$proto) = split(' ', $fn);

    next if $ref_ignore_re and $ref =~ $ref_ignore_re;   # Ignored referrers
    next if $req_ignore_re and $fn =~ $req_ignore_re;    # Ignored requests
    next if $ua_ignore_re and $ua =~ $ua_ignore_re;      # Ignored user agents

    next unless !$ref_match_re or $ref =~ $ref_match_re; # Match referrers
    next unless !$req_match_re or $fn =~ $req_match_re;  # Match requests
    next unless !$ua_match_re or $ua =~ $ua_match_re;    # Match user agents

    # Parse the date
    my $utc_date = _date_to_utc(str2time($time));

    # Reverse DNS lookup
    my $host;
    if ($reverse_dns) {
	my @h = gethostbyaddr(pack('C4',split('\.',$ip)),2);
	$host = @h ? $h[0] : $ip;
    } else {
	$host = $ip;
    }

    # Escape <, >, &, and " in the referring URL and request filename.
    $ref =~ s/($escape_re)/$escape{$1}/g;
    $fn =~ s/($escape_re)/$escape{$1}/g;

    # Shorten the referrer by omitting CGI parameters
    my $short_ref = ($ref =~ m/(.*?)\?.*/) ? $1 : $ref;

    # Use $title as a template to create $entry_title.
    my $entry_title = $title;
    $entry_title =~ s/(\$\w+(?:::)?\w*)/"defined $1 ? $1 : ''"/gee;

    # Print the entry.  Note: if your site commonly gets several hits per
    # second, you may want to choose a new <id> tag here.
    print "  <entry>\n";
    print "    <id>$base_url$feed_path$colon$utc_date</id>\n";
    print "    <title>$entry_title</title>\n";
    print "    <updated>$utc_date</updated>\n";
    print "    <content type=\"xhtml\"><div xmlns=\"http://www.w3.org/1999/xhtml\">\n";
    print "    <ul>\n";
    print "      <li><strong>Date:</strong> $utc_date</li>\n";
    print "      <li><strong>User:</strong> $user</li>\n" if $user ne "-";
    print "      <li><strong>Host:</strong> $host</li>\n";
    print "      <li><strong>User Agent:</strong> $ua</li>\n" if $show_ua;
    print "      <li><strong>Referrer:</strong> <a href=\"$ref\">$ref</a></li>\n";
    print "      <li><strong>File:</strong> <a href=\"$base_url$fn\">$fn</a></li>\n";
    print "      <li><strong>Size:</strong> $sz</li>\n" if $show_size;
    print "      <li><strong>Status:</strong> $code</li>\n" if $show_status;
    print "    </ul>\n";
    print "    </div>\n";
    print "    </content>\n";
    print "    <link rel=\"alternate\" href=\"$ref\"/>\n";
    print "  </entry>\n";
    $count += 1;
}

$log->close();

print "</feed>\n";


sub _date_to_utc {
    my $time = shift;
    my @utc = gmtime($time);
    sprintf("%4d-%02d-%02dT%02d:%02d:%02dZ",
	    $utc[5]+1900, $utc[4]+1, $utc[3], $utc[2], $utc[1], $utc[0]);
}

sub _status {
    my ($code, $msg) = @_;
    print "Content-Type: text/plain\r\n" if ($code != 304);
    print "Status: $code $msg\r\n\r\n";
    print "$msg\n" if ($code != 304);
    exit 1;
}

__END__

=head1 NAME

log-feed

=head1 SYNOPSIS

Provides a custom Atom 1.0 feed by applying configurable filters to an Apache
log file.  log-feed can be used as a CGI script, running on a server, or as a
standalone script, for example, ran locally by a cron job.

=head1 VERSION

2008-01-15

=head1 AUTHORS

Jason Blevins <jrblevin@sdf.lonestar.org>, http://jblevins.org/

=head1 QUICKSTART

First, create a configuration file, say B<foo>, by using the B<example.conf>
file as a template.  Then run B<log-feed.pl> either locally, as in B<perl
log-feed.pl feed=foo> or as a CGI script: B<log-feed.pl?feed=foo>.

=head1 FURTHER CONFIGURATION

In order to clean up the URLs when running in CGI mode, one could write a
B<.htaccess> file using B<mod_rewrite>.  For example:

    RewriteRule ^feeds/(.*).atom$ feeds/log-feed.cgi?feed=$1.conf

Then, given a config file called, say, B<foo.conf>, the feed would be
made available at B</feeds/foo.atom>.

=head1 SEE ALSO

Atom 1.0 Specification:
http://atompub.org/2005/07/11/draft-ietf-atompub-format-10.html

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
