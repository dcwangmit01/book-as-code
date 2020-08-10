SHELL := /bin/bash

.DEFAULT_GOAL=help

NAME := $(shell basename $(shell pwd))
VERSION_STRING := $(if $(VERSION_STRING),$(VERSION_STRING),$(shell git describe --tags))
DATE_STRING := $(shell date +"%Y-%m-%d")
DIST_DIR := ./dist
BUILD_DIR := ./build
DIAGRAMS_DIR := ./diagrams

TMP := $(shell mkdir -p $(BUILD_DIR) $(DIAGRAMS_DIR))

GRAPHVIZ_DOT_FILES := $(shell find $(DIAGRAMS_DIR) -type f -name '*.dot')
GRAPHVIZ_SVG_FILES := $(GRAPHVIZ_DOT_FILES:dot=dot.svg)
GRAPHVIZ_PNG_FILES := $(GRAPHVIZ_DOT_FILES:dot=dot.png)
PLANTUML_FILES := $(shell find $(DIAGRAMS_DIR) -type f -name '*.plantuml')
PLANTUML_SVG_FILES := $(PLANTUML_FILES:plantuml=plantuml.svg)
PLANTUML_PNG_FILES := $(PLANTUML_FILES:plantuml=plantuml.png)
PLANTUML_JAR := $(shell find /usr -type f -name plantuml.jar -print -quit 2>/dev/null)
PLANTUML_CMD := java -Djava.awt.headless=true -jar $(PLANTUML_JAR)

ASCIIDOC_CMD := asciidoctor
ASCIIDOC_FILES := $(shell find * -type f -name '*.asc')
ASCIIDOC_PARAMS := -a data-uri -a allow-uri-read \
    -r $(ASCIIDOC_CMD)-diagram \
    --attribute revnumber='$(VERSION_STRING)' --attribute revdate='$(DATE_STRING)'

# Filter PlantUML/OpenJdk font errors until this is fixed:
#   https://github.com/plantuml/plantuml/issues/305
FILTER_ERRORS := 2>&1 | (grep -v CoreText || true)

WINDOWS_COMPATIBILITY_ENV_VARS = MSYS_NO_PATHCONV=1
DOCKER_RUN_COMMAND = \
  $(WINDOWS_COMPATIBILITY_ENV_VARS) \
  docker run -it --rm -v $(shell pwd):/$(NAME) \
    --entrypoint "/bin/bash" \
    dcwangmit01/docker-asciidoctor-pandoc \
    -c \
      'cd /$(NAME) && VERSION_STRING=$(VERSION_STRING) make _$@'
ifeq ($(NO_DOCKER),true)
	DOCKER_RUN_COMMAND = make _$@
endif

#######################################
# Docker-Based Build Targets

all: check ## Makes all documentation formats
	$(DOCKER_RUN_COMMAND)

html: check ## Builds an HTML doc
	$(DOCKER_RUN_COMMAND)

epub: check  ## Builds an EPUB doc
	$(DOCKER_RUN_COMMAND)

mobi: check  ## Builds a Mobi/Kindle doc
	$(DOCKER_RUN_COMMAND)

docx: check  ## Builds a Word Doc
	$(DOCKER_RUN_COMMAND)

pdf: check  ## Builds a PDF
	$(DOCKER_RUN_COMMAND)

#######################################
# Local Private Build Targets

_all: _html _epub _mobi _docx _pdf

.PHONY: _html
_html: $(BUILD_DIR)/$(NAME).html

.PHONY: _epub
_epub: $(BUILD_DIR)/$(NAME).epub

.PHONY: _mobi
_mobi: $(BUILD_DIR)/$(NAME)-kf8.epub

.PHONY: _docx
_docx: $(BUILD_DIR)/$(NAME).docx

.PHONY: _pdf
_pdf: $(BUILD_DIR)/$(NAME).pdf

#######################################
# Core Logic

.PHONY: images
images:  ## Build all images
	find ./images -name '*.dot' | xargs -n 1 -

.PHONY: contributors
contributors:  ## Build contributes.txt file
	@echo "==> Generating contributors list"
	git shortlog -s . | cut -f 2- > contributors.txt

.PHONY: develop
develop: ## Loop the html build and open a webpage with automatic reload
develop: _html
	if [ ! -f /.dockerenv ]; then \
	  open $(BUILD_DIR)/$(NAME).html; \
	fi
	while true; do make _html ; sleep 5; done

$(BUILD_DIR)/$(NAME).html: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to HTML at $@"
	$(ASCIIDOC_CMD) \
	  $(ASCIIDOC_PARAMS) \
	  --out-file $(BUILD_DIR)/$(NAME).html \
	  main.asc \
	  $(FILTER_ERRORS)

$(BUILD_DIR)/$(NAME).epub: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to EPub at $@"
	$(ASCIIDOC_CMD)-epub3 \
	  $(ASCIIDOC_PARAMS) \
	  --out-file $(BUILD_DIR)/$(NAME).epub \
	  main.asc \
	  $(FILTER_ERRORS)

$(BUILD_DIR)/$(NAME)-kf8.epub: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to Mobi (kf8) at $@"
	KINDLEGEN=$(shell which kindlegen) \
	  $(ASCIIDOC_CMD)-epub3 \
	  $(ASCIIDOC_PARAMS) \
	  -a ebook-format=kf8 \
	  --out-file $(BUILD_DIR)/$(NAME).epub \
	  main.asc \
	  $(FILTER_ERRORS)

$(BUILD_DIR)/$(NAME).docx: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to Word at $@"
	$(EXTRA_ENV) \
	  $(ASCIIDOC_CMD) \
	  $(ASCIIDOC_PARAMS) \
	  --backend docbook \
	  --out-file $(BUILD_DIR)/$(NAME).docbook \
	  main.asc
	 (cd $(BUILD_DIR) && pandoc --from docbook --to docx \
	    --output $(NAME).docx \
	    --highlight-style tango \
	    $(NAME).docbook)

$(BUILD_DIR)/$(NAME).pdf: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to PDF at $@ (this one takes a while)"
	$(ASCIIDOC_CMD)-pdf \
	  $(ASCIIDOC_PARAMS) -a allow-uri-read \
	  --out-file $(BUILD_DIR)/$(NAME).pdf \
	  main.asc \
	  $(FILTER_ERRORS)

.PHONY: diagrams
diagrams:  ## Compile graphviz and plantuml source files in $(DIAGRAMS_DIR) into SVGs
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
	$(PLANTUML_CMD) -tsvg "$<" $(FILTER_ERRORS)
	mv $(basename $<).svg $(basename $<).plantuml.svg
%.plantuml.png: %.plantuml
	$(PLANTUML_CMD) -tpng "$<" $(FILTER_ERRORS)
	mv $(basename $<).png $(basename $<).plantuml.png

.PHONY: check
check:
ifneq ($(NO_DOCKER),true)
	@if ! which docker 2>&1 > /dev/null; then \
	  echo "ERROR: Docker must be installed as a dependency"; \
	fi
endif

.PHONY: clean
clean:  ## Clean up all temporary files
	mkdir -p $(BUILD_DIR) && rm -rf $(BUILD_DIR)/*
	mkdir -p $(DIST_DIR) && rm -rf $(DIST_DIR)/*
	find $(DIAGRAMS_DIR) -type f -name '*.svg' | xargs rm -f

.PHONY: help
help:  ## Print list of Makefile targets
	@# Taken from https://github.com/spf13/hugo/blob/master/Makefile
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  cut -d ":" -f1- | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
