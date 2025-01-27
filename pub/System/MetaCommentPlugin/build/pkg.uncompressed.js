/*

Foswiki - The Free and Open Source Wiki, http://foswiki.org/

(c)opyright 2021 Michael Daum http://michaeldaumconsulting.com

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
/*global foswikiStrikeOne:false */
"use strict";
(function($) {

  var defaults = {
    "formElements": "textarea, input[type='text'], select"
  };

  function NaviBlocker(elem, opts) {
    var self = this;
    self.elem = $(elem);

    self.opts = $.extend({}, defaults, opts);
    
    if (self.elem.is("form")) {
      self.init();
    } else {
      console.error("NaviBlocker: element is not a form: ",elem);
    }
  }

  NaviBlocker.prototype.init = function () {
    var self = this;

    self.initialForm = self.serialize();

    self.elem.on("refresh", function() {
      //console.log("got refresh event");
      self.initialForm = self.serialize();
    });

    $(window).on("beforeunload", function(e) {
      //console.log("got beforeunload event");

      if (self.hasChanged()) {
        //console.log("blocking navigation")
        //console.log("initial=",self.initialForm);
        //console.log("current=",self.serialize());
        e.preventDefault();
        return "Are you sure?"; // dummy text
      }
      return;
    });

  };

  NaviBlocker.prototype.hasChanged = function() {
    var self = this;

    //console.log("testing changes in form",self.elem);
    if (!document.body.contains(self.elem[0])) {
      //console.log("element not part of the document anymore...skipping blocker");
      return false;
    } else {
      return (self.elem.is(":visible") && self.initialForm !== self.serialize()) ? true : false;
    }
  };

  NaviBlocker.prototype.serialize = function() {
    var self = this,
        string = self.elem.find(self.opts.formElements).fieldSerialize();

    //console.log("serialized string=",string,"for form=",self.elem[0]);

    return string;
  };

  $.fn.naviBlocker = function (opts) {
    return this.each(function () {
      if (!$.data(this, "NaviBlocker")) {
        $.data(this, "NaviBlocker", new NaviBlocker(this, opts));
      }
    });
  };

  $(function() {
    $(".naviBlocker").livequery(function() {
      $(this).naviBlocker();
    });
  });

})(jQuery);
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

  /* ajaxify forms ********************************************************/
  $(".cmtJsonRpcForm").livequery(function() {
    var $form = $(this), 
        msg = $form.data("message");

    if (foswiki.eventClient) {
      $("<input />").attr({
        type: "hidden",
        name: "clientId",
        value: foswiki.eventClient.id
      }).prependTo($form);
    }

    $form.on("submit", function() {
      var editor = $form.find(".natedit").data("natedit"),
          dialog;
      //console.log("submit comment",editor);

      function doit() {
        if ($form.is(".cmtModalForm")) {
          dialog = $form.parent();
        }
        $form.ajaxSubmit({
          beforeSubmit: function() {
            if (dialog) {
              dialog.dialog("close");
            }
            $.blockUI({
              message:"<h1>"+msg+" ...</h1>",
              fadeIn: 0,
              fadeOut: 0
            });
          },
          success: function(data) {
            if (dialog) {
              dialog.dialog("destroy");
              dialog.remove();
            }
            $.unblockUI();
            if(data.error) {
              $.pnotify({
                title: "Error",
                text: data.error.message,
                type:"error"
              });
            } else {
              $(".cmtComments").each(function() {
                var metaComments = $(this).data("MetaComments")
                if (metaComments) {
                  metaComments.elem.find("form[name=addCommentForm]").trigger("reset");
                  metaComments.reload();
                }
              });
            }
          },
          error: function(xhr) {
            var data = $.parseJSON(xhr.responseText);
            if (dialog) {
              dialog.dialog("destroy");
              dialog.remove();
            }
            $.unblockUI();
            $.pnotify({
              title: "Error",
              text: data.error.message,
              type:"error"
            });
          }
        });
      }

      if (editor && $.NatEditor.version) {
        editor.purify();
        editor.beforeSubmit().then(doit);
      } else {
        doit();
      }

      return false;
    });
  });

})(jQuery);
/*

Foswiki - The Free and Open Source Wiki, http://foswiki.org/

(c)opyright 2010-2023 Michael Daum http://michaeldaumconsulting.com

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

  /* subscribe / unsubscribe buttons */
  $(document).on("click", ".cmtSubscribeButton", function() {
    var $this = $(this), 
        opts = $.extend({
            subscribed: false,
            topic: foswiki.getPreference("WEB") + "." + foswiki.getPreference('TOPIC'),
          }, $this.data()
        ),
        subElem = $this.children(".cmtSubscribe"),
        unsubElem = $this.children(".cmtUnsubscribe");

    if (opts.subscribed) {
      subElem.hide();
      unsubElem.show();
    } else {
      subElem.show();
      unsubElem.hide();
    }


    $.blockUI();

    foswiki.jsonRpc({
      namespace: "MetaCommentPlugin",
      method: opts.subscribed?"unsubscribe":"subscribe",
      params: {
        topic: opts.topic
      },
    }).done(function(response) {
      $.unblockUI();
      $.pnotify({
         title: "Success",
         text: response.result,
         type: 'success'
      });
      if (opts.subscribed) {
        subElem.show();
        unsubElem.hide();
        $this.data("subscribed", false);
      } else {
        subElem.hide();
        unsubElem.show();
        $this.data("subscribed", true);
      }
    }).fail(function(xhr) {
      $.unblockUI();
      $.pnotify({
         title: "Error",
         text: xhr.responseJSON.error.message,
         type: 'error'
      });
    });

    return false;
  });

})(jQuery);
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
