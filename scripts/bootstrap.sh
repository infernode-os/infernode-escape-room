#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
LOCK="$ROOT/infernode.lock"
DEST=${1:-"$ROOT/vendor/infernode"}

repository=$(awk '$1 == "repository" { print $2 }' "$LOCK")
commit=$(awk '$1 == "commit" { print $2 }' "$LOCK")

if [ -z "$repository" ] || [ -z "$commit" ]; then
	echo "bootstrap: invalid $LOCK" >&2
	exit 1
fi

if [ -e "$DEST" ] && [ ! -d "$DEST/.git" ]; then
	echo "bootstrap: $DEST exists but is not a Git checkout" >&2
	exit 1
fi

fresh=0
if [ ! -d "$DEST/.git" ]; then
	mkdir -p "$(dirname "$DEST")"
	git clone --no-checkout "$repository" "$DEST"
	fresh=1
fi

actual_repository=$(git -C "$DEST" remote get-url origin)
case "$actual_repository" in
	"$repository"|git@github.com:infernode-os/infernode.git|ssh://git@github.com/infernode-os/infernode.git) ;;
	*)
		echo "bootstrap: origin is $actual_repository, expected $repository" >&2
		exit 1
		;;
esac

if [ "$fresh" -eq 0 ] && [ -n "$(git -C "$DEST" status --porcelain)" ]; then
	echo "bootstrap: refusing to replace a dirty InferNode checkout at $DEST" >&2
	exit 1
fi

git -C "$DEST" fetch --depth 1 origin "$commit"
git -C "$DEST" checkout --detach "$commit"

actual_commit=$(git -C "$DEST" rev-parse HEAD)
if [ "$actual_commit" != "$commit" ]; then
	echo "bootstrap: checked out $actual_commit, expected $commit" >&2
	exit 1
fi

printf 'bootstrap: InferNode %s at %s\n' "$actual_commit" "$DEST"
