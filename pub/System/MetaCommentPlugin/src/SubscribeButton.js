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
