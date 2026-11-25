.PHONY: editor xcode build debug dmg run install clean

editor:
	cd EditorEngine && npm install && npm run build

xcode:
	xcodegen generate

build: editor
	chmod +x scripts/build_app.sh && ./scripts/build_app.sh Release

debug: editor
	chmod +x scripts/build_app.sh && ./scripts/build_app.sh Debug

dmg: build
	chmod +x scripts/package_dmg.sh && ./scripts/package_dmg.sh 1.0.0

run: debug
	open build/Debug/Lepora.app

install: build
	rm -rf /Applications/Lepora.app && cp -R build/Release/Lepora.app /Applications/Lepora.app && open /Applications/Lepora.app

clean:
	rm -rf build Lepora.xcodeproj Lepora/Resources/EditorBundle
