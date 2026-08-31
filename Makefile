CXX      := clang++
CXXFLAGS := -std=c++17 -Wall -Wextra -Wno-deprecated-register -Wno-unused-function

# Platform-specific tool and library paths
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    BREW_PREFIX := $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)
    FLEX        ?= $(BREW_PREFIX)/opt/flex/bin/flex
    BISON       ?= $(BREW_PREFIX)/opt/bison/bin/bison
    ODBC_CFLAGS ?= -I$(BREW_PREFIX)/include
    ODBC_LIBS   ?= -L$(BREW_PREFIX)/lib -lodbc
else ifneq (,$(MSYSTEM))
    # MSYSTEM is set by every MSYS2 shell (MINGW64, UCRT64, CLANGARM64, ...) —
    # more reliable than grepping `uname -s`, which reports a different
    # prefix per environment (e.g. CLANGARM64_NT-... on Windows ARM64) and
    # would silently miss anything but literal "MINGW".
    FLEX        ?= flex
    BISON       ?= bison
    ODBC_CFLAGS ?=
    ODBC_LIBS   ?= -lodbc32
    # Static-link the C++ runtime so rpgc.exe doesn't depend on MSYS2's
    # libc++.dll/libstdc++-6.dll/libwinpthread-1.dll being present on the
    # target machine — the NSIS installer only ships the exe itself.
    LDFLAGS     ?= -static
    ifeq ($(MSYSTEM),CLANGARM64)
        CXX := clang++
    else
        CXX := g++
    endif
else
    FLEX        ?= flex
    BISON       ?= bison
    ODBC_CFLAGS ?=
    ODBC_LIBS   ?= -lodbc
    CXX         := g++
endif

SRCDIR   := src
BUILDDIR := build
TARGET   := rpgc

SRCS := $(BUILDDIR)/lexer.cpp \
        $(BUILDDIR)/parser.cpp \
        $(SRCDIR)/ast.cpp \
        $(SRCDIR)/codegen.cpp \
        $(SRCDIR)/sql_utils.cpp \
        $(SRCDIR)/conf.cpp \
        $(SRCDIR)/extdesc.cpp \
        $(SRCDIR)/keyword_list.cpp \
        $(SRCDIR)/fixed_reader.cpp \
        $(SRCDIR)/fixed_cspec.cpp \
        $(SRCDIR)/main.cpp

OBJS := $(BUILDDIR)/lexer.o \
        $(BUILDDIR)/parser.o \
        $(BUILDDIR)/ast.o \
        $(BUILDDIR)/codegen.o \
        $(BUILDDIR)/sql_utils.o \
        $(BUILDDIR)/conf.o \
        $(BUILDDIR)/extdesc.o \
        $(BUILDDIR)/keyword_list.o \
        $(BUILDDIR)/fixed_reader.o \
        $(BUILDDIR)/fixed_cspec.o \
        $(BUILDDIR)/main.o

VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "dev")
CXXFLAGS += -DRPGC_VERSION='"$(VERSION)"'

PREFIX  ?= /usr/local
BINDIR  := $(PREFIX)/bin
DATADIR := $(PREFIX)/share/rpgc/runtime

# Pass installed runtime path to main.cpp so rpgc can find headers after install
CXXFLAGS += -DRPGC_RUNTIME_DIR='"$(DATADIR)"'

# OpenDSPF is vendored as a git submodule at $(DSPF_DIR). Run
# `git submodule update --init` if it's empty. Both of these must be defined
# before the `all` rule below: make expands a rule's prerequisites as the
# makefile is read, so a variable assigned further down expands to nothing and
# the dependency silently disappears.
DSPF_DIR     ?= OpenDSPF
DSPF_RUNTIME := runtime/rpg_dspf_runtime.h

all: $(TARGET) $(DSPF_RUNTIME)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/parser.cpp $(BUILDDIR)/parser.h: $(SRCDIR)/parser.y | $(BUILDDIR)
	$(BISON) --defines=$(BUILDDIR)/parser.h -o $(BUILDDIR)/parser.cpp $<

$(BUILDDIR)/lexer.cpp: $(SRCDIR)/lexer.l $(BUILDDIR)/parser.h | $(BUILDDIR)
	$(FLEX) -o $@ $<

$(BUILDDIR)/lexer.o: $(BUILDDIR)/lexer.cpp $(SRCDIR)/keyword_list.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/keyword_list.o: $(SRCDIR)/keyword_list.cpp $(SRCDIR)/keyword_list.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

HDRS := $(SRCDIR)/ast.h $(SRCDIR)/codegen.h $(BUILDDIR)/parser.h

