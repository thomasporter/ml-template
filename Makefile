#!make


.DEFAULT_GOAL = help

help:
	@printf "Usage:\n"
	@grep -E '^[a-zA-Z_-]+:.*?# .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?# "}; {printf "\033[1;34mmake %-20s\033[0m%s\n", $$1, $$2}'

setup:		# Run setup to build default environment
	@printf "Setting up default environment variables.\n"
	$(shell chmod +x ./setup.sh)
	./setup.sh

build:		# build and tag all intermediate images
	docker build . \
		--target ubuntu-base \
	 	--tag=thestatskid/ubuntu:latest
	docker build . \
		--target python-base \
		--tag=thestatskid/python:latest
	docker build . \
		--target development \
		--tag=thestatskid/jupyter:latest

version?=patch
message?=$(version) release
package-version:		# update version numbers inside container
	poetry version $(version)
	poetry version -s > VERSION
	git tag -a "v$(shell cat VERSION)" -m "version v$(shell cat VERSION) - $(message)"