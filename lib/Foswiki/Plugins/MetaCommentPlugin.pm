# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2017 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
package Foswiki::Plugins::MetaCommentPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Contrib::JsonRpcContrib ();

our $VERSION = '5.01';
our $RELEASE = '16 Jan 2017';
our $SHORTDESCRIPTION = 'An easy to use comment system';
our $NO_PREFS_IN_TOPIC = 1;
our $core;
our @commentHandlers;

sub initPlugin {

  $core = undef;
  @commentHandlers = ();

  Foswiki::Func::registerTagHandler('METACOMMENTS', sub {
    return getCore(shift)->METACOMMENTS(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "getComment", sub {
    return getCore(shift)->jsonRpcGetComment(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "saveComment", sub {
    return getCore(shift)->jsonRpcSaveComment(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "approveComment", sub {
    return getCore(shift)->jsonRpcApproveComment(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "updateComment", sub {
    return getCore(shift)->jsonRpcUpdateComment(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "deleteComment", sub {
    return getCore(shift)->jsonRpcDeleteComment(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "markComment", sub {
    return getCore(shift)->jsonRpcMarkComment(@_);
  });

  if ($Foswiki::cfg{Plugins}{SolrPlugin} && $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) {
    require Foswiki::Plugins::SolrPlugin;
    Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(sub {
      return getCore()->solrIndexTopicHandler(@_);
    });
  }

  if ($Foswiki::cfg{Plugins}{DBCachePlugin}{Enabled}) {
    require Foswiki::Plugins::DBCachePlugin;
    Foswiki::Plugins::DBCachePlugin::registerIndexTopicHandler(sub {
      return getCore()->dbcacheIndexTopicHandler(@_);
    });
  }

  if ($Foswiki::cfg{Plugins}{LikePlugin}{Enabled}) {
    require Foswiki::Plugins::LikePlugin;
    Foswiki::Plugins::LikePlugin::registerAfterLikeHandler(sub {
      return getCore()->afterLikeHandler(@_);
    });
  }

  if ($Foswiki::Plugins::VERSION > 2.0) {
    Foswiki::Meta::registerMETA("COMMENT", many=>1, alias=>"comment");
  }

  return 1;
}

sub getCore {
  unless ($core) {
    my $session = shift || $Foswiki::Plugins::SESSION;

    require Foswiki::Plugins::MetaCommentPlugin::Core;
    $core = new Foswiki::Plugins::MetaCommentPlugin::Core($session, @_);
  }
  return $core;
}

sub registerCommentHandler {
  my ($function, $options) = @_;

  push @commentHandlers, {
    function => $function,
    options => $options,
  };
}

1;
