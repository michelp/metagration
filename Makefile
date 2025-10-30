# Metagration TLE Build System

.PHONY: tle test clean help

help:
	@echo "Metagration TLE Build Targets:"
	@echo "  make tle     - Build TLE installer (install-tle.sql)"
	@echo "  make test    - Build and run full test suite"
	@echo "  make clean   - Remove generated files"

tle:
	@echo "Building TLE installer..."
	python3 build-tle.py

test: tle
	@echo "Running test suite..."
	./test.sh

clean:
	@echo "Cleaning generated files..."
	rm -f install-tle.sql
	@echo "Clean complete"
