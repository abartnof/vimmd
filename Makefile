.PHONY: all cbridge engine views app test clean

all: app

cbridge:
	@mkdir -p build /tmp/clang-module-cache
	clang -Wall -Wextra -Werror -I Sources/CBridge -c Sources/CBridge/libvim_bridge.c -o build/libvim_bridge.o
	ar rcs build/libCBridge.a build/libvim_bridge.o

engine: cbridge
	@mkdir -p build /tmp/clang-module-cache
	swiftc -module-cache-path /tmp/clang-module-cache \
		-I Sources/CBridge -I build \
		-emit-module -emit-module-path build/Engine.swiftmodule \
		-emit-library -static -o build/libEngine.a \
		-module-name Engine \
		Sources/Engine/*.swift

views: engine
	@mkdir -p build /tmp/clang-module-cache
	swiftc -module-cache-path /tmp/clang-module-cache \
		-I Sources/CBridge -I build \
		-emit-module -emit-module-path build/Views.swiftmodule \
		-emit-library -static -o build/libViews.a \
		-module-name Views \
		Sources/Views/*.swift

app: views
	@mkdir -p build /tmp/clang-module-cache
	swiftc -module-cache-path /tmp/clang-module-cache \
		-I Sources/CBridge -I build \
		-L build \
		-lViews -lEngine -lCBridge \
		Sources/App/*.swift \
		-o build/VimMD

test:
	./scripts/test.sh

clean:
	rm -rf build
