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
