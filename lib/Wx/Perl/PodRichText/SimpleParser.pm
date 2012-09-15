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


package Wx::Perl::PodRichText::SimpleParser;
use 5.008;
use strict;
use warnings;
use base 'Pod::Simple';
our $VERSION = 3;

# uncomment this to run the ### lines
#use Smart::Comments;

sub new {
  my ($class, %options) = @_;
  ### PodRichText-SimpleParser new() ...

  my $self = $class->SUPER::new (%options);
  $self->{'richtext'} = $options{'richtext'};
  if ($options{'weaken'}) {
    require Scalar::Util;
    Scalar::Util::weaken ($self->{'richtext'});
  }

  $self->nbsp_for_S(1);   # latin-1 0xA0 for RichText
  $self->preserve_whitespace (1);  # eg. two-spaces for full stop
  $self->accept_targets ('text','TEXT');
  return $self;
}

# sub DESTROY {
#   my ($self) = @_;
#   ### PodRichText-SimpleParser DESTROY() ...
#   $self->SUPER::DESTROY();
#   ### DESTROY done ...
# }

# wxRichTextLineBreakChar() and ->LineBreak() not wrapped in 0.9909
#   eval{Wx::wxRichTextLineBreakChar()}
#
my $linebreak = chr(29); # per src/richtext/richtextbuffer.cpp

sub _handle_text {
  my ($self, $text) = @_;
  ### _handle_text: $text
  my $richtext = $self->{'richtext'};

  if ($self->{'in_X'}) {
    $self->{'X'} .= $text;
    return;
  }

  if ($self->{'verbatim'}) {
    $text =~ s/[ \t\r]*\n/$linebreak/g; # newlines become forced linebreaks
  } else {
    if ($self->{'start_Para'}) {
      $text =~ s/^\s+//;
      return if $text eq '';
      $self->{'start_Para'} = 0;
    }
    $text =~ s/\s*\r?\n\s*/ /g;  # flow newlines
  }
  ### $text
  $richtext->WriteText($text);
}

sub _handle_element_start {
  my ($self, $element, $attrs) = @_;
  ### _handle_element_start(): $element
  my $richtext = $self->{'richtext'};

  if ($element eq 'Document') {
    $self->{'indent'} = 0;

    my $attrs = $richtext->GetBasicStyle;
    my $font = $attrs->GetFont;
    my $font_mm = $font->GetPointSize * (1/72 * 25.4);
    # 1.5 characters expressed in tenths of mm
    $self->{'indent_step'} = int($font_mm*10 * 1.5);
    ### $font_mm
    ### indent_step: $self->{'indent_step'}

    $richtext->BeginSuppressUndo;
    # .6 of a line, expressed in tenths of a mm
    $richtext->BeginParagraphSpacing ($font_mm*10 * .2,  # before
                                      $font_mm*10 * .4); # after
    $richtext->{'section_positions'} = {};
    $richtext->{'heading_list'} = [];
    $richtext->{'index_list'} = [];

  } elsif ($element eq 'Para'
           || $element eq 'Data') {  # =end text
    $self->{'start_Para'} = 1;
    $richtext->BeginLeftIndent($self->{'indent'} + $self->{'indent_step'});

  } elsif ($element eq 'Verbatim') {
    ### start verbatim ...
    $self->{'verbatim'} = 1;
    $richtext->BeginLeftIndent($self->{'indent'} + $self->{'indent_step'});
    $richtext->BeginRightIndent(-10000);
    $richtext->BeginCharacterStyle('code');

  } elsif ($element =~ /^over/) {
    $self->{'indent'} += $self->{'indent_step'};

  } elsif ($element =~ /^item/) {
    $self->{'startpos'} = $richtext->GetInsertionPoint;
    if ($element eq 'item-bullet') {
      $richtext->BeginStandardBullet("standard/circle",
                                     $self->{'indent'},
                                     $self->{'indent_step'});
    } elsif ($element eq 'item-number') {
      # $richtext->BeginLeftIndent($self->{'indent'});
      # $self->_handle_text($number.'.');

      $richtext->BeginNumberedBullet($attrs->{'number'},
                                     $self->{'indent'},
                                     $self->{'indent_step'});
    } else {
      $richtext->BeginLeftIndent($self->{'indent'});
    }

  } elsif ($element =~ /^head(\d*)/) {
    my $level = $1;
    # half-step indent for =head2 and higher
    $richtext->BeginLeftIndent($self->{'indent'}
                               + ($level > 1 ? $self->{'indent_step'} / 2 : 0));
    $richtext->BeginBold;
    $self->{'startpos'} = $richtext->GetInsertionPoint;

  } elsif ($element eq 'B') {
    $richtext->BeginBold;
  } elsif ($element eq 'C') {
    $richtext->BeginCharacterStyle('code');
  } elsif ($element eq 'I') {
    $richtext->BeginItalic;
  } elsif ($element eq 'F') {
    $richtext->BeginCharacterStyle('file');

  } elsif ($element eq 'L') {
    ### link type: $attrs->{'type'}
    if ($attrs->{'type'} eq 'pod') {
      # ENHANCE-ME: escape "/" etc in "to", and maybe in "section"
      my $url = 'pod://';
      if (defined $attrs->{'to'})      { $url .= $attrs->{'to'}; }
      if (defined $attrs->{'section'}) { $url .= "#$attrs->{'section'}"; }
      $richtext->BeginURL ($url);
      $self->{'in_URL'}++;
    } elsif ($attrs->{'type'} eq 'url') {
      $richtext->BeginURL ($attrs->{'to'});
      $self->{'in_URL'}++;
    }
    $richtext->BeginCharacterStyle('link');

  } elsif ($element eq 'X') {
    $self->{'in_X'} = 1;
  }
}
sub _handle_element_end {
  my ($self, $element, $attrs) = @_;
  ### _handle_element_end(): $element

  my $richtext = $self->{'richtext'};

  if ($element eq 'Document') {
    $richtext->EndSuppressUndo;
    $richtext->EndParagraphSpacing;
    $richtext->SetInsertionPoint(0);

  } elsif ($element eq 'Para'
           || $element eq 'Data') {   # =begin text
    $self->{'start_Para'} = 0;
    $richtext->Newline;
    $richtext->EndLeftIndent;

  } elsif ($element eq 'Verbatim') {
    $self->{'verbatim'} = 0;
    $richtext->EndCharacterStyle;
    $richtext->Newline;
    $richtext->EndRightIndent;
    $richtext->EndLeftIndent;

  } elsif ($element =~ /^head(\d*)/) {
    $self->set_heading_range ($self->{'startpos'},
                              $richtext->GetInsertionPoint);
    $richtext->EndBold;
    $richtext->Newline;
    $richtext->EndLeftIndent;

  } elsif ($element =~ /^over/) { # =back
    $self->{'indent'} -= $self->{'indent_step'};

  } elsif ($element =~ /^item/) {
    $self->set_item_range ($self->{'startpos'}, $richtext->GetInsertionPoint);
    $richtext->Newline;
    if ($element eq 'item-bullet') {
      $richtext->EndStandardBullet;
    } elsif ($element eq 'item-number') {
      $richtext->EndNumberedBullet;
    } else {
      $richtext->EndLeftIndent;
    }

  } elsif ($element eq 'B') {
    $richtext->EndBold;
  } elsif ($element eq 'C') {
    $richtext->EndCharacterStyle;
  } elsif ($element eq 'I') {
    $richtext->EndItalic;
  } elsif ($element eq 'F') {
    $richtext->EndCharacterStyle;

  } elsif ($element eq 'L') {
    $richtext->EndCharacterStyle;
    if ($self->{'in_URL'}) {  # if in a URL'ed link
      $self->{'in_URL'}--;
      $richtext->EndURL;
    }

  } elsif ($element eq 'X') {
    delete $self->{'in_X'};
    push @{$richtext->{'index_list'}},
      delete $self->{'X'}, $self->{'startpos'};
  }
}

