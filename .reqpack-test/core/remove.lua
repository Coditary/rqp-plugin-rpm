return {
  name = "rpm remove installed package",
  request = {
    action = "remove",
    system = "rpm",
    packages = {
      { name = "curl" }
    },
  },
  fakeExec = {
    {
      match = "command -v 'rpm' >/dev/null 2>&1",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "rpm -e 'curl'",
      exitCode = 0,
      stdout = "removed\n",
      stderr = "",
      success = true,
    }
  },
  expect = {
    success = true,
    commands = { "rpm -e 'curl'" },
    stdout = { "removed\n" },
    events = { "deleted", "success" },
    eventPayloads = {
      deleted = "<lua-value>",
      success = "ok",
    },
  }
}
