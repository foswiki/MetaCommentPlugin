/*

Foswiki - The Free and Open Source Wiki, http://foswiki.org/

(c)opyright 2010-2022 Michael Daum http://michaeldaumconsulting.com

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

  //globals
  var doneLoadDialogs = false,
  globalMetaComments;

  // constructor
  function MetaComments(elem, opts) {
    var self = this,
        baseTopic = foswiki.getPreference("WEB")+"."+foswiki.getPreference("TOPIC");

    globalMetaComments = self;

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
        
    self.container = self.elem.parent();

    // scroll to comments hash
    if (hash.match(/^#comment\d+\.\d+$/)) {
      $.scrollTo(hash.replace(/\./, "\\."), 500, {
        easing: "easeInOutQuad"
      });
    }

    // add reply behaviour 
    self.elem.find(".cmtReply").on("click", function() {
      var $comment = $(this).parent().find(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.data());

      self.loadDialogs().then(function() {
        $("#cmtReplyComment").dialog("option", "open", function() {
          var $this = $(this);
          $this.find("input[name='topic']").val(self.opts.topic);
          $this.find(".cmtCommentIndex").text(commentOpts.index);
          $this.find("input[name='ref']").val(commentOpts.commentId);
          $this.find("form").trigger("refresh");
        }).dialog("open");
      });

      return false;
    });

    // add edit behaviour 
    self.elem.find(".cmtEdit").on("click", function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.data());

      self.loadDialogs().then(function() {
        $.jsonRpc(foswiki.getPreference("SCRIPTURL")+"/jsonrpc", {
          namespace: "MetaCommentPlugin",
          method: "getComment",
          params: {
            "topic": self.opts.topic,
            "comment_id": commentOpts.commentId
          },
          success: function(json) {
            $.unblockUI();
            $("#cmtUpdateComment").dialog("option", "open", function() {
              var $this = $(this);
              $this.find("input[name='topic']").val(self.opts.topic);
              $this.find("input[name='comment_id']").val(commentOpts.commentId);
              $this.find("input[name='index']").val(commentOpts.index);
              $this.find(".cmtCommentIndex").text(commentOpts.index);
              $this.find("input[name='title']").val(json.result.title);
              $this.find("textarea[name='text']").val(json.result.text);
              $this.find("form").trigger("refresh");
              if ((""+commentOpts.index).match(/^\d+$/)) {
                $this.find(".cmtTitleStep").show();
              } else {
                $this.find(".cmtTitleStep").hide();
              }
            }).dialog("open");
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
      });
      return false;
    });

    // add delete behaviour 
    self.elem.find(".cmtDelete").on("click", function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.data());

      self.loadDialogs().then(function() {
        $("#cmtConfirmDelete").dialog("option", "open", function() {
          var $this = $(this);
          $this.find("input[name='topic']").val(self.opts.topic);
          $this.find("input[name='comment_id']").val(commentOpts.commentId);
          $this.find("input[name='index']").val(commentOpts.index);
          $this.find(".cmtCommentNr").text(commentOpts.index);
          $this.find(".cmtAuthor").text(commentOpts.author);
          $this.find(".cmtDate").text(commentOpts.date);
        }).dialog("open");
      });

      return false;
    });

    // add delete/approve/mark all behaviour 
    self.elem.find(".cmtDeleteAll, .cmtApproveAll, .cmtMarkAll").on("click", function() {
      var id = $(this).attr("href");

      self.loadDialogs().then(function() {
        $(id).dialog("option", "open", function() {
          var $this = $(this);
          $this.find("input[name='topic']").val(self.opts.topic);
        }).dialog("open");
      });

      return false;
    });

    // add "mark as read" 
    self.elem.find(".cmtMark").on("click", function() {
      var $this = $(this), 
          msg = $this.data("message"),
          $comment = $this.parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.data());

      $.jsonRpc(foswiki.getPreference("SCRIPTURL")+"/jsonrpc", {
        namespace: "MetaCommentPlugin",
        method: "markComment",
        params: {
          "topic": self.opts.topic,
          "comment_id": commentOpts.commentId
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

    // add approve behaviour 
    self.elem.find(".cmtApprove").on("click", function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.data());

      self.loadDialogs().then(function() {
        $("#cmtConfirmApprove").dialog("option", "open", function() {
          var $this = $(this);
          $this.find("input[name='topic']").val(self.opts.topic);
          $this.find("input[name='comment_id']").val(commentOpts.commentId);
          $this.find("input[name='index']").val(commentOpts.index);
          $this.find(".cmtCommentNr").text(commentOpts.index);
          $this.find(".cmtAuthor").text(commentOpts.author);
          $this.find(".cmtDate").text(commentOpts.date);
        }).dialog("open");
      });

      return false;
    });

    // work around blinking twisties
    window.setTimeout(function() {
      self.elem.find(".twistyPlugin").show();
    }, 1);

    self.updateFavicon();
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

  // function to reload all dialogs **************************************
  MetaComments.prototype.loadDialogs = function() {
    var self = this,
        dld = $.Deferred();

    if (!doneLoadDialogs) {
      doneLoadDialogs = true;

      $.get(
        foswiki.getScriptUrl("rest", "RenderPlugin", "template", {
          name:'metacomments',
          render:'on',
          topic: self.opts.baseTopic,
          expand:'comments::dialogs'
        }), function(data) {
          $('body').append(data);

          window.setTimeout(function() {
            dld.resolve();
          }, 100); // wait for livequeries ...
        }
      );

    } else {
      $(".cmtDialog form").resetForm();
      dld.resolve();
    }

    return dld;
  };

  // reuload all comments ************************************************
  MetaComments.prototype.reload = function() {
    var self = this;

    var url = foswiki.getScriptUrl("rest", "RenderPlugin", "template", {
        "name": "metacomments",
        "render": "on",
        "topic": self.opts.baseTopic,
        "commentstopic": self.opts.topic,
        "expand": "metacomments",
        "cachecontrol": 0
    });

    self.container.load(url, function() {
      $.unblockUI();
      self.container.height('auto');
    });
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

  /* ajaxify forms ********************************************************/
  $(".cmtJsonRpcForm").livequery(function() {
    var $form = $(this), 
        msg = $form.data("message");

    $form.on("refresh", function() {
      $form.find(".natedit").each(function() {
        var editor = $(this).data("natedit"),
            val = $(this).val();
        if (editor) {
          editor.setValue(val);
        }
      });
    });

    $form.ajaxForm({
      beforeSerialize: function() {
        if (typeof(foswikiStrikeOne) !== 'undefined') {
          foswikiStrikeOne($form[0]);
        }
        $form.find(".natedit").each(function() {
          var editor = $(this).data("natedit");
          if (editor) {
            editor.beforeSubmit();
          }
        });
      },
      beforeSubmit: function() {
        if ($form.is(".cmtModalForm")) {
          $form.parent().dialog("close");
        }
        $.blockUI({
          message:"<h1>"+msg+" ...</h1>",
          fadeIn: 0,
          fadeOut: 0
        });
      },
      success: function(data) {
        if(data.error) {
          $.unblockUI();
          $.pnotify({
            title: "Error",
            text: data.error.message,
            type:"error"
          });
        } else {
          if (globalMetaComments) {
            globalMetaComments.reload();
          }
        }
      },
      error: function(xhr) {
        var data = $.parseJSON(xhr.responseText);
        $.unblockUI();
        $.pnotify({
          title: "Error",
          text: data.error.message,
          type:"error"
        });
      }
    });
  });

})(jQuery);
