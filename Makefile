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
        $(SRCDIR)/main.cpp

OBJS := $(BUILDDIR)/lexer.o \
        $(BUILDDIR)/parser.o \
        $(BUILDDIR)/ast.o \
        $(BUILDDIR)/codegen.o \
        $(BUILDDIR)/sql_utils.o \
        $(BUILDDIR)/conf.o \
        $(BUILDDIR)/extdesc.o \
        $(BUILDDIR)/main.o

VERSION := $(shell git describe --tags --always 2>/dev/null || echo "dev")
CXXFLAGS += -DRPGC_VERSION='"$(VERSION)"'

PREFIX  ?= /usr/local
BINDIR  := $(PREFIX)/bin
DATADIR := $(PREFIX)/share/rpgc/runtime

# Pass installed runtime path to main.cpp so rpgc can find headers after install
CXXFLAGS += -DRPGC_RUNTIME_DIR='"$(DATADIR)"'

all: $(TARGET)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/parser.cpp $(BUILDDIR)/parser.h: $(SRCDIR)/parser.y | $(BUILDDIR)
	$(BISON) --defines=$(BUILDDIR)/parser.h -o $(BUILDDIR)/parser.cpp $<

$(BUILDDIR)/lexer.cpp: $(SRCDIR)/lexer.l $(BUILDDIR)/parser.h | $(BUILDDIR)
	$(FLEX) -o $@ $<

$(BUILDDIR)/lexer.o: $(BUILDDIR)/lexer.cpp
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

$(BUILDDIR)/main.o: $(SRCDIR)/main.cpp $(SRCDIR)/ast.h $(SRCDIR)/codegen.h $(SRCDIR)/conf.h $(SRCDIR)/extdesc.h
	$(CXX) $(CXXFLAGS) $(ODBC_CFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/parser.o: $(BUILDDIR)/parser.cpp $(SRCDIR)/ast.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) $(ODBC_CFLAGS) -o $@ $^ $(LDFLAGS) $(ODBC_LIBS)

clean:
	rm -rf $(BUILDDIR) $(TARGET)

# OpenDSPF is vendored as a git submodule at $(DSPF_DIR). Run
# `git submodule update --init` if it's empty.
DSPF_DIR ?= OpenDSPF

install: $(TARGET)
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(TARGET) $(DESTDIR)$(BINDIR)/$(TARGET)
	install -d $(DESTDIR)$(DATADIR)
	install -m 644 runtime/rpg_runtime.h $(DESTDIR)$(DATADIR)/
	install -m 644 runtime/rpg_sql_runtime.h $(DESTDIR)$(DATADIR)/
	install -m 644 runtime/rpg_xml_runtime.h $(DESTDIR)$(DATADIR)/
	install -m 644 runtime/rpg_json_runtime.h $(DESTDIR)$(DATADIR)/
	install -m 644 runtime/rpg_csv_runtime.h $(DESTDIR)$(DATADIR)/

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

.PHONY: all clean install install-dspf install-all uninstall uninstall-dspf test update-expected
