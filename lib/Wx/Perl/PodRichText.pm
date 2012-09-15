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


package Wx::Perl::PodRichText;
use 5.008;
use strict;
use warnings;
use Carp;
use Wx;
use Wx::RichText;

use base 'Wx::RichTextCtrl';
our $VERSION = 3;

use base 'Exporter';
our @EXPORT_OK = ('EVT_PERL_PODRICHTEXT_CHANGED');

# uncomment this to run the ### lines
#use Smart::Comments;


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
  our $VERSION = 3;
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
                                 Wx::gettext('Nothing selected'),
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
    $attrs->SetFlags (Wx::wxTEXT_ATTR_FONT_FACE());
    # $attrs->SetTextColour(Wx::wxRED());

    my $style = Wx::RichTextCharacterStyleDefinition->new ('code');
    $style->SetStyle($attrs);
    $style->SetDescription(Wx::gettext('C<> code markup and verbatim paragraphs.'));
    $stylesheet->AddCharacterStyle ($style);
  }
  {
    my $attrs = Wx::RichTextAttr->new;
    $attrs->SetFontStyle (Wx::wxTEXT_ATTR_FONT_ITALIC());
    $attrs->SetFlags (Wx::wxTEXT_ATTR_FONT_ITALIC());

    my $style = Wx::RichTextCharacterStyleDefinition->new ('file');
    $style->SetStyle($attrs);
    $style->SetDescription(Wx::gettext('F<> filename markup.'));
    $stylesheet->AddCharacterStyle ($style);
  }
  {
    my $attrs = Wx::RichTextAttr->new;
    $attrs->SetFontUnderlined (1);
    $attrs->SetFlags (Wx::wxTEXT_ATTR_FONT_UNDERLINE());

    my $style = Wx::RichTextCharacterStyleDefinition->new ('link');
    $style->SetDescription(Wx::gettext('L<> link markup.'));
    $style->SetStyle($attrs);
    $stylesheet->AddCharacterStyle ($style);
  }
  ### $stylesheet

  $self->{'history'} = [];
  $self->{'forward'} = [];
  $self->{'location'} = undef;

  $self->set_size_chars(80, 30);
  return $self;
}

sub DESTROY {
  my ($self) = @_;
  ### PodRichText DESTROY() ...
  # if a timer object refers to us after destroyed it causes a segv, it seems
  _stop_timer($self);
}


#------------------------------------------------------------------------------

# not documented yet
sub set_size_chars {
  my ($self, $width, $height) = @_;
  my $attrs = $self->GetBasicStyle;
  my $font = $attrs->GetFont;
  my $font_points = $font->GetPointSize;
  my $font_mm = $font_points * (1/72 * 25.4);

  ### $font_mm
  ### xpixels: x_mm_to_pixels ($self, $width * $font_mm * .8)
  ### ypixels: y_mm_to_pixels ($self, $height * $font_mm)

  $self->SetSize (x_mm_to_pixels ($self, $width * $font_mm * .8),
                  y_mm_to_pixels ($self, $height * $font_mm));
}

# cf Wx::Display->GetFromWindow($window), but wxDisplay doesn't have
# millimetre sizes?
sub x_mm_to_pixels {
  my ($window, $mm) = @_;
  my $size_pixels = Wx::GetDisplaySize();
  my $size_mm = Wx::GetDisplaySizeMM();
  return $mm * $size_pixels->GetWidth / $size_mm->GetWidth;
}
sub y_mm_to_pixels {
  my ($window, $mm) = @_;
  my $size_pixels = Wx::GetDisplaySize();
  my $size_mm = Wx::GetDisplaySizeMM();
  return $mm * $size_pixels->GetHeight / $size_mm->GetHeight;
}
sub y_pixels_to_mm {
  my ($window, $pixels) = @_;
  my $size_pixels = Wx::GetDisplaySize();
  my $size_mm = Wx::GetDisplaySizeMM();
  return $pixels * $size_mm->GetHeight / $size_pixels->GetHeight;
}
# sub pixel_size_mm {
#   my ($window) = @_;
#   my $size_pixels = Wx::GetDisplaySize();
#   my $size_mm = Wx::GetDisplaySizeMM();
#   return ($size_mm->GetWidth / $size_pixels->GetWidth,
#           $size_mm->GetHeight / $size_pixels->GetHeight);
# }

