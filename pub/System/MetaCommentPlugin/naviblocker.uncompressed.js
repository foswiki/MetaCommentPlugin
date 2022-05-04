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
