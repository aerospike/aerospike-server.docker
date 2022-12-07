# Release Process

To release a new Lineage (i.e. not a hotfix release) the follow the directions
under "New Lineage Release." Otherwise for a hotfix release (i.e. a patch to an
existing lineage release), follow the directions under "Hotfix Release."

* [Definitions](#definitions)
* [First Time Docker Buildx Setup](#first-time-docker-buildx-setup)
* [First Time Git Clone](#first-time-git-clone)
* [New or Latest Lineage Release](#new-or-latest-lineage-release)
  * [Checkout Appropriate Branch for New Lineage](#checkout-appropriate-branch-for-new-lineage)
  * [Run `update.sh` for New Lineage](#run-updatesh-for-new-lineage)
* [Hotfix Release](#hotfix-release)
  * [Checkout Appropriate Branch for Hotfix](#checkout-appropriate-branch-for-new-lineage)
  * [Run `update.sh` for Hotfix](#run-updatesh-for-hotfix)
* [Run `build.sh`-for-testing](#run-buildsh-for-testing)
* [Run `test.sh`](#run-testsh)
* [Run `build.sh`-for-publishing](#run-buildsh-for-publishing)
* [Push Changes to GitHub](#push-changes-to-github)

## Definitions

* **full-version** - Full 4 digit version number.
* **lineage-version** - First 3 numbers of the **full-version** (excludes the
  hotfix number).
* **new lineage release** - Initial release for a **lineage-version**.
* **hotfix-release** - A release to an existing **lineage-version**.

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

## First Time Git Clone

The following procedures assume that your current working directory is the root
of the `aerospike-server.docker` repo.

```shell
git clone <org>/aerospike-server.docker
cd aerospike-server.docker
```

## New or Latest Lineage Release

Follow these directions if releasing a new lineage or a hotfix on the latest
lineage.

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
  git commit -m "Update to <full-version>"
  git tag -a "<full-version>" -m "<full-version>"
  ```

3. Optionally you may versify the tag by executing the
  [Optional Tag Sanity Check](#optional-tag-sanity-check) directions.

If there were not any errors continue to the [Run `build.sh`](#run-buildsh)
section.

## Hotfix Release

Follow these directions if this is a patch to an existing release lineage that
isn't the latest lineage.

### Checkout Appropriate Branch for Hotfix

Checkout the appropriate hotfix branch.

```shell
# example - checkout hotfix/<lineage-version>
#           (e.g. git checkout hotfix/5.7.0)
git fetch origin
git checkout hotfix/<lineage-version>
git pull origin hotfix/<lineage-version>
git merge origin/master # Sync hotfix branch with master.
```

If the above command fails to find a matching branch then the branch doesn't
exist yet - create and checkout the hotfix branch based on the `master` branch.

```shell
# example - create hotfix/<lineage-version> base on master
git fetch origin
git checkout origin/master -b hotfix/<lineage-version>
```

If there were not any errors continue to the next section.

### Run `update.sh` for Hotfix

1. For the hotfix, we need to pass in the server version to the `update.sh`
  script.

  ```shell
  ./update.sh -s <full-version>
  ```
  
2. After the update script has run, commit the changes and tag the release.

  ```shell
  git add community enterprise federal
  git commit -m "Update hotfix/<lineage-version> to hotfix <full-version>"
  git tag -a "<full-version>" -m "<full-version>"
  ```

3. Optionally you may versify the tag by executing the
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
./test.sh --clean
```

If there were not any errors continue to the next section.

## Run `build.sh` for Publishing

To build the multi-platform images and publish images to dockerhub.

```shell
./build.sh -p
```

## Push Changes to GitHub

### Push Hotfix Release

For a hotfix release, push the committed changes to the
`hotfix/<lineage-version>` branch.

```shell
# example - push hotfix/<lineage-version>
#           (e.g. git push origin hotfix/5.7.0)
git push origin hotfix/<lineage-version>
```

### Push New Lineage Release

For a new lineage, push the changes committed to the local `master` branch and
create a hotfix branch for future hotfixs.

```shell
git push origin master
git checkout master -b hotfix/<lineage-version>
```

## Optional Tag Sanity Check

Optional sanity check - the GitHub actions will run `./update.sh -g` which
requires that the release has already been tagged - you may verify that the tag
is correct by running `./update.sh -g` and observing that the contents of the
three editions do not change.

```shell
./update.sh -g 2>/dev/null && [ -z "$(git diff --stat)" ] && echo "Tag is good"
```
