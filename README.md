# iACE2

A Jupiter ACE emulator with the original user manual, for iPad and Android tablets. This is the Flutter rebuild of [iACE](archive/iACE). The Z80 core is C, called through `dart:ffi`.

```sh
make setup   # packages + toolchain check
make test    # C core tests + Flutter tests
make help    # all targets
```

The plan and phases are in [project-plan.md](project-plan.md). The license is GPL v2 or later (see the original sources).
