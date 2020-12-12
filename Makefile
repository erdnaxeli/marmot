all:
	shards build --release

doc:
	crystal doc

init-dev:
	shards install

lint:
	crystal tool format
	./bin/ameba src spec

test:
	crystal spec  --error-trace

.PHONY: test
