.PHONY: test coverage app universal install e2e icon clean

test:
	swift test

coverage:
	./scripts/coverage.sh

app:
	./scripts/build-app.sh

universal:
	ARCHS="arm64 x86_64" ./scripts/build-app.sh

install:
	./scripts/install.sh

e2e: app
	./scripts/e2e.sh

icon:
	swift scripts/make-icon.swift Resources

clean:
	rm -rf .build dist
