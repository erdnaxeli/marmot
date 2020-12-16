all:
	shards build --release

doc:
	crystal doc --project-version=''
	find docs -type f -exec sed -i -r -e "s#(../)?index.html#https://github.com/erdnaxeli/marmot/#" {} \;

init-dev:
	shards install

lint:
	crystal tool format
	./bin/ameba src spec

test:
	crystal spec  --error-trace

.PHONY: test
