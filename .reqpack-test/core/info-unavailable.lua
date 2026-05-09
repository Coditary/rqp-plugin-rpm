return {
  name = "rpm info emits unavailable without helpers",
  request = {
    action = "info",
    system = "rpm",
    prompt = "missing-package",
  },
  fakeExec = {
    {
      match = "rpm -qi 'missing-package'",
      exitCode = 1,
      stdout = "",
      stderr = "package missing-package is not installed\n",
      success = false,
    },
    {
      match = "command -v 'dnf' >/dev/null 2>&1",
      exitCode = 1,
      stdout = "",
      stderr = "",
      success = false,
    },
    {
      match = "command -v 'yum' >/dev/null 2>&1",
      exitCode = 1,
      stdout = "",
      stderr = "",
      success = false,
    }
  },
  expect = {
    success = false,
    commands = {
      "rpm -qi 'missing-package'",
      "command -v 'dnf' >/dev/null 2>&1",
      "command -v 'yum' >/dev/null 2>&1"
    },
    stderr = { "package missing-package is not installed\n" },
    events = { "unavailable" },
    eventPayloads = {
      unavailable = "{name=missing-package, packageType=rpm}",
    },
  }
}