# set the position of $section to $pos
# if $pos is not given then default to the current insertion point
sub set_heading_range {
  my ($self, $startpos, $endpos) = @_;
  ### set_heading_position() ...
  my $richtext = $self->{'richtext'};

  my $heading = $richtext->GetRange($startpos, $endpos);
  $heading =~ s/\s+$//; # trailing whitespace
  push @{$richtext->{'heading_list'}}, $heading;
  $richtext->{'section_positions'}->{$heading} = $startpos;
  $heading = lc($heading);
  if (! defined $richtext->{'section_positions'}->{$heading}) {
    $richtext->{'section_positions'}->{$heading} = $startpos;
  }
  $richtext->emit_changed('heading_list');
}
sub set_item_range {
  my ($self, $startpos, $endpos) = @_;

  my $richtext = $self->{'richtext'};

  my $item = $richtext->GetRange($startpos, $endpos);
  $item =~ s/\s+$//; # trailing whitespace
  foreach my $name ($item,
                    ($item =~ /(\w+)/ ? $1 : ())) { # also just the first word
    $richtext->{'section_positions'}->{$name} = $startpos;
    my $lname = lc($name);
    if (! defined $richtext->{'section_positions'}->{$lname}) {
      $richtext->{'section_positions'}->{$lname} = $startpos;
    }
  }
}

1;
__END__

=for stopwords Wx Wx-Perl-PodBrowser Ryde PodRichText RichTextCtrl RichTextBuffer RichText PodBrowser

=head1 NAME

Wx::Perl::PodRichText::SimpleParser -- parser for PodRichText

=head1 DESCRIPTION

This is an internal part of C<Wx::Perl::PodRichText>, not
meant for outside use.

The parser is a C<Pod::Simple> sub-class writing to a given target
RichTextCtrl.  Exactly how much it does versus how much it leaves to
PodRichText is not settled, but perhaps in the future it might be possible
to parse into any RichTextCtrl or RichTextBuffer.

C<Pod::Simple> start/end handler calls generate calls to the RichText
C<BeginBold()>, C<EndBold()>, etc, or C<BeginLeftIndent()> and
C<EndLeftIndent()> etc for paragraphs, etc.  RichText indentation is an
amount in millimetres and the current code makes a value which is about two
"em"s of the default font.

=head2 Other Ways to Do It

C<Pod::Parser> is also good for breaking up POD, in combination with
C<Pod::Escape> and C<Pod::ParseLink>.  It's used by L<Wx::Perl::PodEditor>
(in L<Wx::Perl::PodEditor::PodParser>).

An advantage of C<Pod::Simple> is that its C<parse_lines()> allows the main
loop to push a few lines at a time into the parse to process a big document
piec-by-piece.  There's no reason C<Pod::Parser> couldn't do the same but as
of its version 1.37 it doesn't.


=cut

# A "code" stylesheet entry is used for C<< C<> >> and
# verbatim paragraphs to get teletype font.  RichTextCtrl combines that font
# nicely with any bold, italic, etc in or around a C<< C<> >>.
# C<< F<> >> and C<< L<> >> have stylesheet entries too thinking
# perhaps to make them configurable, but perhaps italic and underline are
# enough and don't need the stylesheet.

=pod

=head1 SEE ALSO

L<Pod::Simple>,
L<Wx>,
L<Wx::Perl::PodRichText>

L<Wx::Perl::PodEditor::PodParser>

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
