#!/usr/bin/perl -w

# Copyright 2012 Kevin Ryde

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

use 5.008;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile
  (NAME         => 'Wx-Perl-PodBrowser',
   ABSTRACT     => 'POD browser in Wx.',
   VERSION_FROM => 'lib/Wx/Perl/PodBrowser.pm',
   AUTHOR       => 'Kevin Ryde <user42@zip.com.au>',
   LICENSE      => 'gpl',
   SIGN         => 1,
   MIN_PERL_VERSION => '5.008',

   PREREQ_PM    => {
                    'Wx' => 0,
                    'Wx::RichText' => 0,
                   },
   META_MERGE =>
   { resources =>
     { homepage => 'http://user42.tuxfamily.org/wx-perl-podbrowser/index.html',
       license  => 'http://www.gnu.org/licenses/gpl.html',
     },
     no_index => { directory=>['devel'] },

     optional_features =>
     {
      maximum_interoperation =>
      { description => 'All the optional things Wx-Perl-PodBrowser can use.',
        requires => {
                     'Software::License::GPL_3' => 0,
                    },
      },
     },
   },
  );