# not documented
sub get_height_lines {
  my ($self) = @_;
  my $attrs = $self->GetBasicStyle;
  my $font = $attrs->GetFont;
  my $font_points = $font->GetPointSize;
  my $font_mm = $font_points * (1/72 * 25.4);
  my (undef,$height) = $self->GetSizeWH;
  ### lines: y_pixels_to_mm($self,$height) / $font_mm
  return y_pixels_to_mm($self,$height) / $font_mm;

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

#------------------------------------------------------------------------------
# sections

# not documented yet
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

#------------------------------------------------------------------------------

sub goto_pod {
  my ($self, %options) = @_;
  ### goto_pod(): keys %options

  my %location;
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
      $self->show_error_text ("Cannot guess POD input type");
      return;
    }
  }

  my $module = $options{'module'};
  if (defined $module && $module ne '') {
    ### $module
    require Pod::Find;
    my $filename = Pod::Find::pod_where({-inc=>1}, $module);
    ### $filename
    if (! $filename) {
      $self->show_error_text ("Module not found: $module");
      return;
    }
    $options{'filename'} = $filename;
    $location{'module'} = $module;
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
    # Note: must keep string in its own scalar since IO::String takes a
    # reference not a copy.
    require IO::String;
    $options{'filehandle'} = IO::String->new ($options{'string'});
  }

  if (defined (my $fh = $options{'filehandle'})) {
    ### filehandle: $fh

    $self->abort_and_clear;

    require Wx::Perl::PodRichText::SimpleParser;
    $self->{'parser'} = Wx::Perl::PodRichText::SimpleParser->new
      (richtext => $self,
       weaken => 1);
    $self->{'section'} = delete $options{'section'};
    $self->{'line'}    = delete $options{'line'};
    $self->{'fh'} = $fh;
    $self->{'busy'} ||= Wx::BusyCursor->new;
    require Time::HiRes;
    $self->parse_some (1);

    $options{'content_changed'} = 1;
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

  if (defined (my $section = $options{'section'})) {
    ### $section
    if (defined (my $pos = $self->get_section_position($section))) {
      $self->SetInsertionPoint($pos);
      my (undef,$y) = $self->PositionToXY($pos);
      $location{'line'} = $y;
      # end and back again scrolls window to have point at the top
      $self->ShowPosition($self->GetLastPosition);
      $self->ShowPosition($self->GetInsertionPoint);
    } else {
      ### unknown section ...
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
    }
    $self->{'location'} = \%location;
    $options{'history_changed'} = 1;
  }

  ### goto_pod done ...
  ### location now: $self->{'location'}
  ### history now: $self->{'history'}
  ### point: $self->GetInsertionPoint

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

# for internal use
sub parse_some {
  my ($self, $nofreeze) = @_;
  ### parse_some() ...

  my $parser = $self->{'parser'}
    || return; # if error out with timer left running maybe

  my $freezer = $nofreeze || Wx::WindowUpdateLocker->new($self);
  $self->SetInsertionPoint($self->GetLastPosition); # for WriteText
  my $fh = $self->{'fh'} || return;
  my $t = Time::HiRes::time();

  for (;;) {
    my @lines;
    do {
      my $line = <$fh>;
      push @lines, $line;
      if (! defined $line) {
        # eof
        # FIXME: notice a read error
        delete $self->{'fh'};
        $parser->parse_lines (@lines);
        delete $self->{'parser'};

        my $section = delete $self->{'section'};
        ### $section
        my (undef,$y) = $self->PositionToXY($self->GetFirstVisiblePosition);
        if ($y == 0) {
          # still at top of document, move to target section
          $self->goto_pod (section => $section,
                           line    => delete $self->{'line'},
                           no_history => 1);
        }

        delete $self->{'timer'};
        delete $self->{'busy'};
        $self->emit_changed('content');
        return;
      }
    } until (@lines >= 20);

    $parser->parse_lines (@lines);
    if (abs (Time::HiRes::time() - $t) > _PARSE_TIME) {
      last;
    }
  }

  if (defined $self->{'section'}
      && defined (my $pos = $self->{'section_positions'}->{$self->{'section'}})) {
    (undef,my $y) = $self->PositionToXY($self->GetFirstVisiblePosition);
    if ($y == 0) {
      # still at top of document, move to target section, but only when
      # enough text to ensure position will be at the top of the window
      (undef,$y) = $self->PositionToXY($pos);
      (undef,my $last_y) = $self->PositionToXY($self->GetLastPosition);
      if ($last_y - $y > $self->get_height_lines * .75) {
        $self->goto_pod (section => delete $self->{'section'},
                         no_history => 1);
      }
    }
  }

  $self->{'timer'} ||= do {
    my $timer = Wx::Timer->new ($self);
    require Scalar::Util;
    Wx::Event::EVT_TIMER ($self, -1, 'parse_some');
    $timer
  };
  if (! $self->{'timer'}->Start(_SLEEP_TIME, Wx::wxTIMER_ONE_SHOT())) {
    $self->show_error_text (Wx::gettext('Oops, cannot start timer'));
  }
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

sub can_reload {
  my ($self) = @_;
  ### can_reload(): $self->{'location'}
  return (defined $self->{'location'}->{'module'}
          || defined $self->{'location'}->{'filename'});
}
sub reload {
  my ($self) = @_;
  $self->current_location_line;
  $self->goto_pod (%{$self->{'location'}},
                   no_history => 1);
  ### location now: $self->{'location'}
  ### history now: $self->{'history'}
}

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
  ### location now: $self->{'location'}
  if ($self->{'location'} && %{$self->{'location'}}) {
    my (undef,$y) = $self->PositionToXY($self->GetFirstVisiblePosition);
    $self->{'location'}->{'line'} = $y;
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
  ### get_url_at_pos(): $pos
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


1;
__END__

=for stopwords Wx Wx-Perl-PodBrowser Ryde RichTextCtrl RichText ascii buttonized latin-1 0xA0 PodRichText filename formatters ie unlinked Gtk linkize PodBrowser

=head1 NAME

Wx::Perl::PodRichText -- POD in a RichTextCtrl

=head1 SYNOPSIS

 use Wx::Perl::PodRichText;
 my $podtext = Wx::Perl::PodRichText->new;
 $podtext->goto_pod (module => 'Foo::Bar');

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

This is a C<Wx::RichTextCtrl> displaying formatted POD documents, either
from F<.pod> or F<.pm> files or parsed from a string or file handle.

See L<Wx::Perl::PodBrowser> for a whole browser window.

=head2 Details

The initial widget C<SetSize()> is a sensible size for POD, currently about
80 columns by 30 lines of the default font.  A parent widget can make it
bigger or smaller as desired.

The POD to text conversion tries to use the RichText features.

=over

=item *

Indentation is done with the left indent feature so text paragraphs flow
nicely within C<=over> etc.

=item *

C<=item> bullet points use the RichText bullets paragraphs, and numbered
C<=item> the numbered paragraphs likewise.  Circa Wx 2.8.12 big numbers seem
to display with the text overlapping, but it's presumed that's a Wx matter,
and for small numbers it's fine anyway.

=item *

Verbatim paragraphs are done in C<wxFONTFAMILY_TELETYPE> and with
C<wxRichTextLineBreakChar> for each newline.  Wraparound is avoided by a
large negative right indent.  Alas there's no scroll bar or visual
indication of more text off to the right, but avoiding wraparound helps
tables and ascii art.

=item *

C<< LE<lt>E<gt> >> links to URLs are underlined and buttonized with the
"URL" style.  C<< LE<lt>E<gt> >> links to POD similarly, but using a
C<pod://> pseudo-URL.  Is a C<pod:> URL a good idea?  It won't be usable by
anything else, but the attribute is a handy place to hold the link target.

The current code has an C<EVT_TEXT_URL()> handler following to target POD,
or C<Wx::LaunchDefaultBrowser()> for URLs.  But that might change, as it
might be better to leave that to the browser parent, if some applications
wanted to display only a single POD.

=item *

C<< SE<lt>E<gt> >> non-breaking text is done with latin-1 0xA0 non-breaking
spaces which RichText obeys when word wrapping.

=back

The display is reckoned as text so C<=begin text> sections from the POD are
included in the display.  Other C<=begin> types are ignored.

Reading a large POD file is slow.  The work is done piece-wise from the
event loop to keep the rest of the application running, but expect
noticeable lag.

=head1 FUNCTIONS

=over

=item C<< $podtext = Wx::Perl::PodRichText->new() >>

=item C<< $podtext = Wx::Perl::PodRichText->new($id,$parent) >>

Create and return a new PodRichText widget.

=item C<< $podtext->goto_pod (key => value, ...) >>

Go to a specified POD module, filename, section etc.  The key/value options
are

    module     => $str      module etc in @INC
    filename   => $str      file name
    filehandle => $fh
    string     => $str
    guess      => $str

    section  => $string
    line     => $integer     line number

The target POD document is given by C<module>, C<filename>, etc.  C<module>
is sought with L<Pod::Find> in the usual C<@INC>.  C<string> is POD in a
string.

    $podtext->goto_pod (module => "perlpodspec");

C<guess> tries a module or filename.  It's intended for command line or
similar loose input to let the user enter either module or filename.

Optional C<section> or C<line> is a position within the document.  They can
be given alone to move in the currently displayed document.

    # move within current display
    $podtext->goto_pod (section => "DESCRIPTION");

C<section> can be an C<=head> heading or an C<=item> text.  The first word
from an C<=item> works too, which is common for the POD formatters and helps
cross-references to L<perlfunc> and similar.

=item C<< @strings = $podtext->reload () >>

Re-read the current C<module> or C<filename> source.

=item C<< @strings = $podtext->get_heading_list () >>

Return a list of the C<=head> headings in the displayed document.

The heading list grows as the parse progresses, ie. when the parse yields
control back to the main loop.

=back

=head1 BUGS

C<Wx::wxTE_AUTO_URL> is turned on attempting to pick up unlinked URLs, but
it doesn't seem to have any effect circa Wx 2.8.12 under Gtk.  Is that
option only for the plain C<Wx::TextCtrl>?  Could search and linkize
apparent URLs manually, though perhaps it's best left to C<< LE<lt>E<gt> >>
markup in the source POD anyway.

=head1 SEE ALSO

L<Wx>,
L<Wx::Perl::PodBrowser>,
L<Pod::Find>

=head1 HOME PAGE

L<http://user42.tuxfamily.org/math-image/index.html>

=head1 LICENSE

Copyright 2012 Kevin Ryde

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
