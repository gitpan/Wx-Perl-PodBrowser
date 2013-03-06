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


package Wx::Perl::PodRichText;
use 5.008;
use strict;
use warnings;
use Carp;
use List::Util 'max';
use Wx;
use Wx::RichText;

use base 'Wx::RichTextCtrl';
our $VERSION = 11;

use base 'Exporter';
our @EXPORT_OK = ('EVT_PERL_PODRICHTEXT_CHANGED');

# uncomment this to run the ### lines
# use Smart::Comments;


#------------------------------------------------------------------------------
# changed event
# not documented yet

my $changed_eventtype = Wx::NewEventType;

# this works, not sure if it's quite right
sub EVT_PERL_PODRICHTEXT_CHANGED ($$$) {
  my ($self, $target, $func) = @_;
  $self->Connect($target, -1, $changed_eventtype, $func);
}
{
  package Wx::Perl::PodRichText::ChangedEvent;
  use strict;
  use warnings;
  use base 'Wx::PlCommandEvent';
  our $VERSION = 11;
  sub GetWhat {
    my ($self) = @_;
    return $self->{'what'};
  }
  sub SetWhat {
    my ($self, $newval) = @_;
    $self->{'what'} = $newval;
  }
}
sub emit_changed {
  my ($self, $what) = @_;
  my $event = Wx::Perl::PodRichText::ChangedEvent->new
    ($changed_eventtype, $self->GetId);
  $event->SetWhat($what);
  $self->GetEventHandler->ProcessEvent($event);
}


#------------------------------------------------------------------------------

sub new {
  my ($class, $parent, $id) = @_;
  if (! defined $id) { $id = Wx::wxID_ANY(); }
  my $self = $class->SUPER::new ($parent,
                                 $id,
                                 Wx::GetTranslation('Nothing selected'),
                                 Wx::wxDefaultPosition(),
                                 Wx::wxDefaultSize(),
                                 (Wx::wxTE_AUTO_URL()
                                  | Wx::wxTE_MULTILINE()
                                  | Wx::wxTE_READONLY()
                                  | Wx::wxHSCROLL()
                                  | Wx::wxTE_PROCESS_ENTER()
                                 ));
  Wx::Event::EVT_TEXT_URL ($self, $self, 'OnUrl');
  Wx::Event::EVT_TEXT_ENTER ($self, $self, 'OnEnter');
  Wx::Event::EVT_KEY_DOWN ($self, 'OnKey');

  # Must hold stylesheet in $self->{'stylesheet'} or it's destroyed prematurely
  my $stylesheet
    = $self->{'stylesheet'}
      = Wx::RichTextStyleSheet->new;
  $self->SetStyleSheet ($stylesheet);
  {
    my $basic_attrs = $self->GetBasicStyle;
    my $basic_font = $basic_attrs->GetFont;
    my $font = Wx::Font->new ($basic_font->GetPointSize,
                              Wx::wxFONTFAMILY_TELETYPE(),
                              $basic_font->GetStyle,
                              $basic_font->GetWeight,
                              $basic_font->GetUnderlined);
    ### code facename: $font->GetFaceName

    my $attrs = Wx::RichTextAttr->new;
    $attrs->SetFontFaceName ($font->GetFaceName);
    # $attrs->SetTextColour(Wx::wxRED());

    my $style = Wx::RichTextCharacterStyleDefinition->new ('code');
    $style->SetStyle($attrs);
    $style->SetDescription(Wx::GetTranslation('C<> code markup and verbatim paragraphs.'));
    $stylesheet->AddCharacterStyle ($style);
  }
  {
    my $attrs = Wx::RichTextAttr->new;
    $attrs->SetFontStyle (Wx::wxITALIC());

    my $style = Wx::RichTextCharacterStyleDefinition->new ('file');
    $style->SetStyle($attrs);
    $style->SetDescription(Wx::GetTranslation('F<> filename markup.'));
    $stylesheet->AddCharacterStyle ($style);
  }
  {
    my $attrs = Wx::RichTextAttr->new;
    $attrs->SetFontUnderlined (1);

    my $style = Wx::RichTextCharacterStyleDefinition->new ('link');
    $style->SetDescription(Wx::GetTranslation('L<> link markup.'));
    $style->SetStyle($attrs);
    $stylesheet->AddCharacterStyle ($style);
  }
  ### $stylesheet

  $self->{'history'} = [];
  $self->{'forward'} = [];
  $self->{'location'} = undef;

  _set_size_chars($self, 80, 30);
  return $self;
}

