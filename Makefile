# Build Meetball from the terminal; see Scripts/dist.sh for details.
.PHONY: dist run install universal phone clean

dist:
	Scripts/dist.sh

run:
	Scripts/dist.sh --run

install:
	Scripts/dist.sh --install --run

universal:
	Scripts/dist.sh --universal

# Build MeetballPhone and install it on your paired iPhone (PHONE="name" picks one); see Scripts/phone.sh.
phone:
	Scripts/phone.sh

clean:
	rm -rf build dist
