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

package Foswiki::Plugins::MetaCommentPlugin::Core;

use strict;
use warnings;

use Foswiki::Plugins ();
use Foswiki::Contrib::JsonRpcContrib::Error ();
use Foswiki::Plugins::MetaCommentPlugin ();
use Foswiki::Time ();
use Foswiki::Func ();
use Error qw( :try );
use Digest::MD5 ();

use constant TRACE => 0; # toggle me
use constant DRY => 0; # toggle me

# Error codes for json-rpc response
# 1000: comment does not exist
# 1001: approval not allowed
# 1002: like plugin not installed

###############################################################################
sub new {
  my ($class, $session) = @_;

  my $this = bless({
      session => $session,
      baseWeb => $session->{webName},
      baseTopic => $session->{topicName},
      anonCommenting => $Foswiki::cfg{MetaCommentPlugin}{AnonymousCommenting},
      webNotify => Foswiki::Func::isTrue(Foswiki::Func::getPreferencesValue("COMMENTWEBNOTIFY"), 0),
      commentNotify => Foswiki::Func::isTrue(Foswiki::Func::getPreferencesValue("COMMENTNOTIFY"), 1),
      wikiName => Foswiki::Func::getWikiName(),
    },
    $class
  );

  $this->{anonCommenting} = 0 unless defined $this->{anonCommenting};

  my $context = Foswiki::Func::getContext();
  my $canComment = 0;
  $canComment = 1
    if Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $this->{baseTopic}, $this->{baseWeb})
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $this->{baseTopic}, $this->{baseWeb});

  $canComment = 0 if Foswiki::Func::isGuest() && !$this->{anonCommenting};
  $context->{canComment} = 1 if $canComment; # set a context flag

  return $this;
}

##############################################################################
sub finish {
  my $this = shift;

  undef $this->{session};
  undef $this->{htmlConverter};
}

##############################################################################
sub restUnsubscribe {
  my ($this, $subject, $verb, $response) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  my $user;
  if (Foswiki::Func::getContext()->{isadmin}) {
    my $request = Foswiki::Func::getRequestObject();
    $user = $request->param("wikiName");
  }
  $this->unsubscribe($meta, $user);

  my $url = Foswiki::Func::getScriptUrl($web, $topic, 'view', flashnote => $this->{session}->i18n->maketext("You unsubscribed from this thread."));

  $meta->save(ignorepermissions => 1, minor => !$this->{webNotify}) unless DRY;
  $this->triggerEvent("commentunsubscribe", $meta);

  Foswiki::Func::redirectCgiQuery(undef, $url);

  return "";
}

##############################################################################
sub METACOMMENT {
  my ($this, $params, $topic, $web) = @_;

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($params->{web} // $web, $params->{topic} // $topic);

  return _inlineError("topic does not exist") unless Foswiki::Func::topicExists($web, $topic);
  return _inlineError("access denied") unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web);

  my $id = $params->{_DEFAULT} // $params->{id};
  return _inlineError("undefined id") unless defined $id;

  my $request = Foswiki::Func::getRequestObject();
  my $rev = $params->{rev} // $request->param('rev');
  my ($meta) = Foswiki::Func::readTopic($web, $topic, $rev);

  my $comment = $meta->get('COMMENT', $id);
  return _inlineError("unknown comment") unless $comment;

  my $result = $params->{format} // '$text';
  my $titleOrText = $this->titleOrText($comment->{title}, $comment->{text}, 22);

  $result =~ s/\$topic/$topic/g;
  $result =~ s/\$web/$web/g;
  $result =~ s/\$(id|name)\b/$comment->{name}/g;
  $result =~ s/\$author\b/$comment->{author}/g;
  $result =~ s/\$date\b/$comment->{date}/g;
  $result =~ s/\$lang\b/$comment->{lang}/g;
  $result =~ s/\$modified\b/$comment->{modified}/g;
  $result =~ s/\$read\b/$comment->{read}/g;
  $result =~ s/\$ref\b/$comment->{ref}/g;
  $result =~ s/\$state\b/$comment->{state}/g;
  $result =~ s/\$title\b/$comment->{title}/g;
  $result =~ s/\$titleOrText\b/$titleOrText/g;

  $result = Foswiki::Func::decodeFormatTokens($result) if $result =~ /%/;

  $result =~ s/\$text\b/$comment->{text}/g;

  my $encode = $params->{encode} // '';
  $result = Foswiki::entityEncode($result) if $encode eq 'entity';
  $result = Foswiki::urlEncode($result) if $encode eq 'url';

  return $result;
}

##############################################################################
sub jsonRpcGetComment {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web);

  my $rev = $request->param('rev');
  my ($meta) = Foswiki::Func::readTopic($web, $topic, $rev);

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  return $comment;
}

##############################################################################
sub jsonRpcSaveComment {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    if Foswiki::Func::isGuest() && !$this->{anonCommenting};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $topic, $web, $meta)
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Discussion closed")
    unless $isModerator || (Foswiki::Func::getPreferencesValue("COMMENTSTATE") || 'open') ne 'closed';

  my $author = $request->param('author') || $this->{wikiName};
  my $title = $request->param('title') || '';
  my $cmtText = $request->param('text') || '';
  my $ref = $request->param('ref') || '';
  my $id = getNewId($meta);
  my $date = time();
  my $fingerPrint = getFingerPrint($author);
  my $textFormat = $request->param("_text_format") || 'undef';
  _deleteParam("_text_format");

  $cmtText = $this->getHtmlConverter->convert($cmtText, $meta) if $textFormat eq 'html';

  my $state = "new";

  if ($this->isModerated($web, $topic, $meta)) {
    if ($this->isModerator($web, $topic, $meta)) {
      $state = "approved";
    } else {
      $state = "unapproved";
    }
  }

  my $lang = $this->{session}->i18n->language();

  my $comment = {
    author => $author,
    lang => $lang,
    fingerPrint => $fingerPrint,
    state => $state,
    date => $date,
    modified => $date,
    name => $id,
    ref => $ref,
    text => $cmtText,
    title => $title,
    read => $this->{wikiName},
  };

  $meta->putKeyed('COMMENT', $comment);

  my $subscribe = $request->param('subscribe');
  if (defined $subscribe) {
    $subscribe = shift @$subscribe if ref $subscribe;
    if (Foswiki::Func::isTrue($subscribe)) {
      $this->subscribe($meta);
    } else {
      $this->unsubscribe($meta);
    }
  }

  # mark ref as read as well as all sub-comments
  $this->markThread($meta, $ref);

  unless (DRY) {
    $meta->save(
      ignorepermissions => 1,
      minor => !$this->{webNotify},
      dontlog => 1,
    );
  }

  $this->triggerEvent("commentsave", $meta, $comment);

  return;
}

