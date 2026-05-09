return {
  name = "rpm search falls back to yum",
  request = {
    action = "search",
    system = "rpm",
    prompt = "curl",
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
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "yum search 'curl'",
      exitCode = 0,
      stdout = "Loaded plugins: fastestmirror\n========================= N/S matched: curl =========================\ncurl.x86_64 : Command line tool for transferring data\nnot a result line\n",
      stderr = "",
      success = true,
    }
  },
  expect = {
    success = true,
    commands = {
      "command -v 'dnf' >/dev/null 2>&1",
      "command -v 'yum' >/dev/null 2>&1",
      "yum search 'curl'"
    },
    events = { "searched" },
    eventPayloads = {
      searched = "{1=<lua-value>}",
    },
    resultCount = 1,
    resultName = "curl",
  }
}