sub DESTROY {
  my ($self) = @_;
  ### PodRichText DESTROY() ...
  # if a timer object refers to us after destroyed it causes a segv, it seems
  _stop_timer($self);
}


#------------------------------------------------------------------------------
# sections

sub get_section_position {
  my ($self, $section) = @_;
  ### get_section_position(): $section
  ### current positions: $self->{'section_positions'}->{$section}

  my $pos = $self->{'section_positions'}->{$section};
  if (! defined $pos) {
    $pos = $self->{'section_positions'}->{lc($section)};
  }
  ### $pos
  return $pos;
}

sub get_heading_list {
  my ($self) = @_;
  return @{$self->{'heading_list'} ||= []};
}

# not documented yet ...
sub get_heading_num_position {
  my ($self, $heading_num) = @_;
  if ($heading_num < 0) { return undef; }
  return ($self->{'heading_pos_list'} ||= [])->[$heading_num];
}

#------------------------------------------------------------------------------

sub goto_pod {
  my ($self, %options) = @_;
  ### goto_pod(): keys %options

  my %location;
  my $new_parse;
  $self->current_location_line; # before section move etc

  if (defined (my $guess = $options{'guess'})) {
    if ($guess eq '-') {
      $options{'filehandle'} = \*STDIN;
    } elsif ($guess =~ /::/
             || do { require Pod::Find;
                     Pod::Find::pod_where({-inc=>1}, $guess)
                     }) {
      $options{'module'} = $guess;
    } elsif (-e $guess) {
      $options{'filename'} = $guess;
    } elsif ($guess =~ /^=(head|pod)/m   # not documented ...
             || $guess =~ /^\s*$/) {
      $options{'string'} = $guess;
    } else {
      $self->show_error_text ("Cannot guess POD input type of: ".$guess);
      return;
    }
  }

  my $module = $options{'module'};
  if (defined $module && $module ne '') {
    ### $module
    require Pod::Find;
    my $filename = Pod::Find::pod_where({-inc=>1}, $module);
    ### $filename
    if ($filename) {
      $options{'filename'} = $filename;
      $location{'module'} = $module;
    } else {
      $self->show_error_text ("Module not found: $module");
      %options = ();
    }
  }

  my $filename = $options{'filename'};
  if (defined $filename && $filename ne '') {
    ### $filename
    my $fh;
    if (! open $fh, '<', $filename) {
      $self->show_error_text ("Cannot open $filename: $!");
      return;
    }
    $options{'filehandle'} = $fh;
    unless (exists $location{'module'}) {
      $location{'filename'} = $filename;
    }
  }

  if (defined $options{'string'}) {
    ### string ...
    open my $fh, '<', \$options{'string'}
      or die "Oops, cannot open filehandle on string";
    $options{'filehandle'} = $fh;
  }

  if (defined (my $fh = $options{'filehandle'})) {
    ### filehandle: $fh

    $self->abort_and_clear;

    require Wx::Perl::PodRichText::SimpleParser;
    $self->{'parser'} = Wx::Perl::PodRichText::SimpleParser->new
      (richtext => $self,
       weaken   => 1);
    $self->{'pending_parameters'}
      = { section     => delete $options{'section'},
          heading_num => delete $options{'heading_num'},
          line        => delete $options{'line'},
        };
    ### pending_parameters: $self->{'pending_parameters'}
    $self->{'fh'} = $fh;
    $self->{'busy'} ||= Wx::BusyCursor->new;
    $new_parse = 1;
  }

  if (defined (my $line = $options{'line'})) {
    ### $line
    $location{'line'} = $line;
    $self->SetInsertionPoint($self->XYToPosition($options{'column'} || 0,
                                                 $line));
    # end and back again scrolls window to have point at the top
    $self->ShowPosition($self->GetLastPosition);
    $self->ShowPosition($self->GetInsertionPoint);
  }

  {
    my $pos;
    if (defined (my $heading_num = $options{'heading_num'})) {
      ### $heading_num
      $pos = $self->get_heading_num_position($heading_num);
    }
    if (defined (my $section = $options{'section'})) {
      ### $section
      $pos = $self->get_section_position($section);
    }
    if (defined $pos) {
      $self->SetInsertionPoint($pos);
      my (undef,$y) = $self->PositionToXY($pos);
      $location{'line'} = $y;
      # end and back again scrolls window to have point at the top
      $self->ShowPosition($self->GetLastPosition);
      $self->ShowPosition($self->GetInsertionPoint);
    } else {
      ### no heading or section ...
      # Wx::Bell();
    }
  }

  unless ($options{'no_history'}) {
    if ($self->{'location'} && %{$self->{'location'}}) {
      my $history = $self->{'history'};
      push @$history, $self->{'location'};
      if (@$history > 20) {
        splice @$history, 0, -20; # keep last 20
      }
      ### push history to: $self->{'history'}
    }
    $self->{'location'} = \%location;
    $options{'history_changed'} = 1;
  }

  ### goto_pod() nearly finished ...
  ### location now: $self->{'location'}
  ### point: $self->GetInsertionPoint

  if ($new_parse) {
    require Time::HiRes;
    $self->parse_some (1);
    $options{'content_changed'} = 1;
  }

  if ($options{'content_changed'}) {
    $self->emit_changed('content');
    $self->emit_changed('heading_list');
  }
  if ($options{'history_changed'}) {
    $self->emit_changed('history');
  }
}

