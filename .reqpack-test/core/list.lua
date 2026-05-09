return {
  name = "rpm list parses installed packages",
  request = {
    action = "list",
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
      match = "rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\t%{SUMMARY}\n'",
      exitCode = 0,
      stdout = "curl\t8.0.1-1.fc40\tx86_64\tCommand line tool\nmalformed line\nvim\t9.1-2.fc40\tnoarch\tEditor\n",
      stderr = "",
      success = true,
    }
  },
  expect = {
    success = true,
    commands = { "rpm -qa --queryformat '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\t%{SUMMARY}\n'" },
    events = { "listed" },
    eventPayloads = {
      listed = "{1=<lua-value>, 2=<lua-value>}",
    },
    resultCount = 2,
    resultName = "curl",
    resultVersion = "8.0.1-1.fc40",
  }
}
