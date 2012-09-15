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

use 5.004;
use strict;
use Wx;
use Wx::RichText;

# uncomment this to run the ### lines
use Devel::Comments;

{
  my $app = Wx::SimpleApp->new;
  my $self = Wx::Frame->new(undef, Wx::wxID_ANY(), 'Pod');
  my $search = Wx::SearchCtrl->new ($self,
                                    Wx::wxID_ANY(),
                                    '', # initial value
                                    Wx::wxDefaultPosition(),
                                    Wx::wxDefaultSize(),
                                    Wx::wxTE_PROCESS_ENTER());
  $search->ShowCancelButton(1);

  Wx::Event::EVT_SEARCHCTRL_SEARCH_BTN( $self, $search, sub {
                                          my ($self, $event) = @_;
                                          print "search\n";
                                        });
  Wx::Event::EVT_SEARCHCTRL_CANCEL_BTN( $self, $search, sub {
                                          my ($self, $event) = @_;
                                          print "cancel\n";
                                        } );
  Wx::Event::EVT_TEXT_ENTER( $self, $search, sub {
                               my ($self, $event) = @_;
                               print "enter\n";
                             } );
  $search->SetFocus;
  $self->Show;
  $app->MainLoop;
  exit 0;
}

