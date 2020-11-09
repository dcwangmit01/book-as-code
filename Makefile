SHELL := /bin/bash
.DEFAULT_GOAL=help

MAIN_ADOC := $(shell find . -maxdepth 1 -type f -name main.adoc -o -name README.adoc | LANG=POSIX sort -r | head -n 1)
NAME := $(shell head -n 1 $(MAIN_ADOC) \
	| tr '[:upper:]' '[:lower:]' | tr '[:punct:]' '_' | tr '[:space:]' '_' | tr -s '_' \
	| sed 's@^_@@g; s@_$$@@g;' | tr '_' '-' \
	| awk '{$$1=$$1;print}' )

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
ASCIIDOC_FILES := $(shell find * -type f -name '*.adoc')
ASCIIDOC_PARAMS := -a data-uri -a allow-uri-read \
    -r $(ASCIIDOC_CMD)-diagram -r $(ASCIIDOC_CMD)-mathematical \
    --attribute revnumber='$(VERSION_STRING)' --attribute revdate='$(DATE_STRING)'

CONFLUENCE_SITE_URL := https://<CONFLUENCE_SERVER>/conf
CONFLUENCE_SPACEKEY := <CONFLUENCE_SPACE_KEY>
CONFLUENCE_TITLE := $(shell head -n 1 $(MAIN_ADOC) | sed 's@=@@g' | awk '{$$1=$$1;print}')

# Filter PlantUML/OpenJdk font errors until this is fixed:
#   https://github.com/plantuml/plantuml/issues/305
FILTER_ERRORS := 2>&1 | (grep -v CoreText || true)

GIT_MODULE_DIR=$(shell git rev-parse --show-toplevel)
CURRENT_PWD=$(shell pwd)
ifeq ($(GIT_MODULE_DIR),$(CURRENT_PWD))
	INSIDE_CONTAINER_DIRECTORY=.
else
	INSIDE_CONTAINER_DIRECTORY=$(shell echo $(CURRENT_PWD) | sed 's@$(GIT_MODULE_DIR)/@@g')
endif

WINDOWS_COMPATIBILITY_ENV_VARS = MSYS_NO_PATHCONV=1
DOCKER_RUN_COMMAND = \
  $(WINDOWS_COMPATIBILITY_ENV_VARS) \
  docker run -it --rm -v $(GIT_MODULE_DIR):/documents \
    --env CONFLUENCE_USERNAME="$${CONFLUENCE_USERNAME}" \
    --env CONFLUENCE_PASSWORD="$${CONFLUENCE_PASSWORD}" \
    --entrypoint "/bin/bash" \
    dcwangmit01/docker-asciidoctor-pandoc:v0.3.0 \
    -c 'cd $(INSIDE_CONTAINER_DIRECTORY) && VERSION_STRING=$(VERSION_STRING) make _$@'
ifeq ($(NO_DOCKER),true)
	DOCKER_RUN_COMMAND = make _$@
endif

#######################################
# Docker-Based Build Targets

all: check ## Makes all documentation formats
	$(DOCKER_RUN_COMMAND)

html: check ## Builds an HTML doc
	$(DOCKER_RUN_COMMAND)

xhtml: check ## Builds an XHTML doc
	$(DOCKER_RUN_COMMAND)

epub: check  ## Builds an EPUB doc
	$(DOCKER_RUN_COMMAND)

mobi: check  ## Builds a Mobi/Kindle doc
	$(DOCKER_RUN_COMMAND)

docx: check  ## Builds a Word Doc
	$(DOCKER_RUN_COMMAND)

pdf: check  ## Builds a PDF
	$(DOCKER_RUN_COMMAND)

publish-confluence: check  ## Builds and Publishes Confluence Doc
	$(DOCKER_RUN_COMMAND)

#######################################
# Local Private Build Targets

_all: _html _pdf _docx _xhtml _epub # _mobi

.PHONY: _html
_html: $(BUILD_DIR)/$(NAME).html

.PHONY: _xhtml
_xhtml: $(BUILD_DIR)/$(NAME).xhtml

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
develop: html
	if [ ! -f /.dockerenv ]; then \
	  open $(BUILD_DIR)/$(NAME).html; \
	fi
	while true; do make html ; sleep 5; done

