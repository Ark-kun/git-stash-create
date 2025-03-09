#!/bin/sh
# Copyright (c) 2007, Nanako Shiraishi

dashless=$(basename "$0" | sed -e 's/-/ /')
# git-stash-create.sh create --include-untracked
USAGE="$dashless create [-u|--include-untracked] [-m|--message <message>]"

SUBDIRECTORY_OK=Yes
OPTIONS_SPEC=
START_DIR=$(pwd)
# Ark:
# . git-sh-setup
. "$(git --exec-path)/git-sh-setup"
require_work_tree
prefix=$(git rev-parse --show-prefix) || exit 1
cd_to_toplevel

TMP="$GIT_DIR/.git-stash.$$"
TMPindex=${GIT_INDEX_FILE-"$(git rev-parse --git-path index)"}.stash.$$
trap 'rm -f "$TMP-"* "$TMPindex"' 0

ref_stash=refs/stash

if git config --get-colorbool color.interactive; then
       help_color="$(git config --get-color color.interactive.help 'red bold')"
       reset_color="$(git config --get-color '' reset)"
else
       help_color=
       reset_color=
fi

no_changes () {
	git diff-index --quiet --cached HEAD --ignore-submodules -- "$@" &&
	git diff-files --quiet --ignore-submodules -- "$@" &&
	(test -z "$untracked" || test -z "$(untracked_files "$@")")
}

untracked_files () {
	if test "$1" = "-z"
	then
		shift
		z=-z
	else
		z=
	fi
	excl_opt=--exclude-standard
	test "$untracked" = "all" && excl_opt=
	git ls-files -o $z $excl_opt -- "$@"
}

prepare_fallback_ident () {
	if ! git -c user.useconfigonly=yes var GIT_COMMITTER_IDENT >/dev/null 2>&1
	then
		GIT_AUTHOR_NAME="git stash"
		GIT_AUTHOR_EMAIL=git@stash
		GIT_COMMITTER_NAME="git stash"
		GIT_COMMITTER_EMAIL=git@stash
		export GIT_AUTHOR_NAME
		export GIT_AUTHOR_EMAIL
		export GIT_COMMITTER_NAME
		export GIT_COMMITTER_EMAIL
	fi
}

create_stash () {

	prepare_fallback_ident

	stash_msg=
	untracked=
	while test $# != 0
	do
		case "$1" in
		-m|--message)
			shift
			stash_msg=${1?"BUG: create_stash () -m requires an argument"}
			;;
		-m*)
			stash_msg=${1#-m}
			;;
		--message=*)
			stash_msg=${1#--message=}
			;;
		-u|--include-untracked)
			shift
			# untracked=${1?"BUG: create_stash () -u requires an argument"}
			untracked=untracked
			;;
		--)
			shift
			break
			;;
		*)
			usage
			;;
		esac
		if test $# != 0
		then
			shift
		fi
	done

	git update-index -q --refresh
	if no_changes "$@"
	then
		exit 0
	fi

	# state of the base commit
	if b_commit=$(git rev-parse --verify HEAD)
	then
		head=$(git rev-list --oneline -n 1 HEAD --)
	else
		die "$(gettext "You do not have the initial commit yet")"
	fi

	if branch=$(git symbolic-ref -q HEAD)
	then
		branch=${branch#refs/heads/}
	else
		branch='(no branch)'
	fi
	msg=$(printf '%s: %s' "$branch" "$head")

	# state of the index
	i_tree=$(git write-tree) &&
	i_commit=$(printf 'index on %s\n' "$msg" |
		git commit-tree $i_tree -p $b_commit) ||
		die "$(gettext "Cannot save the current index state")"

	if test -n "$untracked"
	then
		# Untracked files are stored by themselves in a parentless commit, for
		# ease of unpacking later.
		u_commit=$(
			untracked_files -z "$@" | (
				GIT_INDEX_FILE="$TMPindex" &&
				export GIT_INDEX_FILE &&
				rm -f "$TMPindex" &&
				git update-index -z --add --remove --stdin &&
				u_tree=$(git write-tree) &&
				printf 'untracked files on %s\n' "$msg" | git commit-tree $u_tree  &&
				rm -f "$TMPindex"
		) ) || die "$(gettext "Cannot save the untracked files")"

		untracked_commit_option="-p $u_commit";
	else
		untracked_commit_option=
	fi

	# if test -z "$patch_mode"
	# then

		# state of the working tree
		w_tree=$( (
			git read-tree --index-output="$TMPindex" -m $i_tree &&
			GIT_INDEX_FILE="$TMPindex" &&
			export GIT_INDEX_FILE &&
			git diff-index --name-only -z HEAD -- "$@" >"$TMP-stagenames" &&
			git update-index -z --add --remove --stdin <"$TMP-stagenames" &&
			git write-tree &&
			rm -f "$TMPindex"
		) ) ||
			die "$(gettext "Cannot save the current worktree state")"

	# else

	# 	rm -f "$TMP-index" &&
	# 	GIT_INDEX_FILE="$TMP-index" git read-tree HEAD &&

	# 	# find out what the user wants
	# 	GIT_INDEX_FILE="$TMP-index" \
	# 		git add--interactive --patch=stash -- "$@" &&

	# 	# state of the working tree
	# 	w_tree=$(GIT_INDEX_FILE="$TMP-index" git write-tree) ||
	# 	die "$(gettext "Cannot save the current worktree state")"

	# 	git diff-tree -p HEAD $w_tree -- >"$TMP-patch" &&
	# 	test -s "$TMP-patch" ||
	# 	die "$(gettext "No changes selected")"

	# 	rm -f "$TMP-index" ||
	# 	die "$(gettext "Cannot remove temporary index (can't happen)")"

	# fi

	# create the stash
	if test -z "$stash_msg"
	then
		stash_msg=$(printf 'WIP on %s' "$msg")
	else
		stash_msg=$(printf 'On %s: %s' "$branch" "$stash_msg")
	fi
	w_commit=$(printf '%s\n' "$stash_msg" |
	git commit-tree $w_tree -p $b_commit -p $i_commit $untracked_commit_option) ||
	die "$(gettext "Cannot record working tree state")"
}

show_help () {
	exec git help stash
	exit 1
}

# Main command set
# case "$1" in
# create)
# 	shift
# 	# create_stash -m "$*" && echo "$w_commit"
# 	create_stash "$*" && echo "$w_commit"
# 	;;
# *)
# 	usage
# 	;;
# esac
create_stash "$*" && echo "$w_commit"