use constant _PARSE_TIME => .3; # seconds
use constant _SLEEP_TIME => 50; # milliseconds

# not documented ...
sub parse_some {
  my ($self, $nofreeze) = @_;
  ### parse_some() ...
  ### $nofreeze

  my $parser = $self->{'parser'}
    || return; # if error out with timer left running maybe

  my $freezer = $nofreeze || Wx::WindowUpdateLocker->new($self);

  # preserve user position during parse
  my $old_insertion_pos = $self->GetInsertionPoint;

  $self->SetInsertionPoint($self->GetLastPosition); # for WriteText
  my $fh = $self->{'fh'} || return;
  my $t = Time::HiRes::time();

  do {
    my $lines = _read_some_lines ($fh, 20*60);
    ### some lines: scalar(@$lines)
    # ### $lines
    # FIXME: notice a read error

    $parser->parse_lines (@$lines);

    if (! defined $lines->[-1]) {
      ### EOF ...
      ### heading list: $self->{'heading_list'}
      delete $self->{'parser'};
      delete $self->{'fh'};
      delete $self->{'timer'};
      $self->SetInsertionPoint($old_insertion_pos);
      _maybe_goto_pending($self);
      delete $self->{'busy'};
      $self->emit_changed('content');
      return;
    }

    # Loop while within +/-_PARSE_TIME of the initial.
    # abs() ensures loop stops if time() jumps wildly backwards.
  } until (abs(Time::HiRes::time() - $t) > _PARSE_TIME);

  $self->SetInsertionPoint($old_insertion_pos);
  _maybe_goto_pending($self);

  $self->{'timer'} ||= do {
    my $timer = Wx::Timer->new ($self);
    Wx::Event::EVT_TIMER ($self, -1, 'parse_some');
    $timer
  };
  if (! $self->{'timer'}->Start(_SLEEP_TIME, # milliseconds
                                Wx::wxTIMER_ONE_SHOT())) {
    $self->show_error_text (Wx::GetTranslation('Oops, cannot start timer'));
  }
}

