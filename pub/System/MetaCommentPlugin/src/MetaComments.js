/*

Foswiki - The Free and Open Source Wiki, http://foswiki.org/

(c)opyright 2010-2024 Michael Daum http://michaeldaumconsulting.com

are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.

*/

"use strict";
(function($) {

  function _isMessageToSelf(message) {
    if (typeof(message.user) === 'undefined') {
      return true;
    }

    /*
    if (message.clientId === 'server' && message.user.wikiName === ec.user.wikiName) {
      return true;
    }
    */

    if (message.clientId === foswiki.eventClient.id) {
      return true;
    }

    return false;
  }

  // constructor
  function MetaComments(elem, opts) {
    var self = this,
        baseTopic = foswiki.getPreference("WEB")+"."+foswiki.getPreference("TOPIC");

    self.elem = $(elem);

    // gather options by merging opts
    self.opts = $.extend({
      baseTopic: baseTopic,
      topic: baseTopic
    }, self.elem.data(), opts);

    self.init();
  }

  // initializer *********************************************************
  MetaComments.prototype.init = function () {
    var self = this,
        hash = window.location.hash;
        
    self.container = self.elem.find(".cmtCommentsContainer");
    self.counter = self.elem.find(".cmtCounter");

    // scroll to comments hash
    if (hash.match(/^#comment\d+\.\d+$/)) {
      console.log("scrolling to comment");
      $.scrollTo(hash.replace(/\./, "\\."), 500, {
        margin:true,
        offset: -130, // SMELL: hard coded offset to mitigate sticky topbars
        easing: "easeInOutQuad"
      });
    }

    // add reply behaviour 
    self.elem.on("click", ".cmtReply", function() {
      var $comment = $(this).parent().find(".cmtComment:first"),
          opts = $.extend({
            expand: "comments::replier",
          }, $comment.data());

      self.loadDialog(opts);
      return false;
    });

    // add edit behaviour 
    self.elem.on("click", ".cmtEdit", function() {
      var $comment = $(this).parents(".cmtComment:first"),
          opts = $.extend({
            expand: "comments::updater",
          }, $comment.data());

      self.loadDialog(opts);
      return false;
    });

    // add delete behaviour 
    self.elem.on("click", ".cmtDelete", function() {
      var $comment = $(this).parents(".cmtComment:first"),
          opts = $.extend({
            expand: "comments::confirmdelete",
          }, $comment.data());

      self.loadDialog(opts);
      return false;
    });

    // add approve behaviour 
    self.elem.on("click", ".cmtApprove", function() {
      var $comment = $(this).parents(".cmtComment:first"),
          opts = $.extend({
            expand: "comments::confirmapprove",
          }, $comment.data());

      self.loadDialog(opts);
      return false;
    });

    // add "mark as read" 
    self.elem.on("click", ".cmtMark", function() {
      var $this = $(this), 
          msg = $this.data("message"),
          $comment = $this.parents(".cmtComment:first"),
          opts = $.extend({}, $comment.data());

      foswiki.jsonRpc({
        namespace: "MetaCommentPlugin",
        method: "markComment",
        params: {
          "topic": self.opts.topic,
          "comment_id": opts.commentId
        },
        beforeSubmit: function() {
          $.blockUI({ message:"<h1>"+msg+" ...</h1>"});
        },
        success: function() {
          $.unblockUI();
          if ($this.parent().is(".cmtMarkContainer")) {
            $this.parent().remove();
          } else {
            $this.remove();
          }
          $comment.parent().removeClass("cmtCommentNew cmtCommentUpdated");
          self.updateFavicon();
        },
        error: function(data) {
          $.unblockUI();
          $.pnotify({
            title: "Error",
            text: data.error.message,
            type:"error"
          });
        }
      });

      return false;
    });

    // add delete/approve/mark all behaviour 
    self.elem.find(".cmtDeleteAll, .cmtApproveAll, .cmtMarkAll, .cmtUnsubscribeAll").on("click", function() {
      var $this = $(this),
          opts = $.extend({
            name: $this.attr("href").replace(/^#/, "")
          }, $this.data());

      self.loadDialog(opts);
      return false;
    });

    // work around blinking twisties
    window.setTimeout(function() {
      self.elem.find(".twistyPlugin").show();
    }, 1);

    self.updateFavicon();

    // attaching to websocket events
    if (foswiki.eventClient) {
      foswiki.eventClient.bind("commentsave", function( message) {
        if (!_isMessageToSelf(message)) {
          //console.log("got commentsave event ... reloading",message);
          self.reload().done(function() {
            /*var id = "#comment"+message.data.comment_name.replace(/\./, '\\.');
            $(id).effect("highlight");
            */
          });
        }
      });
      foswiki.eventClient.bind("commentupdate", function(message) {
        if (!_isMessageToSelf(message)) {
          //console.log("got commentupdate event ... reloading",message);
          self.reload().done(function() {
            /*
            var id = "#comment"+message.data.comment_name.replace(/\./, '\\.');
            $(id).effect("highlight");
            */
          });
        }
      });
      foswiki.eventClient.bind("commentdelete", function(message) {
        if (!_isMessageToSelf(message)) {
          //console.log("got commentdelete event ... reloading",message);
          self.reload();
        }
      });
      foswiki.eventClient.bind("like", function(message) {
        if (!_isMessageToSelf(message) && message.data.metaType === "COMMENT") {
          //console.log("got like event ... reloading",message);
          self.reload().done(function() {
            var id = `#comment${message.data.metaId}`.replace(/\./, '\\.') + " .jqLikeButton";
            $(id).effect("highlight");
          });
        }
      });
    }
  };


  // update the favicon with the number of marks *************************
  MetaComments.prototype.updateFavicon = function() {
    var self = this, count;

    if (!foswiki.faviconManager) {
      return;
    }

    count = self.elem.find(".cmtMark").length;
    //console.log("found cmtMarks=",count);
    foswiki.faviconManager.setText(count ? count : "");
  };

  // function to load a dialogs ******************************************
  MetaComments.prototype.loadDialog = function(opts) {
    var self = this,
        dld = $.Deferred();

    opts.name = opts.name || self.opts.template;
    opts.topic = opts.topic || self.opts.topic;

    foswiki.loadTemplate(opts).done(function(data) {
      var $content = $(data.expand);

      $content.hide();
      $("body").append($content);
      $content.data("autoOpen", true).on("dialogopen", function() {
        dld.resolve($content);
       });
    });

    return dld.promise();
  };

  // reuload all comments ************************************************
  MetaComments.prototype.reload = function() {
    var self = this,
      dfd = $.Deferred();

    self.container.load(
      foswiki.getScriptUrl("rest", "RenderPlugin", "template", {
        "name": self.opts.template,
        "render": "on",
        "topic": self.opts.baseTopic,
        "commentstopic": self.opts.topic,
        "expand": "comments::list",
        "cachecontrol": 0
      }), function() {
        $.unblockUI();
        self.container.height('auto');
        dfd.resolve();

        self.counter.load(
          foswiki.getScriptUrl("rest", "RenderPlugin", "template", {
            "name": self.opts.template,
            "render": "on",
            "topic": self.opts.baseTopic,
            "commentstopic": self.opts.topic,
            "expand": "comments::topbar::title::count",
            "cachecontrol": 0
          })
        );
      });

    return dfd.promise();
  };

  $.fn.metaComments = function (opts) {
    return this.each(function () {
      if (!$.data(this, "MetaComments")) {
        $.data(this, "MetaComments", new MetaComments(this, opts));
      }
    });
  };

  // Enable declarative widget instanziation
  $(function() {
    $(".cmtComments").livequery(function() {
      $(this).metaComments();
    });
  });

})(jQuery);
