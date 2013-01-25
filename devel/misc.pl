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
use FindBin;

# uncomment this to run the ### lines
# use Devel::Comments;

{
  # X<> index entries
  use lib '../pc/devel';
  require MyLocatePerl;
  require MyStuff;
  require Perl6::Slurp;

  sub zap_to_first_pod {
    my ($str) = @_;

    if ($str =~ /^=/) {
      return $str;
    }

    my $pos = index ($str, "\n\n=");
    if ($pos < 0) {
      return $str;
    }
    my $pre = substr($str,0,$pos);
    my $post = substr($str,$pos);
    $pre =~ tr/\n//cd;

    ### $pre
    return $pre.$post;
  }

  sub zap_pod_verbatim {
    my ($str) = @_;
    $str =~ s/^ .*//mg;
    return $str;
  }

  sub grep_X {
    my ($filename, $str) = @_;
    my $print_filename = "$filename:\n";
    $str = zap_to_first_pod($str);
    $str = zap_pod_verbatim($str);
    ### $str

    while ($str =~ /X<+(([^>]|E<[^>]*>)*?)>/g) {
      my $pos = $-[1];
      my $X = $1;
      my ($linenum, $colnum) = MyStuff::pos_to_line_and_column
        ($str, $pos-length($X));
      print $print_filename,' ',$X,"\n";
      $print_filename = '';
    }
  }

    if (1) {
      require File::Slurp;
      my $filename = "$FindBin::Bin/$FindBin::Script";
      $filename = "$ENV{HOME}/p/path/lib/Math/PlanePath/SquareSpiral.pm";
      # $filename = "/usr/share/perl/5.14.2/pod/perltoc.pod";
      my $str = Perl6::Slurp::slurp($filename);
      grep_X ($filename, $str);
      # exit 0;
    }

  my $l = MyLocatePerl->new (include_pod => 1,
                             exclude_t => 1);
  while (my ($filename, $str) = $l->next) {
    #  next if $filename =~ m{/perltoc\.pod$};
    # if ($verbose) { print "look at $filename\n"; }
    grep_X ($filename, $str);
  }

  exit 0;
}

{
  my $str = "1\n2\n";
  open my $fh, '<', \$str or die;
  my $line = <$fh>;
  print $line;
  exit 0;
}

{
  require Wx;
  print "wxRichTextLineBreakChar is ",Wx::wxRichTextLineBreakChar(),"\n";
  print "can(wxRichTextLineBreakChar) is ",Wx->can('wxRichTextLineBreakChar'),"\n";
  exit 0;
}

{
  require Wx;
  my $app = Wx::SimpleApp->new;
  my $frame = Wx::Frame->new(undef, Wx::wxID_ANY(), 'Pod');
  require Wx::Perl::PodEditor;
  my $editor = Wx::Perl::PodEditor->create( $frame, [500,220] );
  $editor->set_pod ();
  $frame->Show;
  $app->MainLoop;
  exit 0;
}

