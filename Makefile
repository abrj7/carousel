.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	./scripts/bundle.sh

run: app
	-pkill -x Carousel
	open build/Carousel.app

install: app
	-pkill -x Carousel
	rm -rf /Applications/Carousel.app
	cp -R build/Carousel.app /Applications/
	open /Applications/Carousel.app

clean:
	rm -rf .build build
