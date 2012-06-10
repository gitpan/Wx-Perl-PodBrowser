#!/usr/bin/perl -w

# Copyright 2012 Kevin Ryde

# This file is part of Wx-Perl-PodBrowser.
#
# Wx-Perl-PodBrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 3, or (at your option) any later
# version.
#
# Wx-Perl-PodBrowser is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with Wx-Perl-PodBrowser.  If not, see <http://www.gnu.org/licenses/>.

# Usage: wx-podbrowser.pl modulename_or_filename
#                         --file=filename
#                         --module=modulename
#                         --stdin

use 5.008;
use strict;
use warnings;
use Getopt::Long;
use Wx;
use Wx::Perl::PodBrowser;

my $app = Wx::SimpleApp->new;
$app->SetAppName(Wx::gettext('POD Browser'));

my $browser = Wx::Perl::PodBrowser->new;
$browser->Show;

my @goto_pod;
Getopt::Long::Configure ('no_ignore_case');
Getopt::Long::Configure ('pass_through');
Getopt::Long::GetOptions
  ('module=s' => sub {
     my ($optname, $value) = @_;
     @goto_pod = (module => $value);
   },
   'file=s' => sub {
     my ($optname, $value) = @_;
     @goto_pod = (filename => $value);
   },
   'stdin' => sub {
     my ($optname, $value) = @_;
     @goto_pod = (filehandle => \*STDIN);
   },
  )
  or return 1;

if (@ARGV) {
  @goto_pod = (guess => shift @ARGV);
}
$browser->goto_pod (@goto_pod);

$app->MainLoop;
exit 0;
