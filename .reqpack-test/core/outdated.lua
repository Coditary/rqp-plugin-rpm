return {
  name = "rpm outdated parses dnf check-update",
  request = {
    action = "outdated",
    system = "rpm",
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
      match = "command -v 'dnf' >/dev/null 2>&1",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "dnf check-update",
      exitCode = 100,
      stdout = "Last metadata expiration check: 0:05:12 ago\ncurl.x86_64 8.1.0-1.fc40 updates\nignored line\n",
      stderr = "",
      success = false,
    }
  },
  expect = {
    success = true,
    commands = {
      "command -v 'dnf' >/dev/null 2>&1",
      "dnf check-update"
    },
    events = { "outdated" },
    eventPayloads = {
      outdated = "{1=<lua-value>}",
    },
    resultCount = 1,
    resultName = "curl",
  }
}