# mark all comments starting at a given reference
sub markThread {
  my ($this, $meta, $nameOrComment, $seen) = @_;

  return unless $nameOrComment;

  my $comment;
  my $name;

  if (ref($nameOrComment)) {
    $comment = $nameOrComment;
    $name = $comment->{name};
  } else {
    $name = $nameOrComment;
    $comment = $meta->get('COMMENT', $name);
  }
  return unless $comment;

  $seen ||= {};
  return if $seen->{$name};
  $seen->{$name} = 1;

  $this->markComment($comment);

  # mark all sub-comments
  foreach my $subComment ($meta->find('COMMENT')) {
    next unless $subComment->{ref} eq $name;
    $this->markThread($meta, $subComment, $seen);
  }
}

sub saveComment {
  my ($this, $meta, $comment) = @_;

  $meta->putKeyed('COMMENT', $comment);

  unless (DRY) {
    $meta->save(
      ignorepermissions => 1,
      minor => !$this->{webNotify},
      dontlog => 1,
    );
  }
}

sub extractInlineImages {
  my ($this, $meta, $text) = @_;

  my $imageCore = $this->getImageCore();
  return unless $imageCore;
  return unless $imageCore->{autoAttachInlineImages};

  return $imageCore->extractInlineImages($meta, $text);
}

##############################################################################
sub subscribe {
  my ($this, $meta, $user) = @_;

  ($meta) = Foswiki::Func::readTopic($this->{baseWeb}, $this->{baseTopic})
    unless $meta;
  $user ||= $this->{wikiName};

  $meta->putKeyed(
    "NOTIFY",
    {
      name => $user,
      date => time(),
      state => "enabled"
    }
  );
}

##############################################################################
sub unsubscribe {
  my ($this, $meta, $user) = @_;

  ($meta) = Foswiki::Func::readTopic($this->{baseWeb}, $this->{baseTopic})
    unless $meta;
  $user ||= $this->{wikiName};

  my $notify = $this->getSubscriptionOfUser($meta, $user);
  return unless $notify;

  $notify->{date} = time();
  $notify->{state} = "disabled";

  $meta->putKeyed("NOTIFY", $notify);
}

##############################################################################
sub getSubscriptions {
  my ($this, $meta) = @_;

  ($meta) = Foswiki::Func::readTopic($this->{baseWeb}, $this->{baseTopic})
    unless $meta;

  return $meta->find("NOTIFY");
}

##############################################################################
sub getSubscriptionOfUser {
  my ($this, $meta, $user) = @_;

  ($meta) = Foswiki::Func::readTopic($this->{baseWeb}, $this->{baseTopic})
    unless $meta;
  $user ||= $this->{wikiName};

  return $meta->get("NOTIFY", $user);
}

##############################################################################
sub isSubscribed {
  my ($this, $meta, $user, $default) = @_;

  my $notify = $this->getSubscriptionOfUser($meta, $user);
  $default //= 0;

  return $default unless $notify;
  return 1 unless defined $notify->{state};

  return $notify->{state} eq 'enabled';
}

##############################################################################
sub isUnsubscribed {
  my ($this, $meta, $user) = @_;

  my $notify = $this->getSubscriptionOfUser($meta, $user);

  return 0 unless defined $notify; # no explicit unsubscribe
  return 0 unless defined $notify->{state};

  return $notify->{state} eq 'disabled';
}

##############################################################################
sub getFingerPrint {
  my $author = shift;

  if ($author eq $Foswiki::cfg{DefaultUserWikiName}) {

    # the fingerprint of a guest matches for one hour
    my $timeStamp = Foswiki::Time::formatTime(time(), '$year-$mo-$day-$hours');

    $author = ($ENV{REMOTE_ADDR} || '???') . '::' . $timeStamp;
  }

  return Digest::MD5::md5_hex($author);

}

##############################################################################
sub jsonRpcApproveComment {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1001, "Approval not allowed")
    unless $isModerator;

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  # set the state
  $comment->{state} = "approved";

  $meta->save(ignorepermissions => 1, minor => 1) unless DRY;

  $this->triggerEvent("commentapprove", $meta, $comment);

  return;
}

##############################################################################
sub jsonRpcUpdateComment {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $topic, $web, $meta)
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Discussion closed")
    unless $isModerator || (Foswiki::Func::getPreferencesValue("COMMENTSTATE") || 'open') ne 'closed';

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  my $fingerPrint = getFingerPrint($this->{wikiName});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless $isModerator || $fingerPrint eq ($comment->{fingerPrint} || '');

  my $title = $request->param('title') || '';
  my $cmtText = $request->param('text') || '';
  my $modified = time();
  my $ref = $request->param('ref');
  $ref = $comment->{ref} unless defined $ref;
  my $textFormat = $request->param("_text_format") || 'undef';
  _deleteParam("_text_format");

  $cmtText = $this->getHtmlConverter->convert($cmtText, $meta) if $textFormat eq 'html';

  my $state = "updated";
  $state = "unapproved" if $this->isModerated($web, $topic, $meta) && $comment->{state} =~ /\bunapproved\b/;

  my $lang = $comment->{lang} || $this->{session}->i18n->language();

  $comment = {
    author => $comment->{author},
    lang => $lang,
    fingerPrint => $comment->{fingerPrint},
    date => $comment->{date},
    state => $state,
    modified => $modified,
    name => $id,
    text => $cmtText,
    title => $title,
    ref => $ref,
    read => $this->{wikiName},
  };

  $meta->putKeyed('COMMENT', $comment);

  my $subscribe = $request->param('subscribe');
  if (defined $subscribe) {
    $subscribe = shift @$subscribe if ref $subscribe;
    if (Foswiki::Func::isTrue($subscribe)) {
      $this->subscribe($meta);
    } else {
      $this->unsubscribe($meta);
    }
  }

  # mark ref as read as well as all sub-comments
  $this->markThread($meta, $ref);

  $meta->save(
    ignorepermissions => 1,
    minor => !$this->{webNotify}
  ) unless DRY;
  $this->triggerEvent("commentupdate", $meta, $comment);

  return;
}

