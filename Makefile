# Convenience entry for the hard gates. No build logic lives here: the
# bootstrap and every test stay in selfhost/*.sh and test/run.sh.

.PHONY: check
check:
	bash selfhost/check-all.sh
