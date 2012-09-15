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

use 5.008;
use strict;
use warnings;
use Test::More;

use lib 't';
use MyTestHelpers;
MyTestHelpers::nowarnings();


eval { require Wx }
  or plan skip_all => "due to Wx display not available -- $@";

plan tests => 9;

my $app = Wx::SimpleApp->new;
require Wx::Perl::PodBrowser;


#------------------------------------------------------------------------------
# VERSION

my $want_version = 3;
{
  is ($Wx::Perl::PodBrowser::VERSION, $want_version,
      'VERSION variable');
  is (Wx::Perl::PodBrowser->VERSION, $want_version,
      'VERSION class method');

  ok (eval { Wx::Perl::PodBrowser->VERSION($want_version); 1 },
      "VERSION class check $want_version");
  my $check_version = $want_version + 1000;
  ok (! eval { Wx::Perl::PodBrowser->VERSION($check_version); 1 },
      "VERSION class check $check_version");

  my $podtext = Wx::Perl::PodBrowser->new;
  is ($podtext->VERSION,  $want_version, 'VERSION object method');
  
  ok (eval { $podtext->VERSION($want_version); 1 },
      "VERSION object check $want_version");
  ok (! eval { $podtext->VERSION($check_version); 1 },
      "VERSION object check $check_version");
}


#-----------------------------------------------------------------------------
# Close()

{
  my $browser = Wx::Perl::PodBrowser->new;
  $browser->Show;
  $browser->Close;
  $app->Yield;

  require Scalar::Util;
  Scalar::Util::weaken ($browser);
  is ($browser, undef, 'garbage collect when weakened');
}

#-----------------------------------------------------------------------------
# popup_about()

{
  my $browser = Wx::Perl::PodBrowser->new;
  $browser->Show;
  $browser->popup_about; # check it works enough to open
  $browser->Close;
  $app->Yield;

  require Scalar::Util;
  Scalar::Util::weaken ($browser);
  is ($browser, undef, 'garbage collect when weakened, with about dialog');
}

#-----------------------------------------------------------------------------
# goto_own_pod()

{
  my $browser = Wx::Perl::PodBrowser->new;
  $browser->Show;

  $browser->goto_own_pod; # check it works enough to open

  # FIXME: segv on close while pod read is pending, or some such

  $app->Yield;
  $browser->Close;
  $app->Yield;
}

#-----------------------------------------------------------------------------

exit 0;
