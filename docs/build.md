# Release Process

To release a new Lineage (i.e. not a hotfix release) the follow the directions
under "New Lineage Release." Otherwise for a hotfix release (i.e. a patch to an
existing lineage release), follow the directions under "Hotfix Release."

* [First Time Docker Buildx Setup](#first-time-docker-buildx-setup)
* [New Lineage Release](#new-lineage-release)
  * [Checkout Appropriate Branch for New Lineage](#checkout-appropriate-branch-for-new-lineage)
  * [Run `update.sh` for New Lineage](#run-updatesh-for-new-lineage)
* [Hotfix Release](#hotfix-release)
  * [Checkout Appropriate Branch for Hotfix](#checkout-appropriate-branch-for-new-lineage)
  * [Run `update.sh` for Hotfix](#run-updatesh-for-hotfix)
* [Run `build.sh`-for-testing](#run-buildsh-for-testing)
* [Run `test.sh`](#run-testsh)
* [Run `build.sh`-for-publishing](#run-buildsh-for-publishing)
* [Push Changes to GitHub](#push-changes-to-github)

## First Time Docker Buildx Setup

These scripts use `docker buildx` for multi-architecture builds, buildx may need
to be setup if it isn't already.

To check if your current builder support ARM run:

```shell
docker buildx inspect | grep -q "linux/arm" && echo "Builder supports ARM" || echo -e "\033[0;31mARM NOT supported by builder\033[0m"
```

If above outputs "Builder supports ARM" then proceed to either
[New Lineage Release](#new-lineage-release) or
[Hotfix Release](#hotfix-release).

If the output was "ARM NOT supported by builder" then run the following to setup
a builder that supports ARM.

```shell
docker run --privileged --rm tonistiigi/binfmt --install all 
docker buildx create --name mybuilder --driver docker-container --bootstrap --use
```

## New Lineage Release

Follow these directions if this is a new lineage release (i.e. not a hotfix
release).

### Checkout Appropriate Branch for New Lineage

New lineage releases are always committed to the `master` branch.

```shell
git checkout master
git pull origin master
```

If there were not any errors continue to the next section.

### Run `update.sh` for New Lineage

1. The `update.sh` script will find the latest release in the on the artifacts
  page and apply the version it finds to the template which updates the
  enterprise, federal, and community docker images.

  ```shell
  ./update.sh
  ```

2. After the update script has run, commit the changes and tag the release.

  ```shell
  git add enterprise federal community
  git commit -m "Update to <full version>"
  git tag {-a,-m}\ "<full version>"
  ```

3. Optionally you may versify the tag by executing the
  [Optional Tag Sanity Check](#optional-tag-sanity-check) directions.

If there were not any errors continue to the [Run `build.sh`](#run-buildsh)
section.

## Hotfix Release

Follow these directions if this is a patch to an existing release lineage.

### Checkout Appropriate Branch for Hotfix

Checkout the appropriate hotfix branch.

```shell
# example - checkout hotfix/<version excluding hotfix number>
#           (e.g. git checkout hotfix/5.7.0)
git fetch origin
git checkout hotfix/<version excluding hotfix number>
git pull origin hotfix/<version excluding hotfix number>
git merge origin/master # Sync hotfix branch with master.
```

If the above command fails to find a matching branch then the branch doesn't
exist yet - create and checkout the hotfix branch based on the `master` branch.

```shell
# example - create hotfix/<version excluding hotfix number> base on master
git fetch origin
git checkout origin/master -b hotfix/<version excluding hotfix number>
```

If there were not any errors continue to the next section.

### Run `update.sh` for Hotfix

1. For the hotfix, we need to pass in the server version to the `update.sh`
  script.

  ```shell
  git pull origin master
  
  ./update.sh -s <full version>
  
  git commit -m "Update hotfix/<version excluding hotfix number> to hotfix <hotfix number>"
  git tag "<full version>"
  ```

2. Optionally you may versify the tag by executing the
  [Optional Tag Sanity Check](#optional-tag-sanity-check) directions.

If there were not any errors continue to the [Run `build.sh`](#run-buildsh)
section.

## Run `build.sh` for Testing

By default, `build.sh` discovers the server version from the enterprise
Dockerfile (which the script assumes is always generated). Build uses the server
version to determine which editions, architectures, and Linux distributions that
are supported and builds each variant.

Currently we are unable to test multi-platform docker images without pushing
those images to a registry. To work around this issue, build has two modes, test
and push. The test mode allows the `test.sh` to locally verify that the docker
containers are functioning properly. The push mode builds the multi-platform
containers that will be published.

```shell
./build.sh -t
```

If there were not any errors continue to the next section.

## Run `test.sh`

By default, `test.sh` discovers each variant which needs to be tested based on
the server version it discovers from the enterprise Dockerfile - same as
`build.sh` above.

```shell
./test.sh --all --clean
```

If there were not any errors continue to the next section.

## Run `build.sh` for Publishing

To build the multi-platform images and publish images to dockerhub.

```shell
./build.sh -p
```

## Push Changes to GitHub

For a new lineage, push the changes committed to the local `master` branch and
create a hotfix branch for future hotfixs.

```shell
git push origin master
git checkout master -b hotfix/<version excluding hotfix number>
```

For a hotfix release, push the committed changes to the
`hotfix<version excluding hotfix number>` branch.

```shell
# example - push hotfix/<version excluding hotfix number>
#           (e.g. git push origin hotfix/5.7.0)
git push origin hotfix/<version excluding hotfix number>
```

## Optional Tag Sanity Check

Optional sanity check - the GitHub actions will run `./update.sh -g` which
requires that the release has already been tagged - you may verify that the tag
is correct by running `./update.sh -g` and observing that the contents of the
three editions do not change.

```shell
./update.sh -g 2>/dev/null && [ -z "$(git diff --stat)" ] && echo "Tag is good"
```
