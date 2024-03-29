#!/usr/bin/perl -w

# Copyright 2012, 2013 Kevin Ryde

# This file is part of Wx-Perl-PodBrowser.
#
# Wx-Perl-PodBrowser is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3, or (at your option) any later
# version.
#
# Wx-Perl-PodBrowser is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with Wx-Perl-PodBrowser.  If not, see <http://www.gnu.org/licenses/>.


# Usage: perl screenshot.pl [outputfile.png]
#
# Draw a history widget and write it to the given output file in PNG format.
# The default output file is /tmp/screenshot.png

use 5.008;
use strict;
use warnings;
use POSIX ();
use Wx;
use FindBin;
use Wx::Perl::PodBrowser;

# uncomment this to run the ### lines
use Smart::Comments;

# PNG spec 11.3.4.2 suggests RFC822 (or rather RFC1123) for CreationTime
use constant STRFTIME_FORMAT_RFC822 => '%a, %d %b %Y %H:%M:%S %z';

my $progname = $FindBin::Script; # basename part
print "progname '$progname'\n";
my $output_filename = (@ARGV >= 1 ? $ARGV[0] : '/tmp/screenshot.png');

my $xwd_filename = '/tmp/screenshot.xwd';
my $time = POSIX::strftime (STRFTIME_FORMAT_RFC822, localtime(time));
my $software = "Generated by $progname";

my $app = Wx::SimpleApp->new;
$app->SetAppName(Wx::GetTranslation('POD Browser'));

my $browser = Wx::Perl::PodBrowser->new;
$browser->goto_pod (module => 'Wx::Perl::PodBrowser');
$browser->SetSize (520, 270);
$browser->Show;

print "Click on the browser window for xwd ...\n";
my $timer = Wx::Timer->new($app);
Wx::Event::EVT_TIMER
  ($app, -1,
   sub {
     system <<"HERE";
xwd -frame >$xwd_filename;
convert $xwd_filename $output_filename;
pngtextadd --keyword=Author --text='Kevin Ryde' $output_filename;
pngtextadd --keyword=Title  --text='Wx-Perl-PodBrowser Screenshot' $output_filename;
pngtextadd --keyword=Copyright --text='Copyright 2012, 2013 Kevin Ryde' $output_filename;
pngtextadd --keyword='Creation Time' --text='$time' $output_filename;
pngtextadd --keyword=Software --text='$software' $output_filename;
pngtextadd --keyword=Homepage --text='http://user42.tuxfamily.org/wx-perl-podbrowser/index.html' $output_filename;
xzgv $output_filename;
HERE
     $browser->Close;
   });
$timer->Start(100, # milliseconds
              Wx::wxTIMER_ONE_SHOT())
  or die "Oops, cannot start timer";
Wx::WakeUpIdle();

$app->MainLoop;
print "Output in $output_filename\n";
exit 0;
