return {
  name = "rpm search without repo helper returns empty",
  request = {
    action = "search",
    system = "rpm",
    prompt = "jq",
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
    success = true,
    commands = {
      "command -v 'dnf' >/dev/null 2>&1",
      "command -v 'yum' >/dev/null 2>&1"
    },
    events = { "searched" },
    eventPayloads = {
      searched = "{}",
    },
    resultCount = 0,
  }
}
