.PHONY: run build app clean

run:
	swift run

build:
	swift build -c release

app:
	./scripts/build-app.sh

clean:
	swift package clean
	rm -rf dist
