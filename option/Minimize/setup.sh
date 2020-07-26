#!/bin/sh

minimize () {
	rm -rf usr/tests
	rm -rf usr/lib/debug/boot/kernel
}

PRIORITY=40 strategy_add $PHASE_FREEBSD_OPTION_INSTALL minimize