$(BUILD_DIR)/$(NAME).html: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to HTML at $@"
	$(ASCIIDOC_CMD) \
	  $(ASCIIDOC_PARAMS) \
	  --backend html5 \
	  --out-file $(BUILD_DIR)/$(NAME).html \
	  $(MAIN_ADOC) \
	  $(FILTER_ERRORS)

$(BUILD_DIR)/$(NAME).xhtml: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to XHTML at $@"
	$(ASCIIDOC_CMD) \
	  $(ASCIIDOC_PARAMS) \
	  --backend xhtml \
	  --out-file $(BUILD_DIR)/$(NAME).xhtml \
	  $(MAIN_ADOC) \
	  $(FILTER_ERRORS)

$(BUILD_DIR)/$(NAME).epub: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to EPub at $@"
	$(ASCIIDOC_CMD)-epub3 \
	  $(ASCIIDOC_PARAMS) \
	  --out-file $(BUILD_DIR)/$(NAME).epub \
	  $(MAIN_ADOC) \
	  $(FILTER_ERRORS)

$(BUILD_DIR)/$(NAME)-kf8.epub: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to Mobi (kf8) at $@"
	KINDLEGEN=$(shell which kindlegen) \
	  $(ASCIIDOC_CMD)-epub3 \
	  $(ASCIIDOC_PARAMS) \
	  -a ebook-format=kf8 \
	  --out-file $(BUILD_DIR)/$(NAME).epub \
	  $(MAIN_ADOC) \
	  $(FILTER_ERRORS)

$(BUILD_DIR)/$(NAME).docx: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to Word at $@"
	$(EXTRA_ENV) \
	  $(ASCIIDOC_CMD) \
	  $(ASCIIDOC_PARAMS) \
	  --backend docbook \
	  --out-file $(BUILD_DIR)/$(NAME).docbook \
	  $(MAIN_ADOC)
	 (cd $(BUILD_DIR) && pandoc --from docbook --to docx \
	    --output $(NAME).docx \
	    --highlight-style tango \
	    $(NAME).docbook)

$(BUILD_DIR)/$(NAME).pdf: $(GRAPHVIZ_SVG_FILES) $(PLANTUML_SVG_FILES) $(ASCIIDOC_FILES)
	@echo "==> Converting to PDF at $@ (this one takes a while)"
	$(ASCIIDOC_CMD)-pdf \
	  $(ASCIIDOC_PARAMS) -a allow-uri-read \
	  --out-file $(BUILD_DIR)/$(NAME).pdf \
	  $(MAIN_ADOC) \
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

_publish-confluence: check $(BUILD_DIR)/$(NAME).xhtml
	@# Verify that we have what we need to push to Confluence
	@if [[ -z "${CONFLUENCE_USERNAME}" ]]; then \
	  echo "ERROR: CONFLUENCE_USERNAME env var must be set: export CONFLUENCE_USERNAME=<VALUE>"; exit 1; fi
	@if [[ -z "${CONFLUENCE_PASSWORD}" ]]; then \
	  echo "ERROR: CONFLUENCE_PASSWORD env var must be set: export CONFLUENCE_PASSWORD=<VALUE>"; exit 1; fi

	@# Create the document to be uploaded to confluence
	@echo '<ac:structured-macro ac:name = "html"><ac:plain-text-body><![CDATA[' > $(BUILD_DIR)/$(NAME).confluence
	@cat $(BUILD_DIR)/$(NAME).xhtml >> $(BUILD_DIR)/$(NAME).confluence
	@echo >> $(BUILD_DIR)/$(NAME).confluence
	@echo "]]></ac:plain-text-body></ac:structured-macro>" >> $(BUILD_DIR)/$(NAME).confluence

	@# Do the upload
	confluence-cli \
	  -u "$${CONFLUENCE_USERNAME}" \
	  -p "$${CONFLUENCE_PASSWORD}" \
	  -s "$(CONFLUENCE_SITE_URL)" \
	  -t "$(CONFLUENCE_TITLE)" \
	  -k "$(CONFLUENCE_SPACEKEY)" \
	  -f $(BUILD_DIR)/$(NAME).confluence \
	  add-or-update-page

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
	@grep --with-filename -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  cut -d ":" -f2- | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' | sort
