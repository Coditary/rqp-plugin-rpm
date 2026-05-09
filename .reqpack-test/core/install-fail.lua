return {
  name = "rpm install local artifact fails cleanly",
  request = {
    action = "install",
    system = "rpm",
    localPath = "/tmp/broken.rpm",
  },
  fakeExec = {
    {
      match = "rpm -Uvh '/tmp/broken.rpm'",
      exitCode = 1,
      stdout = "",
      stderr = "bad package\n",
      success = false,
    }
  },
  expect = {
    success = false,
    commands = { "rpm -Uvh '/tmp/broken.rpm'" },
    stderr = { "bad package\n" },
    events = { "failed" },
    eventPayloads = {
      failed = "local rpm install failed",
    },
  }
}
