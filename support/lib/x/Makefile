include $(LIB)/deps.make

all: dist

dist: build/dist.make dist/fonts.css
	@$(MAKE) -f build/dist.make
	cp -R $(SITE)/public/* dist/

preview: dist dist/preview/brat.sh dist/preview/index.html

.PHONY: all dist preview

.git/logs/HEAD:

build/dist.make: build/index $(LIBEXEC)/x-show-rules
	x--emit $@ x-show rules build/index

build/index: .git/logs/HEAD $(INDEX_DEPS)
	x--emit $@ x-show index

dist/fonts.css: $(SITE)/fonts.css $(LIBEXEC)/x-show-css
	x--emit $@ x-show css $(SITE)/fonts.css

dist/preview/brat.sh: brat.sh $(SCRIPT_DEPS)
	x--emit $@ x-show dist brat.sh preview

dist/preview/index.html: brat.sh $(PAGE_DEPS)
	x--emit $@ x-show page brat.sh preview
