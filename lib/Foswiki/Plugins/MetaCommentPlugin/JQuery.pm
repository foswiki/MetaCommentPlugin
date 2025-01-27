# Extension for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# JQuery MetaCommentPlugin is Copyright (C) 2021-2025 Michael Daum 
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::MetaCommentPlugin::JQuery;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::MetaCommentPlugin ();
use Foswiki::Plugins::JQueryPlugin::Plugin ();
our @ISA = qw( Foswiki::Plugins::JQueryPlugin::Plugin );

sub new {
  my $class = shift;

  my $this = bless(
    $class->SUPER::new(
      name => 'MetaCommentPlugin',
      version => $Foswiki::Plugins::MetaCommentPlugin::VERSION,
      author => 'Michael Daum',
      homepage => 'https://foswiki.org/Extensions/MetaCommentPlugin',
      javascript => ['pkg.js'],
      css => ['metacomments.css'],
      puburl => '%PUBURLPATH%/%SYSTEMWEB%/MetaCommentPlugin/build',
      dependencies => ['ui', 'form', 'jsonrpc', 'pnotify', 'scrollto'],
    ),
    $class
  );

  return $this;
}

1;
