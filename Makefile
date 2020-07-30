.DEFAULT_GOAL=help

NAME := $(shell basename $(shell pwd))
VERSION_STRING := $(shell git describe --tags)
DATE_STRING := $(shell date +"%Y-%m-%d")
BUILD_DIR := ./build

GRAPHVIZ_DOT_FILES := $(shell find ./diagrams -type f -name '*.dot')
GRAPHVIZ_SVG_FILES := $(GRAPHVIZ_DOT_FILES:dot=dot.svg)
GRAPHVIZ_PNG_FILES := $(GRAPHVIZ_DOT_FILES:dot=dot.png)
PLANTUML_FILES := $(shell find ./diagrams -type f -name '*.plantuml')
PLANTUML_SVG_FILES := $(PLANTUML_FILES:plantuml=plantuml.svg)
PLANTUML_PNG_FILES := $(PLANTUML_FILES:plantuml=plantuml.png)

ASCIIDOC_PARAMS := -r asciidoctor-diagram --attribute revnumber='$(VERSION_STRING)' --attribute revdate='$(DATE_STRING)'

EXTRA_ENV := JAVA_HOME=$(shell dirname $(shell dirname $(shell which java)))
EXTRA_ENV += KINDLEGEN=$(shell which kindlegen)

FILTER_ERRORS := grep -v -E "(font access|proper APIs|Set a breakpoint)" || true


.PHONY: test
test:
	@echo $(GRAPHVIZ_DOT_FILES)
	@echo $(GRAPHVIZ_SVG_FILES)

.PHONY: deps
deps:  ## Install dependencies
	bundle install

.PHONY: images
images:  ## Build all images
	find ./images -name '*.dot' | xargs -n 1 -

.PHONY: contributors
contributors: book/contributors.txt
	@echo "==> Generating contributors list"
	git shortlog -s | cut -f 2- | column -c 120 > book/contributors.txt

.PHONY: build
build: ## Build all docs
build: build-html build-epub build-mobi build-word build-pdf

.PHONY: build-html
build-html: ## Build html doc only
build-html: $(BUILD_DIR)/$(NAME).html
$(BUILD_DIR)/$(NAME).html: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) book/contributors.txt
	@echo "==> Converting to HTML at $@"
	$(EXTRA_ENV) bundle exec asciidoctor $(ASCIIDOC_PARAMS) -a data-uri --out-file $(BUILD_DIR)/$(NAME).html book.asc 2>&1 | $(FILTER_ERRORS)

.PHONY: build-epub
build-epub: ## Build epub doc only
build-epub: $(BUILD_DIR)/$(NAME).epub
$(BUILD_DIR)/$(NAME).epub: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) book/contributors.txt
	@echo "==> Converting to EPub at $@"
	$(EXTRA_ENV) bundle exec asciidoctor-epub3 $(ASCIIDOC_PARAMS) --out-file $(BUILD_DIR)/$(NAME).epub book.asc

.PHONY: build-mobi
build-mobi: ## Build mobi doc only
build-mobi: $(BUILD_DIR)/$(NAME)-kf8.epub
$(BUILD_DIR)/$(NAME)-kf8.epub: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) book/contributors.txt
	@echo "==> Converting to Mobi (kf8) at $@"
	$(EXTRA_ENV) bundle exec asciidoctor-epub3 $(ASCIIDOC_PARAMS) -a ebook-format=kf8 --out-file $(BUILD_DIR)/$(NAME).epub book.asc

.PHONY: build-word
build-word: ## Build word doc only
build-word: $(BUILD_DIR)/$(NAME).docx
$(BUILD_DIR)/$(NAME).docx: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) book/contributors.txt
	@echo "==> Converting to Word at $@"
	$(EXTRA_ENV) bundle exec asciidoctor  $(ASCIIDOC_PARAMS) --backend docbook --out-file - book.asc \
	  | pandoc --from docbook --to docx --output $(BUILD_DIR)/$(NAME).docx --highlight-style tango 2>&1 | $(FILTER_ERRORS)

.PHONY: build-pdf
build-pdf: ## Build pdf doc only
build-pdf: $(BUILD_DIR)/$(NAME).pdf
$(BUILD_DIR)/$(NAME).pdf: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) book/contributors.txt
	@echo "==> Converting to PDF at $@ (this one takes a while)"
	$(EXTRA_ENV) bundle exec asciidoctor-pdf $(ASCIIDOC_PARAMS) --out-file $(BUILD_DIR)/$(NAME).pdf book.asc 2>/dev/null

.PHONY: diagrams
diagrams:  ## Compile graphviz and plantuml source files in ./diagrams into SVGs
diagrams: graphviz plantuml

.PHONY: graphviz
graphviz: $(GRAPHVIZ_SVG_FILES) $(GRAPHVIZ_PNG_FILES)
%.dot.svg: %.dot
	dot -Tsvg "$<" > "$@"
%.dot.png: %.dot
	dot -Tpng "$<" > "$@"

.PHONY: plantuml
plantuml: $(PLANTUML_SVG_FILES) $(PLANTUML_PNG_FILES)
%.plantuml.svg: %.plantuml
	plantuml -tsvg "$<" 2>&1 | $(FILTER_ERRORS)
	mv $(basename $<).svg $(basename $<).plantuml.svg
%.plantuml.png: %.plantuml
	plantuml -tpng "$<" 2>&1 | $(FILTER_ERRORS)
	mv $(basename $<).png $(basename $<).plantuml.png

.PHONY: clean
clean:  ## Clean up all temporary files
	rm -rf build/*
	find ./diagrams -type f -name '*.svg' | xargs rm -f

.PHONY: help
help:  ## Print list of Makefile targets
	@# Taken from https://github.com/spf13/hugo/blob/master/Makefile
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  cut -d ":" -f1- | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
