# Project settings
PROJECT := verchew
PACKAGE := verchew
REPOSITORY := jacebrowning/verchew

# Project paths
PACKAGES := $(PACKAGE) tests
CONFIG := $(wildcard *.py)
MODULES := $(wildcard $(PACKAGE)/*.py)

# Python settings
ifndef TRAVIS
	PYTHON_MAJOR ?= 2
	PYTHON_MINOR ?= 7
endif

# System paths
PLATFORM := $(shell python -c 'import sys; print(sys.platform)')
ifneq ($(findstring win32, $(PLATFORM)), )
	WINDOWS := true
	SYS_PYTHON_DIR := C:\\Python$(PYTHON_MAJOR)$(PYTHON_MINOR)
	SYS_PYTHON := $(SYS_PYTHON_DIR)\\python.exe
	SYS_VIRTUALENV := $(SYS_PYTHON_DIR)\\Scripts\\virtualenv.exe
	# https://bugs.launchpad.net/virtualenv/+bug/449537
	export TCL_LIBRARY=$(SYS_PYTHON_DIR)\\tcl\\tcl8.5
else
	ifneq ($(findstring darwin, $(PLATFORM)), )
		MAC := true
	else
		LINUX := true
	endif
	SYS_PYTHON := python$(PYTHON_MAJOR)
	ifdef PYTHON_MINOR
		SYS_PYTHON := $(SYS_PYTHON).$(PYTHON_MINOR)
	endif
	SYS_VIRTUALENV := virtualenv
endif

# Virtual environment paths
ifdef TRAVIS
	ENV := $(shell dirname $(shell dirname $(shell which $(SYS_PYTHON))))/
else
	ENV := env
endif
ifneq ($(findstring win32, $(PLATFORM)), )
	BIN := $(ENV)/Scripts
	ACTIVATE := $(BIN)/activate.bat
	OPEN := cmd /c start
else
	BIN := $(ENV)/bin
	ACTIVATE := . $(BIN)/activate
	ifneq ($(findstring cygwin, $(PLATFORM)), )
		OPEN := cygstart
	else
		OPEN := open
	endif
endif

# Virtual environment executables
PYTHON := $(BIN)/python
PIP := $(BIN)/pip
EASY_INSTALL := $(BIN)/easy_install
SNIFFER := $(BIN)/sniffer
HONCHO := $(ACTIVATE) && $(BIN)/honcho

# MAIN TASKS ###################################################################

.PHONY: all
all: install

.PHONY: ci
ci: check test ## Run all tasks that determine CI status

.PHONY: watch
watch: install .clean-test ## Continuously run all CI tasks when files chanage
	$(SNIFFER)

.PHONY: run ## Start the program
run: install
	$(PYTHON) $(PACKAGE)/__main__.py

.PHONY: demo ## Run the example
demo: install
	make doctor -C examples

# SYSTEM DEPENDENCIES ##########################################################

.PHONY: doctor
doctor:  ## Confirm system dependencies are available
	verchew/script.py

# PROJECT DEPENDENCIES #########################################################

DEPENDENCIES := $(ENV)/.dependencies-flag
DEV_DEPENDENCIES := $(ENV)/.dev-dependencies-flag

.PHONY: install
install: $(DEPENDENCIES) $(DEV_DEPENDENCIES) ## Install all project dependencies

$(DEPENDENCIES): setup.py requirements.txt $(PYTHON)
	$(PYTHON) setup.py develop
	@ touch $@  # flag to indicate dependencies are installed

$(DEV_DEPENDENCIES): requirements/*.txt $(PIP)
	$(PIP) install --upgrade pip setuptools
	$(PIP) install --upgrade -r requirements/ci.txt
	$(PIP) install --upgrade -r requirements/dev.txt
ifdef WINDOWS
	@ echo "Manually install pywin32: https://sourceforge.net/projects/pywin32/files/pywin32"
else ifdef MAC
	$(PIP) install --upgrade pync MacFSEvents
else ifdef LINUX
	$(PIP) install --upgrade pyinotify
endif
	@ touch $@  # flag to indicate dependencies are installed

$(PIP): $(PYTHON)

$(PYTHON):
	$(SYS_VIRTUALENV) --python $(SYS_PYTHON) $(ENV)

# CHECKS #######################################################################

PYLINT := $(BIN)/pylint
PYCODESTYLE := $(BIN)/pycodestyle
PYDOCSTYLE := $(BIN)/pydocstyle

.PHONY: check
check: pylint pycodestyle pydocstyle ## Run linters and static analysis

.PHONY: pylint
pylint: install ## Check for code issues
	$(PYLINT) $(PACKAGES) $(CONFIG) --rcfile=.pylint.ini

.PHONY: pycodestyle
pycodestyle: install ## Check for code conventions
	$(PYCODESTYLE) $(PACKAGES) $(CONFIG) --config=.pycodestyle.ini

.PHONY: pydocstyle
pydocstyle: install ## Check for docstring conventions
	$(PYDOCSTYLE) $(PACKAGES) $(CONFIG)

# TESTS ########################################################################

PYTEST := $(BIN)/py.test
COVERAGE := $(BIN)/coverage
COVERAGE_SPACE := $(BIN)/coverage.space

RANDOM_SEED ?= $(shell date +%s)

PYTEST_CORE_OPTS := --doctest-modules -ra -vv
PYTEST_COV_OPTS := --cov=$(PACKAGE) --no-cov-on-fail --cov-report=term-missing --cov-report=html
PYTEST_RANDOM_OPTS := --random --random-seed=$(RANDOM_SEED)

PYTEST_OPTS := $(PYTEST_CORE_OPTS) $(PYTEST_COV_OPTS) $(PYTEST_RANDOM_OPTS)
PYTEST_OPTS_FAILFAST := $(PYTEST_OPTS) --last-failed --exitfirst

FAILURES := .cache/v/cache/lastfailed
REPORTS ?= xmlreport

.PHONY: test
test: test-all

.PHONY: test-unit
test-unit: install ## Run the unit tests
	@- mv $(FAILURES) $(FAILURES).bak
	$(PYTEST) $(PYTEST_OPTS) $(PACKAGE) --junitxml=$(REPORTS)/unit.xml
	@- mv $(FAILURES).bak $(FAILURES)
	$(COVERAGE_SPACE) $(REPOSITORY) unit

.PHONY: test-int
test-int: install ## Run the integration tests
	@ if test -e $(FAILURES); then $(PYTEST) $(PYTEST_OPTS_FAILFAST) tests; fi
	@ rm -rf $(FAILURES)
	$(PYTEST) $(PYTEST_OPTS) tests --junitxml=$(REPORTS)/integration.xml
	$(COVERAGE_SPACE) $(REPOSITORY) integration

.PHONY: test-all
test-all: install ## Run all the tests
	@ if test -e $(FAILURES); then $(PYTEST) $(PYTEST_OPTS_FAILFAST) $(PACKAGES); fi
	@ rm -rf $(FAILURES)
	$(PYTEST) $(PYTEST_OPTS) $(PACKAGES) --junitxml=$(REPORTS)/overall.xml
	$(COVERAGE_SPACE) $(REPOSITORY) overall

.PHONY: read-coverage
read-coverage:
	$(OPEN) htmlcov/index.html

# DOCUMENTATION ################################################################

PYREVERSE := $(BIN)/pyreverse
PDOC := $(PYTHON) $(BIN)/pdoc
MKDOCS := $(BIN)/mkdocs

PDOC_INDEX := docs/apidocs/$(PACKAGE)/index.html
MKDOCS_INDEX := site/index.html

.PHONY: doc
doc: uml pdoc mkdocs ## Run documentation generators

.PHONY: uml
uml: install docs/*.png ## Generate UML diagrams for classes and packages
docs/*.png: $(MODULES)
	$(PYREVERSE) $(PACKAGE) -p $(PACKAGE) -a 1 -f ALL -o png --ignore tests
	- mv -f classes_$(PACKAGE).png docs/classes.png
	- mv -f packages_$(PACKAGE).png docs/packages.png

.PHONY: pdoc
pdoc: install $(PDOC_INDEX)  ## Generate API documentaiton with pdoc
$(PDOC_INDEX): $(MODULES)
	$(PDOC) --html --overwrite $(PACKAGE) --html-dir docs/apidocs
	@ touch $@

.PHONY: mkdocs
mkdocs: install $(MKDOCS_INDEX) ## Build the documentation site with mkdocs
$(MKDOCS_INDEX): mkdocs.yml docs/*.md
	ln -sf `realpath README.md --relative-to=docs` docs/index.md
	ln -sf `realpath CHANGELOG.md --relative-to=docs/about` docs/about/changelog.md
	ln -sf `realpath CONTRIBUTING.md --relative-to=docs/about` docs/about/contributing.md
	ln -sf `realpath LICENSE.md --relative-to=docs/about` docs/about/license.md
	$(MKDOCS) build --clean --strict

.PHONY: mkdocs-live
mkdocs-live: mkdocs ## Launch and continuously rebuild the mkdocs site
	eval "sleep 3; open http://127.0.0.1:8000" &
	$(MKDOCS) serve

# BUILD ########################################################################

PYINSTALLER := $(BIN)/pyinstaller
PYINSTALLER_MAKESPEC := $(BIN)/pyi-makespec

DIST_FILES := dist/*.tar.gz dist/*.whl
EXE_FILES := dist/$(PROJECT).*

.PHONY: dist
dist: install $(DIST_FILES)
$(DIST_FILES): $(MODULES) README.rst CHANGELOG.rst
	rm -f $(DIST_FILES)
	$(PYTHON) setup.py check --restructuredtext --strict --metadata
	$(PYTHON) setup.py sdist
	$(PYTHON) setup.py bdist_wheel
	cp $(PACKAGE)/script.py dist/$(PROJECT) && chmod a+x dist/$(PROJECT)

%.rst: %.md
	pandoc -f markdown_github -t rst -o $@ $<

.PHONY: exe
exe: install $(EXE_FILES)
$(EXE_FILES): $(MODULES) $(PROJECT).spec
	# For framework/shared support: https://github.com/yyuu/pyenv/wiki
	$(PYINSTALLER) $(PROJECT).spec --noconfirm --clean

$(PROJECT).spec:
	$(PYINSTALLER_MAKESPEC) $(PACKAGE)/__main__.py --onefile --windowed --name=$(PROJECT)

# RELEASE ######################################################################

TWINE := $(BIN)/twine

.PHONY: register
register: dist ## Register the project on PyPI
	@ echo NOTE: your project must be registered manually
	@ echo https://github.com/pypa/python-packaging-user-guide/issues/263
	# TODO: switch to twine when the above issue is resolved
	# $(TWINE) register dist/*.whl

.PHONY: upload
upload: .git-no-changes register ## Upload the current version to PyPI
	$(TWINE) upload dist/*.*
	$(OPEN) https://pypi.python.org/pypi/$(PROJECT)

.PHONY: .git-no-changes
.git-no-changes:
	@ if git diff --name-only --exit-code;        \
	then                                          \
		echo Git working copy is clean...;        \
	else                                          \
		echo ERROR: Git working copy is dirty!;   \
		echo Commit your changes and try again.;  \
		exit -1;                                  \
	fi;

# CLEANUP ######################################################################

.PHONY: clean
clean: .clean-dist .clean-test .clean-doc .clean-build ## Delete all generated and temporary files

.PHONY: clean-all
clean-all: clean .clean-env .clean-workspace

.PHONY: .clean-build
.clean-build:
	find $(PACKAGES) -name '*.pyc' -delete
	find $(PACKAGES) -name '__pycache__' -delete
	rm -rf *.egg-info

.PHONY: .clean-doc
.clean-doc:
	rm -rf README.rst docs/apidocs *.html docs/*.png site

.PHONY: .clean-test
.clean-test:
	rm -rf .cache .pytest .coverage htmlcov xmlreport

.PHONY: .clean-dist
.clean-dist:
	rm -rf *.spec dist build

.PHONY: .clean-env
.clean-env: clean
	rm -rf $(ENV)

.PHONY: .clean-workspace
.clean-workspace:
	rm -rf *.sublime-workspace

# HELP #########################################################################

.PHONY: help
help: all
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
