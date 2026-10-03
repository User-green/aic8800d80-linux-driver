# Top-level wrapper. Builds against the headers of the running kernel by default;
# override with e.g.  make KDIR=/path/to/kernel/build
KDIR ?= /lib/modules/$(shell uname -r)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/aic8800 modules
	$(MAKE) -C $(KDIR) M=$(CURDIR)/aic_btusb modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/aic8800 clean
	$(MAKE) -C $(KDIR) M=$(CURDIR)/aic_btusb clean