$(BUILDDIR)/ast.o: $(SRCDIR)/ast.cpp $(SRCDIR)/ast.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/codegen.o: $(SRCDIR)/codegen.cpp $(HDRS)
	$(CXX) $(CXXFLAGS) $(ODBC_CFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/sql_utils.o: $(SRCDIR)/sql_utils.cpp $(SRCDIR)/ast.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/conf.o: $(SRCDIR)/conf.cpp $(SRCDIR)/conf.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/extdesc.o: $(SRCDIR)/extdesc.cpp $(SRCDIR)/extdesc.h $(SRCDIR)/conf.h
	$(CXX) $(CXXFLAGS) $(ODBC_CFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/main.o: $(SRCDIR)/main.cpp $(SRCDIR)/ast.h $(SRCDIR)/codegen.h $(SRCDIR)/conf.h $(SRCDIR)/extdesc.h $(SRCDIR)/fixed_reader.h
	$(CXX) $(CXXFLAGS) $(ODBC_CFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/parser.o: $(BUILDDIR)/parser.cpp $(SRCDIR)/ast.h $(SRCDIR)/free_bridge.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/fixed_reader.o: $(SRCDIR)/fixed_reader.cpp $(SRCDIR)/fixed_reader.h $(SRCDIR)/fixed_columns.h $(SRCDIR)/fixed_cspec.h $(SRCDIR)/free_bridge.h $(SRCDIR)/keyword_list.h $(SRCDIR)/ast.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/fixed_cspec.o: $(SRCDIR)/fixed_cspec.cpp $(SRCDIR)/fixed_cspec.h $(SRCDIR)/fixed_columns.h $(SRCDIR)/free_bridge.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) $(ODBC_CFLAGS) -o $@ $^ $(LDFLAGS) $(ODBC_LIBS)

clean:
	rm -rf $(BUILDDIR) $(TARGET) $(DSPF_RUNTIME)


# rpgc compiles WORKSTN programs against runtime/rpg_dspf_runtime.h, but that
# file belongs to OpenDSPF. It used to be a second tracked copy kept in step by
# hand, which is exactly as reliable as it sounds: the two silently diverged,
# and a whole set of display-runtime changes was developed and tested against
# the copy here while the submodule — the one CI, install-dspf and the Windows
# installer ship — still had the old code.
#
# So it is generated, not tracked. There is one copy of this file under source
# control, in OpenDSPF, and `make` refreshes the build-time copy from whatever
# $(DSPF_DIR) points at. Override DSPF_DIR to build against a different
# OpenDSPF checkout.
#
# A copy rather than a symlink: git only checks symlinks out as symlinks when
# core.symlinks is on, which it is not by default on Windows, and this header
# is shipped by the NSIS installer.

# FORCE, and a content compare rather than a timestamp one: the target is
# generated and gitignored, so an edit made to it directly would leave it
# NEWER than its source and make would consider it up to date forever —
# precisely the stale copy this rule exists to prevent. cmp keeps the copy
# from running when the bytes already match, so nothing downstream rebuilds
# needlessly.
$(DSPF_RUNTIME): $(DSPF_DIR)/runtime/rpg_dspf_runtime.h FORCE
	@cmp -s $< $@ 2>/dev/null || { echo "cp $< $@"; cp $< $@; }

FORCE:

$(DSPF_DIR)/runtime/rpg_dspf_runtime.h:
	@echo "error: $(DSPF_DIR)/runtime/rpg_dspf_runtime.h is missing."; \
	 echo "  OpenDSPF is a git submodule and has not been checked out."; \
	 echo "  Run: git submodule update --init"; \
	 exit 1

install: $(TARGET)
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(TARGET) $(DESTDIR)$(BINDIR)/$(TARGET)
	install -d $(DESTDIR)$(DATADIR)
	install -m 644 runtime/rpg_runtime.h $(DESTDIR)$(DATADIR)/
	install -m 644 runtime/rpg_sql_runtime.h $(DESTDIR)$(DATADIR)/
	install -m 644 runtime/rpg_xml_runtime.h $(DESTDIR)$(DATADIR)/
	install -m 644 runtime/rpg_json_runtime.h $(DESTDIR)$(DATADIR)/
	install -m 644 runtime/rpg_csv_runtime.h $(DESTDIR)$(DATADIR)/
	install -m 644 runtime/rpg_flatfile_runtime.h $(DESTDIR)$(DATADIR)/

$(DSPF_DIR)/dspfc:
	$(MAKE) -C $(DSPF_DIR)

install-dspf: $(DSPF_DIR)/dspfc
	install -m 755 $(DSPF_DIR)/dspfc $(DESTDIR)$(BINDIR)/dspfc
	install -d $(DESTDIR)$(DATADIR)
	install -m 644 $(DSPF_DIR)/runtime/rpg_dspf_runtime.h $(DESTDIR)$(DATADIR)/

install-all: install install-dspf

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(TARGET)
	rm -rf $(DESTDIR)$(DATADIR)

uninstall-dspf:
	rm -f $(DESTDIR)$(BINDIR)/dspfc
	rm -f $(DESTDIR)$(DATADIR)/rpg_dspf_runtime.h

test: $(TARGET)
	@bash tests/run_tests.sh

update-expected: $(TARGET)
	@bash tests/run_tests.sh --update

.PHONY: FORCE all clean install install-dspf install-all uninstall uninstall-dspf test update-expected
