return {
  name = "rpm install local artifact",
  request = {
    action = "install",
    system = "rpm",
    localPath = "/tmp/curl.rpm",
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
      match = "rpm -Uvh '/tmp/curl.rpm'",
      exitCode = 0,
      stdout = "Preparing...\nInstalled\n",
      stderr = "",
      success = true,
    }
  },
  expect = {
    success = true,
    commands = { "rpm -Uvh '/tmp/curl.rpm'" },
    stdout = { "Preparing...\nInstalled\n" },
    events = { "installed", "success" },
    eventPayloads = {
      installed = "{localTarget=true, path=/tmp/curl.rpm}",
      success = "ok",
    },
  }
}
