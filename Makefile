SHELL := /bin/bash
.DEFAULT_GOAL := help

project_dir := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
builddir ?= $(project_dir)/build/rpmbuild
outdir ?= $(project_dir)/dist
spec ?= $(project_dir)/epic-games-launcher.spec
RPMBUILD ?= rpmbuild
rpm_args = --define "_topdir $(abspath $(builddir))" \
           --define "_tmppath $(abspath $(builddir))/tmp" \
           --define "_sourcedir $(project_dir)" \
           --define "_rpmdir $(abspath $(outdir))" \
           --define "_srcrpmdir $(abspath $(outdir))"

.PHONY: help check rpm srpm

help:
	@printf '%s\n' \
	  'Install the latest official download: sudo ./install-epic-games-launcher.sh' \
	  'Installer options: ./install-epic-games-launcher.sh --help'
	@printf '%s\n' \
	  'make check  - Test launcher behavior and validate desktop/shell files.' \
	  'make rpm    - Build a local RPM and self-contained SRPM in dist/.' \
	  'make srpm   - Build only the SRPM (override output with outdir=...).'
	@printf '%s\n' \
	  'Build prerequisites: rpm-build redhat-rpm-config dpkg desktop-file-utils binutils make' \
	  'Keep the original EpicGamesLauncher .deb next to the spec.' \
	  'COPR PUBLICATION BLOCKED: the main application license is unverified.' \
	  'Neither the .deb nor its RPM/SRPM may be uploaded to COPR on that basis.'

check:
	sh -n "$(project_dir)/run-epic-games-launcher.sh"
	bash -n "$(project_dir)/install-epic-games-launcher.sh"
	desktop-file-validate "$(project_dir)/epic-games-launcher.desktop"
	bash "$(project_dir)/tests/test-launcher.sh"
	bash "$(project_dir)/tests/test-rpaths.sh"
	bash "$(project_dir)/tests/test-installer.sh"

rpm: check
	mkdir -p "$(builddir)/tmp" "$(outdir)"
	$(RPMBUILD) -ba $(rpm_args) "$(spec)"

srpm: check
	mkdir -p "$(builddir)/tmp" "$(outdir)"
	$(RPMBUILD) -bs $(rpm_args) "$(spec)"