# Return an arrayref of lines, with last one undef at EOF.
sub _read_some_lines {
  my ($fh, $maxchars) = @_;
  my @lines;
  my $gotchars = 0;
  for (;;) {
    my $line = readline($fh);
    push @lines, $line;  # final undef for Pod::Simple
    if (! defined $line) {
      ### end of file ...
      last;
    }
    $gotchars += length($line);
    if ($gotchars >= $maxchars) {
      last;
    }
  }
  return \@lines;
}

sub _maybe_goto_pending {
  my ($self) = @_;

  my $pending_parameters = $self->{'pending_parameters'}
    || return;

  if ($self->{'parser'}) {
    my $target_line = $pending_parameters->{'line'};

    my $pos;
    if (defined (my $heading_num = $pending_parameters->{'heading_num'})) {
      if ($heading_num <= $#{$self->{'heading_pos_list'}}) {
        $pos = $self->{'heading_pos_list'}->[$heading_num];
      }
    }
    if (defined (my $section = $pending_parameters->{'section'})) {
      $pos = $self->get_section_position($section);
    }
    if (defined $pos) {
      my $section_line = _position_to_line($self,$pos);
      $target_line = max($section_line || 0,
                         $target_line || 0);
    } else {
      ### pending section not yet reached ...
      return;
    }

    # don't move until there's enough text to ensure position will be at the
    # top of the window
    my $lines_after = _count_lines($self) - $target_line;
    if ($lines_after < 0
        || $lines_after < 0.75 * _get_height_lines($self)) {
      ### pending line not yet reached ...
      return;
    }
  }

  delete $self->{'pending_parameters'};

  if (! _top_is_visible($self)) {
    # not at top of document, don't move from where the user has scrolled
    return;
  }

  $self->goto_pod (%$pending_parameters,
                   no_history  => 1);
}

# for internal use
sub show_error_text {
  my ($self, $str) = @_;
  ### show_error_text(): $str
  $self->abort_and_clear;
  $self->WriteText ($str);
  $self->Newline;
  $self->SetInsertionPoint(0);
  $self->emit_changed('content');
  $self->emit_changed('heading_list');
}

# not documented
sub abort_and_clear {
  my ($self) = @_;
  _stop_timer($self);
  delete $self->{'parser'};
  delete $self->{'fh'};
  delete $self->{'busy'};
  $self->EndAllStyles;
  $self->SetInsertionPoint(0);
  $self->SetDefaultStyle (Wx::TextAttrEx->new);
  $self->Clear;
  delete $self->{'section_positions'};
  delete $self->{'heading_list'};
}
sub _stop_timer {
  my ($self) = @_;
  if (my $timer = delete $self->{'timer'}) {
    $timer->Stop;
    $timer->SetOwner(undef);
  }
}

#------------------------------------------------------------------------------
# history

sub reload {
  my ($self) = @_;
  $self->current_location_line;
  $self->goto_pod (%{$self->{'location'}},
                   no_history => 1);
  ### location now: $self->{'location'}
  ### history now: $self->{'history'}
}

# not documented ...
sub can_reload {
  my ($self) = @_;
  ### can_reload(): $self->{'location'}
  return (defined $self->{'location'}->{'module'}
          || defined $self->{'location'}->{'filename'});
}

# not documented ...
sub can_go_forward {
  my ($self) = @_;
  return @{$self->{'forward'}} > 0;
}