##############################################################################
sub jsonRpcDeleteComment {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $topic, $web, $meta)
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Discussion closed")
    unless $isModerator || (Foswiki::Func::getPreferencesValue("COMMENTSTATE") || 'open') ne 'closed';

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  my $fingerPrint = getFingerPrint($this->{wikiName});

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless $isModerator || $fingerPrint eq ($comment->{fingerPrint} || '');

  # relocate replies by assigning them to the parent
  my $parentId = $comment->{ref} || '';
  my $parentComment = $meta->get('COMMENT', $parentId);
  my $parentName = $parentComment ? $parentComment->{name} : '';

  foreach my $reply ($meta->find('COMMENT')) {
    next unless $reply->{ref} && $reply->{ref} eq $comment->{name};
    $reply->{ref} = $parentName;
  }

  # remove this comment
  $meta->remove('COMMENT', $id);

  $meta->save(
    ignorepermissions => 1,
    minor => !$this->{webNotify}
  ) unless DRY;

  $this->triggerEvent("commentdelete", $meta, $comment);

  return;
}

##############################################################################
sub jsonRpcDeleteAllComments {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $topic, $web, $meta)
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Discussion closed")
    unless $isModerator || (Foswiki::Func::getPreferencesValue("COMMENTSTATE") || 'open') ne 'closed';

  my $fingerPrint = getFingerPrint($this->{wikiName});

  # check all comments
  foreach my $comment ($meta->find('COMMENT')) {
    throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
      unless $isModerator || $fingerPrint eq ($comment->{fingerPrint} || '');
  }

  # remove all comments
  $meta->remove('COMMENT');

  $meta->save(ignorepermissions => 1, minor =>) unless DRY;
  $this->triggerEvent("commentdeleteall", $meta);

  return;
}

##############################################################################
sub jsonRpcSubscribe {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $topic, $web, $meta)
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  $this->subscribe($meta);

  $meta->save(ignorepermissions => 1, minor => !$this->{webNotify}) unless DRY;

  return $this->{session}->i18n->maketext("You subscribed to this thread.");
}

sub jsonRpcUnsubscribe {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $topic, $web, $meta)
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  $this->unsubscribe($meta);

  $meta->save(ignorepermissions => 1, minor => !$this->{webNotify}) unless DRY;

  return $this->{session}->i18n->maketext("You unsubscribed from this thread.");
}

##############################################################################
sub jsonRpcUnsubscribeAll {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $topic, $web, $meta)
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless $isModerator;

  # disable all subscriptions
  foreach my $notify ($this->getSubscriptions($meta)) {
    $notify->{state} = 'disabled';
  }

  $meta->save(ignorepermissions => 1, minor => 1) unless DRY;
  $this->triggerEvent("commentunsubscribeall", $meta);

  return;
}

##############################################################################
sub jsonRpcApproveAllComments {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $topic, $web, $meta)
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  my $isModerator = $this->isModerator($web, $topic, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Discussion closed")
    unless $isModerator || (Foswiki::Func::getPreferencesValue("COMMENTSTATE") || 'open') ne 'closed';

  my $fingerPrint = getFingerPrint($this->{wikiName});

  # check all comments
  foreach my $comment ($meta->find('COMMENT')) {
    throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
      unless $isModerator || $fingerPrint eq ($comment->{fingerPrint} || '');
  }

  # approve all comments
  foreach my $comment ($meta->find('COMMENT')) {
    $comment->{state} = "approved";
  }

  $meta->save(ignorepermissions => 1, minor => 1) unless DRY;
  $this->triggerEvent("commentapproveall", $meta);

  return;
}

##############################################################################
sub jsonRpcMarkAllComments {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $topic, $web, $meta)
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  # mark all comments
  foreach my $comment ($meta->find('COMMENT')) {
    $this->markComment($comment);
  }

  $meta->save(ignorepermissions => 1, minor => 1) unless DRY;
  $this->triggerEvent("commentmarkall", $meta);

  return;
}

##############################################################################
sub jsonRpcMarkComment {
  my ($this, $request) = @_;

  my $web = $this->{baseWeb};
  my $topic = $this->{baseTopic};

  throw Foswiki::Contrib::JsonRpcContrib::Error(404, "Topic $web.$topic does not exist")
    unless Foswiki::Func::topicExists($web, $topic);

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission("VIEW", $this->{wikiName}, undef, $topic, $web, $meta);

  throw Foswiki::Contrib::JsonRpcContrib::Error(401, "Access denied")
    unless Foswiki::Func::checkAccessPermission('COMMENT', $this->{wikiName}, undef, $topic, $web, $meta)
    || Foswiki::Func::checkAccessPermission('CHANGE', $this->{wikiName}, undef, $topic, $web, $meta);

  my $id = $request->param('comment_id') || '';
  my $comment = $meta->get('COMMENT', $id);

  throw Foswiki::Contrib::JsonRpcContrib::Error(1000, "Comment not found")
    unless $comment;

  $this->markComment($comment);

  $meta->save(ignorepermissions => 1, minor => 1) unless DRY;
  $this->triggerEvent("commentmark", $meta, $comment);

  return;
}

###############################################################################
sub markComment {
  my ($this, $comment, $user) = @_;

  return unless defined $comment;
  $user ||= $this->{wikiName};

  my %readUsers = ();
  if ($comment->{read}) {
    foreach my $user (split(/\s*,\s*/, $comment->{read})) {
      $user =~ s/^\s+//;
      $user =~ s/\s+$//;
      $readUsers{$user} = 1;
    }
  }

  $readUsers{$user} = 1;
  $comment->{read} = join(', ', sort keys %readUsers);

  return $comment;
}

##############################################################################
sub isModerator {
  my ($this, $web, $topic, $meta) = @_;

  return 1 if Foswiki::Func::isAnAdmin();
  return 1
    if $this->isModerated($web, $topic, $meta)
    && Foswiki::Func::checkAccessPermission("MODERATE", $this->{wikiName}, undef, $topic, $web, $meta);
  return 0;
}

##############################################################################
sub isModerated {
  my ($this, $web, $topic, $meta) = @_;

  ($meta) = Foswiki::Func::readTopic($web, $topic) unless defined $meta;

  my $prefs = $this->{session}->{prefs}->loadPreferences($meta);
  my $isModerated = $prefs->get("COMMENTMODERATION");
  $isModerated = $prefs->getLocal("COMMENTMODERATION") unless defined $isModerated;
  $isModerated = Foswiki::Func::getPreferencesValue("COMMENTMODERATION", $web) unless defined $isModerated;

  return Foswiki::Func::isTrue($isModerated, 0);
}

