/*

Foswiki - The Free and Open Source Wiki, http://foswiki.org/

(c)opyright 2010-2019 Michael Daum http://michaeldaumconsulting.com

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
jQuery(function($) {
  var doneLoadDialogs = false;

  $(".cmtComments:not(.cmtCommentsInited)").livequery(function() {
    var $this = $(this),
        $container = $this.parent(),
        defaults = {
          topic: foswiki.getPreference("TOPIC"),
          web: foswiki.getPreference("WEB"),
          updateMessage: "Updating comment",
          deleteMessage: "Deleting comment",
          approveMessage: "Approving comment",
          markingMessage: "Marking comment"
        },
        opts = $.extend({}, defaults, $this.data(), $this.metadata()),
        hash;

    /* function to reload all dialogs **************************************/
    function loadDialogs(callback) {
      if (!doneLoadDialogs) {
        doneLoadDialogs = true;
        $.get(
          foswiki.getPreference("SCRIPTURL") + "/rest/RenderPlugin/template", 
          {
            name:'metacomments',
            render:'on',
            topic:opts.web+"."+opts.topic,
            expand:'comments::dialogs'
          }, function(data) {
            $('body').append(data);
            window.setTimeout(callback, 100); // wait for livequeries ...
          }
        );
      } else {
        $(".cmtDialog form").resetForm();
        callback.call();
      }
    }

    /* function to reload all comments *************************************/
    function loadComments() {
      var url = foswiki.getPreference("SCRIPTURL") + 
          "/rest/RenderPlugin/template" +
          "?name=metacomments" + 
          ";render=on" +
          ";topic="+opts.web+"."+opts.topic +
          ";expand=metacomments";

      $container.load(url, function() {
        $.unblockUI();
        $container.height('auto');
      });
    }

    /* add hover ***********************************************************/
    $this.find(".cmtComment").hover(
      function() {
        var $this = $(this), $controls = $this.children(".cmtControls");
        $this.addClass("cmtHover");
        $controls.stop(true, true).fadeIn(500);
      },
      function() {
        var $this = $(this), $controls = $this.children(".cmtControls");
        $controls.stop(true, true).hide();
        $this.removeClass("cmtHover");
      }
    );

    /* ajaxify forms ********************************************************/
    $(".cmtJsonRpcForm").livequery(function() {
      var $form = $(this), msg = $form.data("message");

      $form.ajaxForm({
        beforeSerialize: function() {
          if (typeof(foswikiStrikeOne) !== 'undefined') {
            foswikiStrikeOne($form[0]);
          }
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
              text: "Error: "+data.error.message,
              type:"error"
            });
          } else {
            loadComments();
          }
        },
        error: function(xhr) {
          var data = $.parseJSON(xhr.responseText);
          $.unblockUI();
          $.pnotify({
            text: "Error: "+data.error.message,
            type:"error"
          });
        }
      });
    });

    /* add reply behaviour **************************************************/
    $this.find(".cmtReply").click(function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.metadata());

      loadDialogs(function() {
        $("#cmtReplyComment").dialog("option", "open", function() {
          var $this = $(this);
          $this.find(".cmtCommentIndex").text(commentOpts.index);
          $this.find("input[name='ref']").val(commentOpts.comment_id);
        }).dialog("open");
      });

      return false;
    });

    /* add edit behaviour ***************************************************/
    $this.find(".cmtEdit").click(function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.metadata());

      loadDialogs(function() {
        $.jsonRpc(foswiki.getPreference("SCRIPTURL")+"/jsonrpc", {
          namespace: "MetaCommentPlugin",
          method: "getComment",
          params: {
            "topic": opts.web+"."+opts.topic,
            "comment_id": commentOpts.comment_id
          },
          success: function(json) {
            $.unblockUI();
            $("#cmtUpdateComment").dialog("option", "open", function() {
              var $this = $(this);
              $this.find("input[name='comment_id']").val(commentOpts.comment_id);
              $this.find("input[name='index']").val(commentOpts.index);
              $this.find(".cmtCommentIndex").text(commentOpts.index);
              $this.find("input[name='title']").val(json.result.title);
              $this.find("textarea[name='text']").val(json.result.text);
            }).dialog("open");
          },
          error: function(data) {
            $.unblockUI();
            $.pnotify({
              text: "Error: "+data.error.message,
              type:"error"
            });
          }
        });
      });
      return false;
    });

    /* add delete behaviour *************************************************/
    $this.find(".cmtDelete").click(function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.metadata());

      loadDialogs(function() {
        $("#cmtConfirmDelete").dialog("option", "open", function() {
          var $this = $(this);
          $this.find("input[name='comment_id']").val(commentOpts.comment_id);
          $this.find("input[name='index']").val(commentOpts.index);
          $this.find(".cmtCommentNr").text(commentOpts.index);
          $this.find(".cmtAuthor").text(commentOpts.author);
          $this.find(".cmtDate").text(commentOpts.date);
        }).dialog("open");
      });

      return false;
    });

    /* add delete/approve/mark all behaviour ******************************************/
    $this.find(".cmtDeleteAll, .cmtApproveAll, .cmtMarkAll").click(function() {
      var id = $(this).attr("href");

      loadDialogs(function() {
        $(id).dialog("open");
      });

      return false;
    });

    /* add "mark as read" behaviour *************************************************/
    $this.find(".cmtMark").click(function() {
      var $this = $(this), 
          msg = $this.data("message"),
          $comment = $this.parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.metadata());

      $.jsonRpc(foswiki.getPreference("SCRIPTURL")+"/jsonrpc", {
        namespace: "MetaCommentPlugin",
        method: "markComment",
        params: {
          "topic": opts.web+"."+opts.topic,
          "comment_id": commentOpts.comment_id
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
        },
        error: function(data) {
          $.unblockUI();
          $.pnotify({
            text: "Error: "+data.error.message,
            type:"error"
          });
        }
      });

      return false;
    });

    /* add approve behaviour ************************************************/
    $this.find(".cmtApprove").click(function() {
      var $comment = $(this).parents(".cmtComment:first"),
          commentOpts = $.extend({}, $comment.metadata());

      loadDialogs(function() {
        $("#cmtConfirmApprove").dialog("option", "open", function() {
          var $this = $(this);
          $this.find("input[name='comment_id']").val(commentOpts.comment_id);
          $this.find("input[name='index']").val(commentOpts.index);
          $this.find(".cmtCommentNr").text(commentOpts.index);
          $this.find(".cmtAuthor").text(commentOpts.author);
          $this.find(".cmtDate").text(commentOpts.date);
        }).dialog("open");
      });
      return false;
    });

    // scroll to comments hash
    hash = window.location.hash;
    if (hash.match(/^#comment\d+\.\d+$/)) {
      $.scrollTo(hash.replace(/\./, "\\."), 500, {
        easing: "easeInOutQuad"
      });
    }

    // work around blinking twisties
    window.setTimeout(function() {
      $this.find(".twistyPlugin").show();
    }, 1);
  });
});