sub go_forward {
  my ($self) = @_;
  if (defined (my $forward_location = shift @{$self->{'forward'}})) {
    my $current_location = $self->{'location'};

    my %goto_pod = %$forward_location;
    if ($goto_pod{'module'}
        && $current_location->{'module'}
        && $goto_pod{'module'} eq $current_location->{'module'}) {
      delete $goto_pod{'module'};
    } elsif ($goto_pod{'filename'}
             && $current_location->{'filename'}
             && $goto_pod{'filename'} eq $current_location->{'filename'}) {
      delete $goto_pod{'filename'};
    }
    $self->goto_pod (%goto_pod,
                     history_changed => 1);
  }
}

# not documented ...
sub can_go_back {
  my ($self) = @_;
  return @{$self->{'history'}} > 0;
}

sub go_back {
  my ($self) = @_;
  if (defined (my $back_location = pop @{$self->{'history'}})) {
    my $current_location = $self->{'location'};
    $self->current_location_line;
    unshift @{$self->{'forward'}}, $current_location;
    $self->{'location'} = $back_location;

    my %goto_pod = %$back_location;
    if ($goto_pod{'module'}
        && $current_location->{'module'}
        && $goto_pod{'module'} eq $current_location->{'module'}) {
      delete $goto_pod{'module'};
    } elsif ($goto_pod{'filename'}
             && $current_location->{'filename'}
             && $goto_pod{'filename'} eq $current_location->{'filename'}) {
      delete $goto_pod{'filename'};
    }
    $self->goto_pod (%goto_pod,
                     no_history => 1,
                     history_changed => 1);
  }
}
sub current_location_line {
  my ($self) = @_;
  ### current_location_line() ...
  if ($self->{'location'} && %{$self->{'location'}}) {
    my (undef,$y) = $self->PositionToXY($self->GetFirstVisiblePosition);
    $self->{'location'}->{'line'} = $y;
    ### location updated to: $self->{'location'}
  } else {
    ### no current location to store to ...
  }
}

#------------------------------------------------------------------------------
# link following

sub OnKey {
  my ($self, $event) = @_;
  ### PodRichText OnEnter(): $event
  ### keycode: $event->GetKeyCode

  if ($event->ControlDown) {
    if ($event->GetKeyCode == ord('b') || $event->GetKeyCode == ord('B')) {
      $self->go_back;
    } elsif ($event->GetKeyCode == ord('f') || $event->GetKeyCode == ord('F')) {
      $self->go_forward;
    }
  } else {
    if ($event->GetKeyCode == ord("\r")) {
      $self->goto_link_at_pos ($self->GetInsertionPoint);
    }
  }
  $event->Skip(1); # propagate to other handlers
}
sub OnUrl {
  my ($self, $event) = @_;
  ### PodRichText OnUrl(): $event
  $self->goto_link_at_pos ($event->GetURLStart);
  $event->Skip(1); # propagate to other handlers
}

