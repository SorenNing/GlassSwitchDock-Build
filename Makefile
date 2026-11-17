PYTHON ?= python3
ARCH ?= arm64e

.PHONY: all build check verify smoke smoke-core infra-check clean
all: build

build:
	$(PYTHON) tools/build.py --arch $(ARCH)

check:
	$(PYTHON) tools/project.py --output evidence/source-check.json

infra-check:
	$(PYTHON) tools/check-infrastructure.py

verify:
	$(PYTHON) tools/verify-dist.py

smoke:
	$(PYTHON) tools/build.py --smoke --harness

smoke-core:
	$(PYTHON) tools/build.py --smoke

clean:
	$(PYTHON) -c "import shutil; shutil.rmtree('build', ignore_errors=True)"
