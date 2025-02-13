# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2025 Michael Daum http://michaeldaumconsulting.com
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
use Foswiki::Plugins::JQueryPlugin ();

our $VERSION = '9.21';
our $RELEASE = '%$RELEASE%';
our $SHORTDESCRIPTION = 'An easy to use comment system';
our $LICENSECODE = '%$LICENSECODE%';
our $NO_PREFS_IN_TOPIC = 1;
our $core;
our @commentHandlers;

sub initPlugin {

  @commentHandlers = ();

  Foswiki::Plugins::JQueryPlugin::registerPlugin("MetaComment", 'Foswiki::Plugins::MetaCommentPlugin::JQuery');

  Foswiki::Func::registerTagHandler('METACOMMENTS', sub {
    return getCore(shift)->METACOMMENTS(@_);
  });

  Foswiki::Func::registerTagHandler('METACOMMENT', sub {
    return getCore(shift)->METACOMMENT(@_);
  });

  Foswiki::Func::registerTagHandler('METASUBSCRIBED', sub {
    return getCore(shift)->METASUBSCRIBED(@_);
  });

  Foswiki::Func::registerRESTHandler('unsubscribe', sub {
      return getCore(shift)->restUnsubscribe(@_);
    },
    authenticate => 1,
    validate => 0,
    http_allow => 'GET',
  );

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

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "deleteAllComments", sub {
    return getCore(shift)->jsonRpcDeleteAllComments(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "subscribe", sub {
    return getCore(shift)->jsonRpcSubscribe(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "unsubscribe", sub {
    return getCore(shift)->jsonRpcUnsubscribe(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "unsubscribeAll", sub {
    return getCore(shift)->jsonRpcUnsubscribeAll(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "approveAllComments", sub {
    return getCore(shift)->jsonRpcApproveAllComments(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "markAllComments", sub {
    return getCore(shift)->jsonRpcMarkAllComments(@_);
  });

  Foswiki::Contrib::JsonRpcContrib::registerMethod("MetaCommentPlugin", "markComment", sub {
    return getCore(shift)->jsonRpcMarkComment(@_);
  });

  my $solrInstalled = (exists $Foswiki::cfg{Plugins}{SolrPlugin} && $Foswiki::cfg{Plugins}{SolrPlugin}{Enabled}) ? 1 :0;
  if ($solrInstalled) {
    require Foswiki::Plugins::SolrPlugin;
    Foswiki::Plugins::SolrPlugin::registerIndexTopicHandler(sub {
      return getCore()->solrIndexTopicHandler(@_);
    });
  }

  my $dbCacheInstalled = (exists $Foswiki::cfg{Plugins}{DBCachePlugin} && $Foswiki::cfg{Plugins}{DBCachePlugin}{Enabled}) ? 1 :0;
  if ($dbCacheInstalled) {
    require Foswiki::Plugins::DBCachePlugin;
    Foswiki::Plugins::DBCachePlugin::registerIndexTopicHandler(sub {
      return getCore()->dbcacheIndexTopicHandler(@_);
    });
  }

  if (exists $Foswiki::cfg{Plugins}{LikePlugin} && $Foswiki::cfg{Plugins}{LikePlugin}{Enabled}) {
    require Foswiki::Plugins::LikePlugin;
    Foswiki::Plugins::LikePlugin::registerAfterLikeHandler(sub {
      return getCore()->afterLikeHandler(@_);
    });
  }

  if (exists $Foswiki::cfg{Plugins}{JQDataTablesPlugin} && $Foswiki::cfg{Plugins}{JQDataTablesPlugin}{Enabled}) {
    # register qmstate properties to JQDataTablesPlugin
    require Foswiki::Plugins::JQDataTablesPlugin;

    if ($dbCacheInstalled) {
      Foswiki::Plugins::JQDataTablesPlugin::describeColumn("dbcache", "comments", {
        type => "number",
        data => 'length(comment)',
        search => 'length(comment)',
        sort => 'length(comment)',
      });
      Foswiki::Plugins::JQDataTablesPlugin::describeColumn("dbcache", "commentdate", {
        type => 'date',
        data => 'commentdate',
        search => 'lc(n2d(commentdate))',
        sort => 'commentdate',
      });
    }

    if ($solrInstalled) {
      Foswiki::Plugins::JQDataTablesPlugin::describeColumn("solr", "comments", {
        type => 'number',
        data => 'field_Comments_d',
        search => 'field_Comments_d',
        sort => 'field_Comments_d',
      });
      Foswiki::Plugins::JQDataTablesPlugin::describeColumn("solr", "commentdate", {
        type => 'date',
        data => 'field_Comments_dt',
        search => 'field_Comments_search',
        sort => 'field_Comments_dt',
      });
    }
  }

  if ($Foswiki::Plugins::VERSION > 2.0) {
    Foswiki::Meta::registerMETA("COMMENT", many => 1, alias => "comment");
    Foswiki::Meta::registerMETA("NOTIFY", many => 1, alias => "notify");
  }

  return 1;
}

sub finishPlugin {
  if (defined $core) {
    $core->finish();
    undef $core;
  }
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

sub beforeSaveHandler {
  my ($text, $topic, $web, $meta) = @_;

  getCore()->beforeSaveHandler($web, $topic, $meta);
}


1;