# not documented yet
sub goto_link_at_pos {
  my ($self, $pos) = @_;
  ### goto_link_at_pos(): $pos

  my $attrs = $self->GetRichTextAttrStyle($pos);
  if (defined (my $url = $attrs->GetURL)) {
    ### $url
    if ($url =~ m{^pod://([^#]+)?(#(.*))?}) {
      my $module = $1;
      my $section = $3;
      ### $module
      ### $section
      $self->goto_pod (module  => $module,
                       section => $section);
    } else {
      Wx::LaunchDefaultBrowser($url);
    }
  }
}

#------------------------------------------------------------------------------
# printing

# return a suitably setup Wx::RichTextPrinting object
# not documented yet
sub rich_text_printing {
  my ($self) = @_;
  $self->{'printing'} ||= do {
    my $printing = Wx::RichTextPrinting->new ('', $self);
    $printing->SetHeaderText('@TITLE@');

    my $footer = Wx::GetTranslation('Page @PAGENUM@ of @PAGESCNT@');
    $printing->SetFooterText($footer,
                             Wx::wxRICHTEXT_PAGE_ODD(),
                             Wx::wxRICHTEXT_PAGE_RIGHT());
    $printing->SetFooterText($footer,
                             Wx::wxRICHTEXT_PAGE_EVEN(),
                             Wx::wxRICHTEXT_PAGE_LEFT());
    $printing;
  };

  my $printing = $self->{'printing'};
  my $title = '';
  my $location = $self->{'location'};
  if (defined $location->{'module'}) {
    $title = $location->{'module'};
  } elsif (defined $location->{'filename'}) {
    $title = $location->{'filename'};
  }
  $printing->SetTitle($title);

  return $printing;
}

#------------------------------------------------------------------------------
# Generic

# Maybe ...
#
# =item C<$height = Wx::Perl::RichTextBits::set_size_chars($richtextctrl, $width,$height)>
#
# Return the size of a C<wxRichTextCtrl> as width and height in characters
# of the default font.

sub _set_size_chars {
  my ($self, $width, $height) = @_;
  ### _set_size_chars(): "$width,$height"

  my $attrs = $self->GetBasicStyle;
  my $font = $attrs->GetFont;
  my $font_points = $font->GetPointSize;
  my $font_mm = $font_points * (1/72 * 25.4);

  ### $font_mm
  ### xpixels: _x_mm_to_pixels ($self, $width * $font_mm * .8)
  ### ypixels: _y_mm_to_pixels ($self, $height * $font_mm)

  $self->SetSize (_x_mm_to_pixels ($self, $width * $font_mm * .8),
                  _y_mm_to_pixels ($self, $height * $font_mm));
}

# Maybe ...
#
# =item C<$height = Wx::Perl::RichTextBits::get_height_lines($richtextctrl)>
#
# Return the height in lines of a C<wxRichTextCtrl>, as reckoned by the
# default font height.  This might include a fraction of a line, depending
# the window height and font height.

sub _get_height_lines {
  my ($self) = @_;
  my $attrs = $self->GetBasicStyle;
  my $font = $attrs->GetFont;
  my $font_points = $font->GetPointSize;
  my $font_mm = $font_points * (1/72 * 25.4);
  my (undef,$height) = $self->GetSizeWH;
  ### lines: _y_pixels_to_mm($self,$height) / $font_mm
  return _y_pixels_to_mm($self,$height) / $font_mm;

  # ### $height
  # {  my ($outside, $x,$y) = $self->HitTest(Wx::Point->new(0,0));
  #    ### top: ($outside, $x,$y)
  #  }
  # {
  #   my ($outside, $x,$y) = $self->HitTest(Wx::Point->new(0,$height));
  #   ### bot: ($outside, $x,$y)
  # }
  # return 30;
}

# cf Wx::Display->GetFromWindow($window), but wxDisplay doesn't have
# millimetre sizes?
sub _x_mm_to_pixels {
  my ($window, $mm) = @_;
  my $size_pixels = Wx::GetDisplaySize();
  my $size_mm = Wx::GetDisplaySizeMM();
  return $mm * $size_pixels->GetWidth / $size_mm->GetWidth;
}
sub _y_mm_to_pixels {
  my ($window, $mm) = @_;
  my $size_pixels = Wx::GetDisplaySize();
  my $size_mm = Wx::GetDisplaySizeMM();
  return $mm * $size_pixels->GetHeight / $size_mm->GetHeight;
}
sub _y_pixels_to_mm {
  my ($window, $pixels) = @_;
  my $size_pixels = Wx::GetDisplaySize();
  my $size_mm = Wx::GetDisplaySizeMM();
  return $pixels * $size_mm->GetHeight / $size_pixels->GetHeight;
}
# sub _pixel_size_mm {
#   my ($window) = @_;
#   my $size_pixels = Wx::GetDisplaySize();
#   my $size_mm = Wx::GetDisplaySizeMM();
#   return ($size_mm->GetWidth / $size_pixels->GetWidth,
#           $size_mm->GetHeight / $size_pixels->GetHeight);
# }

# =item C<$bool = Wx::Perl::RichTextBits::top_is_visible($richtext)>
#
# Return true if the first line of C<$richtext> is visible in its window.
#
# =item C<$count = Wx::Perl::RichTextBits::count_lines($richtext)>
#
# =item C<$linenum = Wx::Perl::TextCtrlBits::position_to_line($richtext,$pos)>
#
# Return the line number containing character position C<$pos>, or C<undef>
# if C<$pos> is past the end of the buffer.  This is simply the Y value from
# C<$richtext-E<gt>PositionToXY($pos)>.
#
sub _top_is_visible {
  my ($richtext) = @_;
  return _position_to_line($richtext, $richtext->GetFirstVisiblePosition) == 0;
}
sub _count_lines {
  my ($richtext) = @_;
  return _position_to_line($richtext, $richtext->GetLastPosition);
}
sub _position_to_line {
  my ($richtext, $pos) = @_;
  (undef, my $y) = $richtext->PositionToXY($pos);
  return $y;
}

1;
__END__

=for stopwords Wx Wx-Perl-PodBrowser Ryde RichTextCtrl RichText ascii buttonized latin-1 0xA0 PodRichText filename formatters ie unlinked Gtk linkize PodBrowser

=head1 NAME

Wx::Perl::PodRichText -- POD in a RichTextCtrl

=head1 SYNOPSIS

 use Wx::Perl::PodRichText;
 my $podtextwidget = Wx::Perl::PodRichText->new;
 $podtextwidget->goto_pod (module => 'Foo::Bar');

=head1 CLASS HIERARCHY

C<Wx::Perl::PodBrowser> is a subclass of C<Wx::RichTextCtrl>.

    Wx::Object
      Wx::EvtHandler
        Wx::Validator
          Wx::Control
            Wx::TextCtrlBase
              Wx::RichTextCtrl
                 Wx::Perl::PodRichText

=head1 DESCRIPTION

This is a C<Wx::RichTextCtrl> displaying formatted POD documents from
F<.pod> or F<.pm> files or parsed from a string or file handle.

See L<Wx::Perl::PodBrowser> for a whole toplevel browser window.

=head2 Details

The initial widget C<SetSize()> is a sensible size for POD, currently about
80 columns by 30 lines of the default font.  A parent widget can make it
bigger or smaller as desired.

The POD to text conversion tries to use RichText features.

=over

=item *

Indentation is done with the left indent feature so text paragraphs flow
nicely within C<=over> etc.

=item *

C<=item> bullet points use the RichText bullet paragraphs, and numbered
C<=item> use numbered paragraphs likewise.

In Wx circa 2.8.12 numbered paragraphs with big numbers seem to display with
the text overlapping the number, but that should be a Wx matter and for
small numbers it's fine.

=item *

Verbatim paragraphs are done in C<wxFONTFAMILY_TELETYPE> and
C<wxRichTextLineBreakChar> for each newline.  Wraparound is avoided by a
large negative right indent.

Alas there's no scroll bar or visual indication of more text off to the
right, but avoiding wraparound helps tables and ascii art.

=item *

C<< LE<lt>E<gt> >> links to URLs are underlined and buttonized with the
"URL" style.  C<< LE<lt>E<gt> >> links to POD similarly but using a
C<pod://> pseudo-URL.  Is a C<pod:> URL a good idea?  It won't be usable by
anything else, but the attribute is a handy place to hold the link
destination.

The current code has an C<EVT_TEXT_URL()> handler following to target POD or
C<Wx::LaunchDefaultBrowser()> for URLs.  But that might change, as it might
be better to leave that to the browser parent if some applications wanted to
display only a single POD.

=item *

C<< SE<lt>E<gt> >> non-breaking text is done with latin-1 0xA0 non-breaking
spaces.  RichText obeys them when word wrapping.

=back

The display is reckoned as text so POD C<=begin text> sections are included
in the display.  Other C<=begin> types are ignored.

Reading a large POD file is slow.  The work is done piece-wise from the
event loop to keep the rest of the application running, but expect
noticeable lag.

=head1 FUNCTIONS

=over

=item C<< $podtextwidget = Wx::Perl::PodRichText->new($parent) >>

=item C<< $podtextwidget = Wx::Perl::PodRichText->new($parent,$id) >>

Create and return a new PodRichText widget in C<$parent>.  If C<$id> is not
given then C<wxID_ANY> is used to have wxWidgets choose an ID number.

=item C<< $podtextwidget->goto_pod (key => value, ...) >>

Go to a specified POD module, filename, section etc.  The key/value options
are

    module     => $str      module etc in @INC
    filename   => $str      file name
    filehandle => $fh
    string     => $str
    guess      => $str

    section  => $string
    line     => $integer     line number

The target POD document is given by C<module> or C<filename>, etc.
C<module> is sought with L<Pod::Find> in the usual C<@INC> path.  C<string>
is POD in a string.

    $podtextwidget->goto_pod (module => "perlpodspec");

C<guess> tries a module or filename.  It's intended for command line or
similar loose input to let the user enter either module or filename.

Optional C<section> or C<line> is a position within the document.  They can
be given alone to move in the currently displayed document.

    # move within current display
    $podtextwidget->goto_pod (section => "DESCRIPTION");

C<section> can be an C<=head> heading or an C<=item> text.  The first word
from an C<=item> works too, which is common for the POD formatters and helps
cross-references to L<perlfunc> and similar.

=item C<< $podtextwidget->reload () >>

Re-read the current C<module> or C<filename> source.

=item C<< $bool = $podtextwidget->can_reload () >>

Return true if the current POD is from a C<module> or C<filename> source and
therefore suitable for a C<reload()>.

=back

=head2 Content Methods

POD is parsed progressively under a timer and the following methods give the
part parsed so far.

=over

=item C<< @strings = $podtextwidget->get_heading_list () >>

Return a list of the C<=head> headings in the displayed document.

=item C<< $charpos = $podtextwidget->get_section_position ($section) >>

Return the character position of C<$section>.  The position is per
C<SetInsertionPoint()> etc so 0 is the start of the document.  C<$section>
is a heading or item as described above for C<section> of C<goto_pod()>.  If
there is no such C<$section> then return C<undef>.

=back

=head1 BUGS

C<Wx::wxTE_AUTO_URL> is turned on attempting to pick up unlinked URLs, but
it doesn't seem to have any effect circa Wx 2.8.12 under Gtk.  Is that
option only for the plain C<Wx::TextCtrl>?  Perhaps could search and linkize
apparent URLs manually, though perhaps links are best left to
C<< LE<lt>E<gt> >> markup in the source POD anyway.

As of wxWidgets circa 2.8.12 calling C<new()> without a C<$parent> gets a
segfault.  This is the same as C<< Wx::RichTextCtrl->new() >> called without
a parent.  Is it good enough to let C<< Wx::RichTextCtrl->new() >> do any
necessary C<undef> etc argument checking?

=head1 SEE ALSO

L<Wx>,
L<Wx::Perl::PodBrowser>,
L<Pod::Find>

=head1 HOME PAGE

L<http://user42.tuxfamily.org/wx-perl-podbrowser/index.html>

=head1 LICENSE

Copyright 2012, 2013 Kevin Ryde

Wx-Perl-PodBrowser is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by the
Free Software Foundation; either version 3, or (at your option) any later
version.

Wx-Perl-PodBrowser is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along with
Wx-Perl-PodBrowser.  If not, see L<http://www.gnu.org/licenses/>.

=cut
