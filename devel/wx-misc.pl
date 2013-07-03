#!/usr/bin/perl -w

# Copyright 2012, 2013 Kevin Ryde

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

use 5.008;
use strict;
use Wx;
use Wx::RichText;

# uncomment this to run the ### lines
use Devel::Comments;

my $str;

{
  my $attrs = Wx::RichTextAttr->new;
  my $url = $attrs->GetURL;
  ### $attrs
  ### $url
  exit 0;
}