##############################################################################
sub METASUBSCRIBED {
  my ($this, $params, $topic, $web) = @_;

  my ($theWeb, $theTopic) = Foswiki::Func::normalizeWebTopicName($params->{web} // $web, $params->{topic} // $topic);
  my $user = $params->{user} // $params->{_DEFAULT} // $this->{wikiName};
  my $default = Foswiki::isTrue($params->{default});

  my ($meta) = Foswiki::Func::readTopic($theWeb, $theTopic, $params->{rev});

  return "" unless $this->isSubscribed($meta, $user, $default);
  return $params->{format} // "on";
}

##############################################################################
sub METACOMMENTS {
  my ($this, $params, $topic, $web) = @_;

  my $context = Foswiki::Func::getContext();
  if ($context->{"preview"} || $context->{"save"} || $context->{"edit"}) {
    return '';
  }

  Foswiki::Func::readTemplate("metacomments");

  # sanitize params
  $params->{topic} ||= $topic;
  $params->{web} ||= $web;
  my ($theWeb, $theTopic) = Foswiki::Func::normalizeWebTopicName($params->{web}, $params->{topic});
  $params->{topic} = $theTopic;
  $params->{web} = $theWeb;
  $params->{format} = '<h3>$title</h3>$text'
    unless defined $params->{format};
  $params->{format} = Foswiki::Func::expandTemplate($params->{template})
    if defined $params->{template};
  $params->{subformat} = $params->{format}
    unless defined $params->{subformat};
  $params->{subformat} = Foswiki::Func::expandTemplate($params->{subtemplate})
    if defined $params->{subtemplate};
  unless (defined $params->{subheader}) {
    $params->{subheader} = "<div class='cmtSubComments'>";
    $params->{subfooter} = "</div>";
  }
  $params->{subfooter} ||= '';
  $params->{header} ||= '';
  $params->{footer} ||= '';
  $params->{separator} ||= '';
  $params->{ref} ||= '';
  $params->{skip} ||= 0;
  $params->{limit} ||= 0;
  $params->{moderation} ||= 'off';
  $params->{reverse} ||= 'off';
  $params->{sort} ||= 'name';
  $params->{null} //= "";
  $params->{singular} = 'One comment'
    unless defined $params->{singular};
  $params->{plural} = '$count comments'
    unless defined $params->{plural};
  $params->{mindate} = Foswiki::Time::parseTime($params->{mindate})
    if defined $params->{mindate} && $params->{mindate} !~ /^\d+$/;
  $params->{maxdate} = Foswiki::Time::parseTime($params->{maxdate})
    if defined $params->{maxdate} && $params->{mindate} !~ /^\d+$/;
  $params->{threaded} = 'off'
    unless defined $params->{threaded};
  $params->{isclosed} = ((Foswiki::Func::getPreferencesValue("COMMENTSTATE") || 'open') eq 'closed') ? 1 : 0;
  $params->{rev} //= $params->{revision};

  my ($meta) = Foswiki::Func::readTopic($theWeb, $theTopic, $params->{rev});
  $params->{ismoderator} = $this->isModerator($theWeb, $theTopic, $meta);
  $params->{ismoderated} = $this->isModerated($theWeb, $theTopic, $meta);
  $context->{ismoderator} = 1 if $params->{ismoderator};
  $context->{ismoderated} = 1 if $params->{ismoderated};

  my $isSubscribed = $this->isSubscribed($meta) ? "on" : "off";
  $context->{subscribed} = 1 if $isSubscribed eq "on";

  # get all comments data
  my $comments = $this->getComments($theWeb, $theTopic, $meta, $params);

  return $params->{null} unless $comments;
  my $count = scalar(keys %$comments);
  return $params->{null} unless $count;

  $params->{count} = ($count > 1) ? $params->{plural} : $params->{singular};
  $params->{count} =~ s/\$count/$count/g;

  # format the results
  my @topComments;
  if ($params->{threaded} eq 'on') {
    @topComments = grep { !$_->{ref} } values %$comments;
  } else {
    @topComments = values %$comments;
  }
  my %seen = ();
  my @result = $this->formatComments(\@topComments, $params, undef, \%seen);

  my $result = expandVariables(
    $params->{header},
    count => $params->{count},
    ismoderator => $params->{ismoderator},
    ismoderated => $params->{ismoderated},
    )
    . join(expandVariables($params->{separator}), @result)
    . expandVariables(
    $params->{footer},
    count => $params->{count},
    ismoderator => $params->{ismoderator},
    ismoderated => $params->{ismoderated},
    );

  $result =~ s/\$subscribed\b/$isSubscribed/g;
  $result =~ s/\$perce?nt/\%/g;
  $result =~ s/\$nop//g;
  $result =~ s/\$n/\n/g;
  $result =~ s/\$dollar/\$/g;
  $result =~ s/\\\\/\\/g;
  $result =~ s/\0(.*?)\0/$seen{$1}/g;

  return $result;
}

##############################################################################
sub getComments {
  my ($this, $web, $topic, $meta, $params) = @_;

  ($meta) = Foswiki::Func::readTopic($web, $topic, $params->{rev}) unless defined $meta;

  my $isModerator = $this->isModerator($web, $topic, $meta);

  _writeDebug("called getComments web=$web");

  my @topics = ();
  if (defined $params->{search}) {
    @topics = $this->getTopics($web, $params->{search}, $params);
  } else {
    return unless Foswiki::Func::checkAccessPermission('VIEW', $this->{wikiName}, undef, $topic, $web);
    push @topics, $topic;
  }

  my $fingerPrint = getFingerPrint($this->{wikiName});
  my %comments = ();

  foreach my $thisTopic (@topics) {
    ($meta) = Foswiki::Func::readTopic($web, $thisTopic, $params->{rev});
    my $isModerated = $this->isModerated($web, $thisTopic, $meta);

    my @comments = $meta->find('COMMENT');
    foreach my $comment (@comments) {
      my $id = $comment->{name};
      _writeDebug("id=$id, moderation=$params->{moderation}, isModerator=$isModerator, author=$comment->{author}, wikiName=$this->{wikiName}, state=$comment->{state}, isclosed=$params->{isclosed}");
      next if $params->{author} && $comment->{author} !~ /$params->{author}/;
      next if $params->{mindate} && $comment->{date} < $params->{mindate};
      next if $params->{maxdate} && $comment->{date} > $params->{maxdate};
      next if $params->{id} && $id ne $params->{id};
      next if $params->{ref} && $params->{ref} ne $comment->{ref};
      next if $params->{state} && (!$comment->{state} || $comment->{state} !~ /^($params->{state})$/);
      if ($isModerated) {
        next if $params->{moderation} eq 'on' && !($isModerator || ($comment->{fingerPrint} || '') eq $fingerPrint) && (!$comment->{state} || $comment->{state} =~ /\bunapproved\b/);
        next if $params->{moderation} eq 'on' && $params->{isclosed} && (!$comment->{state} || $comment->{state} =~ /\bunapproved\b/);
      }

      next
        if $params->{include}
        && !($comment->{author} =~ /$params->{include}/ || $comment->{title} =~ /$params->{include}/ || $comment->{text} =~ /$params->{include}/);

      next
        if $params->{exclude}
        && ($comment->{author} =~ /$params->{exclude}/
        || $comment->{title} =~ /$params->{exclude}/
        || $comment->{text} =~ /$params->{exclude}/);

      $comment->{topic} = $thisTopic;
      $comment->{web} = $web;

      _writeDebug("adding $id");
      $comments{$thisTopic . '::' . $id} = $comment;
    }
  }

  # gather children
  if ($params->{threaded} && $params->{threaded} eq 'on') {
    while (my ($key, $cmt) = each %comments) {
      next unless $cmt->{ref};
      my $parent = $comments{$cmt->{topic} . '::' . $cmt->{ref}};
      if ($parent) {
        push @{$parent->{children}}, $cmt;
      } else {
        #_writeDebug("parent $cmt->{ref} not found for $cmt->{name}");
        delete $comments{$key};
      }
    }
    # mark all reachable children and remove the unmarked
    while (my ($key, $cmt) = each %comments) {
      $cmt->{_tick} = 1 unless $cmt->{ref};
      next unless $cmt->{children};
      foreach my $child (@{$cmt->{children}}) {
        $child->{_tick} = 1;
      }
    }
    while (my ($key, $cmt) = each %comments) {
      next if $cmt->{_tick};
      #_writeDebug("found unticked comment $cmt->{name}");
      delete $comments{$key};
    }
  }

  return \%comments;
}

##############################################################################
sub getTopics {
  my $this = shift;

  if ($Foswiki::cfg{Plugins}{DBCachePlugin}{Enabled}) {
    require Foswiki::Plugins::DBCachePlugin;
    return $this->getTopics_DBQUERY(@_);
  } else {
    return $this->getTopics_SEARCH(@_);
  }
}

##############################################################################
sub getTopics_DBQUERY {
  my ($this, $web, $where, $params) = @_;

  my $search = new Foswiki::Contrib::DBCacheContrib::Search($where);
  return unless $search;

  my $db = Foswiki::Plugins::DBCachePlugin::getDB($web);
  my @topicNames = $db->getKeys();
  my @selectedTopics = ();

  foreach my $topic (@topicNames) { # loop over all topics
    my $topicObj = $db->fastget($topic);
    next unless $search->matches($topicObj); # that match the query

    next
      unless Foswiki::Func::isAnAdmin($this->{wikiName})
      || Foswiki::Func::checkAccessPermission('VIEW', $this->{wikiName}, undef, $topic, $web);

    my $commentDate = $topicObj->fastget("commentdate");
    next unless $commentDate;
    push @selectedTopics, $topic;
  }

  return @selectedTopics;
}

##############################################################################
sub getTopics_SEARCH {
  my ($this, $web, $where, $params) = @_;

  $where .= ' and comment';

  #print STDERR "where=$where, web=$web\n";

  my $matches = Foswiki::Func::query(
    $where, undef,
    {
      web => $web,
      casesensitive => 0,
      files_without_match => 1
    }
  );

  my @selectedTopics = ();
  while ($matches->hasNext) {
    my $topic = $matches->next;
    (undef, $topic) = Foswiki::Func::normalizeWebTopicName('', $topic);
    push @selectedTopics, $topic;
  }

  #print STDERR "topics=".join(', ', @selectedTopics)."\n";
  return @selectedTopics;
}

##############################################################################
sub formatComments {
  my ($this, $comments, $params, $parentIndex, $seen) = @_;

  $parentIndex ||= '';
  $seen ||= {};
  my @result = ();
  my $index = $params->{index} || 0;
  my @sortedComments;

  if ($params->{sort} eq 'name') {
    @sortedComments = sort { $a->{name} <=> $b->{name} } @$comments;
  } elsif ($params->{sort} eq 'date') {
    @sortedComments = sort { $a->{date} <=> $b->{date} } @$comments;
  } elsif ($params->{sort} eq 'modified') {
    @sortedComments = sort { $a->{modified} <=> $b->{modified} } @$comments;
  } elsif ($params->{sort} eq 'author') {
    @sortedComments = sort { $a->{author} cmp $b->{author} } @$comments;
  } elsif ($params->{sort} eq 'likes') {
    @sortedComments = sort { ($a->{likes} || 0) - ($a->{dislikes} || 0) <=> ($b->{likes} || 0) - ($b->{dislikes} || 0) } @$comments;
  }

  @sortedComments = reverse @sortedComments if $params->{reverse} eq 'on';
  my $count = scalar(@sortedComments);
  foreach my $comment (@sortedComments) {
    next if $seen->{$comment->{name}};
    $seen->{$comment->{name}} = $comment->{text};

    $index++;
    next if $params->{skip} && $index <= $params->{skip};
    my $indexString = ($params->{reverse} eq 'on') ? ($count - $index + 1) : $index;
    $indexString = "$parentIndex.$indexString" if $parentIndex;

    # insert subcomments
    my $subComments = '';
    if ($params->{format} =~ /\$subcomments/ && $comment->{children}) {
      my $oldFormat = $params->{format};
      $params->{format} = $params->{subformat};
      $subComments = join(expandVariables($params->{separator}), $this->formatComments($comment->{children}, $params, $indexString, $seen));
      $params->{format} = $oldFormat;
      if ($subComments) {
        $subComments = expandVariables(
          $params->{subheader},
          count => $params->{count},
          index => $indexString,
          ismoderator => $params->{ismoderator},
          ismoderated => $params->{ismoderated},
          )
          . $subComments
          . expandVariables(
          $params->{subfooter},
          count => $params->{count},
          ismoderator => $params->{ismoderator},
          ismoderated => $params->{ismoderated},
          index => $indexString
          );
      }
    }

    my $summary = '';
    my $text = $comment->{text};
    $text =~ s/\s+$//g;
    if ($params->{format} =~ /\$summary/) {
      $summary = substr($text, 0, 100);
      $summary =~ s/^\s*\-\-\-\++//g; # don't remove heading, just strip tml
      $summary = $this->{session}->renderer->TML2PlainText($summary, undef, "showvar") . " ...";
      $summary =~ s/\n/<br \/>/g;
    }

    my $permlink = Foswiki::Func::getScriptUrl($comment->{web}, $comment->{topic}, "view", "#" => "comment" . ($comment->{name} || 0));

    my $isNew = ($comment->{state} eq 'new' && (!$comment->{read} || $comment->{read} !~ /\b$this->{wikiName}\b/)) ? 1 : 0;
    my $isUpdated = ($comment->{state} eq 'updated' && (!$comment->{read} || $comment->{read} !~ /\b$this->{wikiName}\b/)) ? 1 : 0;

    my $line = expandVariables(
      $params->{format},
      authorurl => $comment->{author_url},
      author => $comment->{author},
      lang => $comment->{lang} // '',
      state => $comment->{state},
      count => $params->{count},
      ismoderator => $params->{ismoderator},
      ismoderated => $params->{ismoderated},
      timestamp => $comment->{date} || 0,
      date => Foswiki::Time::formatTime(($comment->{date} || 0)),
      datetime => Foswiki::Time::formatTime(($comment->{date} || 0), $Foswiki::cfg{DateManipPlugin}{DefaultDateTimeFormat} || '$day $mon $year - $hour:$min'),
      modified => Foswiki::Time::formatTime(($comment->{modified} || 0)),
      rssdate => Foswiki::Func::formatTime($comment->{modified} || $comment->{date}, '$wday, $day $mon $year $hour:$min:$second %z'),
      isodate => Foswiki::Func::formatTime($comment->{modified} || $comment->{date}, 'iso'),
      evenodd => ($index % 2) ? 'Odd' : 'Even',
      id => ($comment->{name} || 0),
      index => $indexString,
      ref => ($comment->{ref} || ''),
      text => "\0$comment->{name}\0",
      title => $comment->{title},
      titleOrText => $this->titleOrText($comment->{title}, $comment->{text}, 20),
      subcomments => $subComments,
      topic => $comment->{topic},
      web => $comment->{web},
      summary => $summary,
      permlink => $permlink,
      isnew => $isNew,
      isupdated => $isUpdated,
      likes => ($comment->{likes} || 0),
      dislikes => ($comment->{dislikes} || 0),
    );

    next unless $line;

    push @result, $line;
    last if $params->{limit} && $index >= $params->{limit};
  }

  return @result;
}

##############################################################################
sub getNewId {
  my $meta = shift;

  my @comments = $meta->find('COMMENT');
  my $maxId = 0;
  foreach my $comment (@comments) {
    my $id = int($comment->{name});
    $maxId = $id if $id > $maxId;
  }

  $maxId++;

  return "$maxId." . time();
}

##############################################################################
sub expandVariables {
  my ($text, %params) = @_;

  return '' unless $text;

  foreach my $key (keys %params) {
    my $val = $params{$key};
    $val = '' unless defined $val;
    $text =~ s/\$$key\b/$val/g;
  }

  return $text;
}

##############################################################################
# available events
#    * commentsave
#    * commentapprove
#    * commetupdate
#    * commentdelete
#    * commentdeleteall
#    * commentappriveall
#    * commentmark
#    * commentmarkall
#    * commentubsubscrib
#    * commentunsubscribeall
sub triggerEvent {
  my ($this, $eventName, $meta, $comment) = @_;

  my $message = "";
  if ($comment) {
    $message = "state=$comment->{state} title=" . ($comment->{title} || '') . ' text=' . _plainify(substr($comment->{text}, 0, 200));
  }

  Foswiki::Func::writeEvent($eventName, $message);

  $this->sendNotification($eventName, $meta, $comment);
  $this->publishEvent($eventName, $meta, $comment);

  # call comment handlers
  foreach my $commentHandler (@Foswiki::Plugins::MetaCommentPlugin::commentHandlers) {
    my $function = $commentHandler->{function};
    my $result;
    my $error;

    _writeDebug("executing $function");
    try {
      no strict 'refs'; ## no critics
      $result = &$function($eventName, $meta->web, $meta->topic, $comment, $commentHandler->{options});
      use strict 'refs';
    } catch Error::Simple with {
      $error = shift;
    };

    print STDERR "error executing commentHandler $function: " . $error . "\n" if defined $error;
  }
}

##############################################################################
sub publishEvent {
  my ($this, $eventName, $meta, $comment) = @_;

  return unless exists $Foswiki::cfg{Plugins}{WebSocketPlugin}{Enabled} && $Foswiki::cfg{Plugins}{WebSocketPlugin}{Enabled};
  require Foswiki::Plugins::WebSocketPlugin;

  my $web = $meta->web;
  my $topic = $meta->topic;
  $web =~ s/\//\./g;

  my $message;
  if ($comment) {
    _writeDebug("publishEvent called for $web.$topic comment id=$comment->{name}: event $eventName");
    $message = {
      type => $eventName,
      data => {
        web => $web,
        topic => $topic,
        comment_name => $comment->{name},
        comment_text => $comment->{text},
        comment_title => $comment->{title},
      },
    };
  } else {
    _writeDebug("publishEvent called for $web.$topic: event $eventName");
    $message = {
      type => $eventName,
      data => {
        web => $web,
        topic => $topic,
      },
    };
  }

  my $channelName = $web . "." . $topic;

  return Foswiki::Plugins::WebSocketPlugin::publish($channelName, $message);
}

##############################################################################
sub sendNotification {
  my ($this, $eventName, $meta, $comment) = @_;

  return unless $eventName eq 'commentsave'; # SMELL: what about the other events;
  return unless $this->{commentNotify};

  my $web = $meta->web;
  my $topic = $meta->topic;
  my $isModerated = $this->isModerated($web, $topic, $meta);
  my $isModerator = $this->isModerator($web, $topic, $meta);

  # don't send notifications on unapproved comments except to the moderator
  return if $isModerated && !$isModerator && ($comment->{state} // 'null' ne "approved");

  my @emails = ();
  foreach my $notify ($this->getSubscriptions) {
    next if defined $notify->{state} && $notify->{state} eq 'disabled';
    next unless $this->doNotifyUser($meta, $notify->{name});

    my @thisMails = Foswiki::Func::wikinameToEmails($notify->{name});
    push @emails, $thisMails[0] if @thisMails;
  }

  unless ($this->doNotifySelf($meta)) {
    my %myEmails = map { $_ => 1 } Foswiki::Func::wikinameToEmails();
    @emails = grep { !$myEmails{$_} } @emails;
  }

  return unless @emails;

  _writeDebug("notifying @emails about $eventName in $web.$topic");

  my $context = Foswiki::Func::getContext();
  $context->{has_title} = 1 if defined $comment->{title} && $comment->{title} ne "";

  my $tmpl = $this->getTemplate();

  Foswiki::Func::setPreferencesValue("COMMENT_EMAILS", join(", ", sort @emails));
  Foswiki::Func::setPreferencesValue("COMMENT_ID", $comment->{name});
  Foswiki::Func::setPreferencesValue("COMMENT_TITLE", $comment->{title});
  Foswiki::Func::setPreferencesValue("COMMENT_TEXT", $comment->{text});

  my $text = $tmpl;
  $text = Foswiki::Func::expandCommonVariables($text, $topic, $web, $meta) if $text =~ /%/;

  $text =~ s/^\s+//g;
  $text =~ s/\s+$//g;

  delete $context->{has_title};

  return unless $text;

  _writeDebug("text=$text");
  Foswiki::Func::writeEvent("sendmail", "to=" . join(", ", sort @emails) . " subject=$eventName");
  my $errors = Foswiki::Func::sendEmail($text, 3);

  if ($errors) {
    Foswiki::Func::writeWarning("Failed to send mails: $errors");
    _writeError("Failed to send mails: $errors");
  } else {
    _writeDebug("... sent email successfully");
  }

  return $errors;
}

sub doNotifyUser {
  my ($this, $meta, $subscriber) = @_;

  return 0 if $subscriber eq $Foswiki::cfg{AdminUserWikiName};

  my $excludeList = Foswiki::Func::getPreferencesValue("COMMENTNOTIFYEXCLUDE");
  if (!defined($excludeList) && defined($meta)) {
    $excludeList = $meta->getPreference("COMMENTNOTIFYEXCLUDE");
  }
  return 1 unless $excludeList;

  return $excludeList =~ /\b$subscriber\b/ ? 0 : 1;
}

sub doNotifySelf {
  my ($this, $meta) = @_;

  my $doNotifySelf = Foswiki::Func::getPreferencesValue("COMMENT_NOTIFYSELF") // Foswiki::Func::getPreferencesValue("COMMENTNOTIFYSELF");
  if (!defined($doNotifySelf) && defined($meta)) {
    $doNotifySelf = $meta->getPreference("COMMENT_NOTIFYSELF") // $meta->getPreference("COMMENTNOTIFYSELF");
  }
  $doNotifySelf //= 'off';

  return Foswiki::Func::isTrue($doNotifySelf);
}

##############################################################################
sub getTemplate {
  my ($this, $name) = @_;

  $name ||= 'comments::notify';

  my $tmpl = $this->{_templates}{$name};

  unless (defined $tmpl) {
    unless ($this->{_doneLoadTemplate}) {
      Foswiki::Func::loadTemplate("metacomments");
      $this->{_doneLoadTemplate} = 1;
    }

    $tmpl = $this->{_templates}{$name} = Foswiki::Func::expandTemplate($name);
    _writeDebug("... woops, empty template for $name") unless $tmpl;
  }

  return $tmpl;
}

##############################################################################
sub beforeSaveHandler {
  my ($this, $web, $topic, $meta) = @_;

  my $commentSystem = Foswiki::Func::getPreferencesValue("COMMENTSYSTEM") // '';
  return unless $commentSystem =~ /^(metacomment)?$/;

  my $autoSubscribe = Foswiki::Func::getPreferencesValue("COMMENTAUTOSUBSCRIBE");
  return unless defined $autoSubscribe;

  $autoSubscribe =~ s/^\s+//;
  $autoSubscribe =~ s/\s+$//;
  return if $autoSubscribe =~ /^(off|no|none|0)$/;

  my %users = ();
  foreach my $fieldName (split(/\s*,\s*/, $autoSubscribe)) {

    my $items;

    if ($fieldName eq 'creator') {
      if (Foswiki::Func::topicExists($web, $topic)) {
        my ($date, $user) = Foswiki::Func::getRevisionInfo($web, $topic, 1);
        $items = $user;
      } else {
        $items = Foswiki::Func::getWikiName();
      }
    } else {
      my $field = $meta->get("FIELD", $fieldName);
      $items = $field->{value} if $field;
    }

    next unless $items;

    foreach my $item (split(/\s*,\s*/, $items)) {
      $item =~ s/^.*\.//;

      if (Foswiki::Func::isGroup($item)) {
        # gather users from group
        %users = map { $_ => 1 } Foswiki::Func::eachGroupMember($item)->all();
      } else {
        # just a single user
        $users{$item} = 1;
      }
    }
  }

  foreach my $name (keys %users) {
    my $cUID = Foswiki::Func::getCanonicalUserID($name);
    next unless $cUID; # does not exist

    my $wikiName = Foswiki::Func::getWikiName($cUID);
    next if $this->isUnsubscribed($meta, $wikiName); # unsubscribed explicitly
    next if $this->isSubscribed($meta, $wikiName); # already subscribed

    $this->subscribe($meta, $wikiName);
  }
}

##############################################################################
sub afterLikeHandler {
  my ($this, $web, $topic, $type, $id, $user, $likes, $dislikes) = @_;

  #print STDERR "called afterLikeHandler(web=$web,topic=$topic,type=$type,id=$id,user=$user,likes=$likes,dislikes=$dislikes)\n";

  return unless $type && $type eq 'COMMENT';

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  my $comment = $meta->get('COMMENT', $id);

  unless ($comment) {
    print STDERR "ERROR: afterLikeHandler - unknown comment $id\n";
    return;
  }

  $comment->{likes} = $likes;
  $comment->{dislikes} = $dislikes;

  $meta->save(ignorepermissions => 1, minor => 1) unless DRY;
}

##############################################################################
sub solrIndexTopicHandler {
  my ($this, $indexer, $doc, $web, $topic, $meta, $text) = @_;

  # delete all previous comments of this topic
  #$indexer->deleteByQuery("type:comment web:$web topic:$topic");

  my $commentDate = 0;
  my @comments = $meta->find('COMMENT');
  my @aclFields = $indexer->getAclFields($web, $topic, $meta);
  my $isModerated = $this->isModerated($web, $topic, $meta);

  foreach my $comment (@comments) {

    $indexer->log("Indexing comment $comment->{name} at $web.$topic");

    # set doc fields
    my $createDate = Foswiki::Func::formatTime($comment->{date}, 'iso', 'gmtime');
    my $createStr = Foswiki::Func::formatTime($comment->{date});
    my $cmtDate = $comment->{modified} || $comment->{date};
    my $date = Foswiki::Func::formatTime($cmtDate, 'iso', 'gmtime');
    my $dateStr = Foswiki::Func::formatTime($cmtDate);

    if ($cmtDate > $commentDate) {
      $commentDate = $cmtDate;
    }

    my $webtopic = "$web.$topic";
    $webtopic =~ s/\//./g;
    my $id = $webtopic . '#' . $comment->{name};
    my $url = $indexer->getScriptUrlPath($web, $topic, 'view', '#' => 'comment' . $comment->{name});

    my $text = $indexer->plainify($comment->{text});
    my $title = $this->titleOrText($comment->{title}, $text, 20);

    my $state = $comment->{state} || 'null';
    my $containerTitle = Foswiki::Func::getTopicTitle($web, $topic, undef, $meta);
    $containerTitle = $indexer->plainify($containerTitle);

    # reindex this comment
    my $commentDoc = $indexer->newDocument();
    $commentDoc->add_fields(
      'id' => $id,
      'name' => $comment->{name},
      'type' => 'comment',
      'form' => 'Comment',
      'web' => $web,
      'topic' => $topic,
      'webtopic' => $webtopic,
      'author' => $comment->{author},
      'author_title' => Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $comment->{author}),
      #      'author_url' => $comment->{author_url},
      'contributor' => $comment->{author},
      'date' => $date,
      'date_s' => $dateStr,
      'createdate' => $createDate,
      'createdate_s' => $createStr,
      'title' => $title,
      'text' => $text,
      'url' => $url,
      'state' => $state,
      'icon' => $indexer->mapToIconFileName("comment"),
      'container_id' => $web . '.' . $topic,
      'container_url' => Foswiki::Func::getViewUrl($web, $topic),
      'container_title' => $containerTitle,
      'field_TopicType_lst' => 'Comment',
    );

    my $contentLanguage = $indexer->getContentLanguage($web, $topic);
    if (defined $contentLanguage && $contentLanguage ne 'detect') {
      $commentDoc->add_fields(
        language => $contentLanguage,
        'text_' . $contentLanguage => $text,
      );
    }

    if ($comment->{read}) {
      foreach my $read (split(/\s*,\s*/, $comment->{read})) {
        $commentDoc->add_fields('read_lst' => $read);
      }
    }

    if ($isModerated && $state =~ /\bunapproved\b/) {
      $commentDoc->add_fields('access_granted' => '');
    } else {
      $commentDoc->add_fields(@aclFields) if @aclFields;
    }

    $doc->add_fields('contributor' => $comment->{author});

    # SMELL: why these two
    $doc->add_fields('catchall' => $title);
    $doc->add_fields('catchall' => $text);

    # add the document to the index
    try {
      $indexer->add($commentDoc);
    } catch Error::Simple with {
      my $e = shift;
      $indexer->log("ERROR: " . $e->{-text});
    };
  }

  my $numComments = scalar(@comments);

  $doc->add_fields(field_Comments_d => $numComments);
  $doc->add_fields(field_CommentDate_dt => Foswiki::Func::formatTime($commentDate, 'iso', 'gmtime'))
    if $commentDate;
}

##############################################################################
sub dbcacheIndexTopicHandler {
  my ($this, $db, $obj, $web, $topic, $meta, $text) = @_;

  my $maxDate = 0;
  foreach my $comment ($meta->find("COMMENT")) {
    my $cmtDate = $comment->{date};
    $maxDate = $cmtDate if $cmtDate > $maxDate;
  }

  $obj->set('commentdate', $maxDate) if $maxDate;
}

##############################################################################
sub getImageCore {
  my $this = shift;

  return unless Foswiki::Func::getContext()->{ImagePluginEnabled};
  require Foswiki::Plugins::ImagePlugin;
  return Foswiki::Plugins::ImagePlugin::getCore($this->{session});
}

##############################################################################
sub getHtmlConverter {
  my $this = shift;

  unless ($this->{htmlConverter}) {
    require Foswiki::Plugins::NatEditPlugin::HTML2TML;
    $this->{htmlConverter} =
      Foswiki::Plugins::NatEditPlugin::HTML2TML->new($this->{session});
  }

  return $this->{htmlConverter};
}

##############################################################################
sub titleOrText {
  my ($this, $title, $text, $trunc) = @_;

  my $result = $title // '';
  $result = substr($text, 0, $trunc) if $result eq '';
  $result = $this->{session}->renderer->TML2PlainText($result, undef, "showvar");
  $result .= " ..." if length($text) > length($result);

  return $result;
}

##############################################################################
sub _plainify {
  my $text = shift;

  return '' unless $text;

  $text =~ s/<!--.*?-->//gs; # remove all HTML comments
  $text =~ s/\&[a-z]+;/ /g; # remove entities
  $text =~ s/\[\[([^\]]*\]\[)(.*?)\]\]/$2/g;
  $text =~ s/<[^>]*>//g; # remove all HTML tags
  $text =~ s/[\[\]\*\|=_\&\<\>]/ /g; # remove Wiki formatting chars
  $text =~ s/^\-\-\-+\+*\s*\!*/ /gm; # remove heading formatting and hbar
  $text =~ s/^\s+//; # remove leading whitespace
  $text =~ s/\s+$//; # remove trailing whitespace
  $text =~ s/"/ /;
  $text =~ s/[\r\n]+/ /g; # remove linefeed

  return $text;
}

sub _deleteParam {
  my $key = shift;

  my $request = Foswiki::Func::getRequestObject();
  $request->delete($key);
}

sub _writeDebug {
  print STDERR "- MetaCommentPlugin - $_[0]\n" if TRACE;
}

sub _writeError {
  print STDERR "- MetaCommentPlugin - $_[0]\n";
}

sub _inlineError {
  return "<span class='foswikiAlert'>" . shift . "</span>";
}

1;
