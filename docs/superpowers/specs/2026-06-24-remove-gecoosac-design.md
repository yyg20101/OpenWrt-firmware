# Remove GecoOS AC From Required Firmware Set

## Summary

The latest `Firmware CI / x86_64_LEDE` release build on commit `86db57a62dfdcb4b98eb10232e095c9b34f8779d` failed after `Compile Firmware` because `package/gecoosac` could not prepare its build directory. The failing command was:

```text
cp -fpR ../LICENSE .../gecoosac/LICENSE
cp: cannot stat '../LICENSE': No such file or directory
```

`gecoosac` is not provided by the default LEDE feeds. It is currently introduced by this repository through `CONFIG_PACKAGE_luci-app-gecoosac=y` in `scripts/common/config/base.config` and an overlay from `laipeng668/luci-app-gecoosac` in `scripts/common/package`.

## Decision

Remove `gecoosac` from the shared required firmware package set instead of repairing and continuing to maintain the external overlay.

This keeps the LEDE build aligned with default feeds plus the explicitly approved `kenzok8/small` package seed and existing required overlays such as PassWall. It also avoids preserving a default-feeds-external binary package whose upstream layout currently breaks the repository's package extraction mode.

## Scope

- Remove `CONFIG_PACKAGE_luci-app-gecoosac=y` from `scripts/common/config/base.config`.
- Remove the `laipeng668/luci-app-gecoosac` overlay call from `scripts/common/package`.
- Update documentation and plan evidence that currently lists `luci-app-gecoosac` as required/effective.
- Keep `kenzok8/small@master` LEDE package seeding unchanged.
- Keep PassWall, HomeProxy, Samba4, WireGuard, LuCI Chinese, SQM, CAKE, and other existing required capabilities unchanged.

## Non-Goals

- Do not add a local compatibility hack for `gecoosac`.
- Do not reintroduce `gecoosac` from another feed.
- Do not remove unrelated plugins to reduce image size or compile time.
- Do not change the release workflow beyond re-running the existing `x86_64_LEDE` release build.

## Validation

Local validation must include:

- `bash scripts/ci/validate-profiles.sh`
- `bash scripts/ci/validate-lede-small-overlay.sh`
- `bash scripts/ci/validate-passwall-overlay.sh`
- `bash scripts/ci/test-config-audit.sh`
- `bash scripts/ci/test-config-feeds.sh`
- workflow YAML parsing
- shell syntax checks
- `git diff --check`

Remote validation must trigger:

```bash
gh workflow run firmware-ci.yml --repo yyg20101/OpenWrt-firmware --ref main -f target=x86_64_LEDE -f release=true
```

Success means the run reaches firmware artifact upload, x86 smoke, and `Publish GitHub Release`.

## Risks

- Users expecting GecoOS AC in the firmware will no longer receive it.
- The requested-vs-effective LuCI audit will no longer list `luci-app-gecoosac`, which is intended after this removal.
- If another package later depends on `gecoosac`, config audit or compile output should expose that dependency explicitly.
