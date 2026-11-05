# Build Meetball from the terminal; see Scripts/dist.sh for details.
.PHONY: dist run install universal clean

dist:
	Scripts/dist.sh

run:
	Scripts/dist.sh --run

install:
	Scripts/dist.sh --install --run

universal:
	Scripts/dist.sh --universal

clean:
	rm -rf build dist
