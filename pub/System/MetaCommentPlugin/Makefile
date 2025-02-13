FOSWIKI_ROOT?=~/foswiki/trunk/core
TARGET=\
  build \
  build/pkg.js \
  build/metacomments.css \
  build/metacomments.pattern.css

PKG_SOURCES=\
  src/NaviBlocker.js \
  src/JsonRpcForm.js \
  src/SubscribeButton.js \
  src/MetaComments.js 

-include $(FOSWIKI_ROOT)/pub/System/JQueryPlugin/Makefile.include

clean: 
	rm -f build/* src/*jslint 

build:
	@mkdir build

build/pkg.uncompressed.js: $(PKG_SOURCES)
	@echo creating $@; $(CAT) $^ > $@;

