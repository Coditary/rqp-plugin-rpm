return {
  name = "rpm info parses installed package",
  request = {
    action = "info",
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
      match = "rpm -qi 'curl'",
      exitCode = 0,
      stdout = "Name        : curl\nVersion     : 8.0.1\nRelease     : 1.fc40\nArchitecture: x86_64\nLicense     : MIT\nSummary     : Transfer tool\nURL         : https://curl.se\nDescription : Command line tool\n            for transferring data\n",
      stderr = "",
      success = true,
    }
  },
  expect = {
    success = true,
    events = { "informed" },
    eventPayloads = {
      informed = "{architecture=x86_64, description=Command line tool\nfor transferring data, extraFields=<lua-value>, homepage=https://curl.se, installed=true, license=MIT, name=curl, packageId=curl.x86_64, packageType=rpm, status=installed, summary=Transfer tool, type=package, version=8.0.1-1.fc40}",
    },
    resultCount = 1,
    resultName = "curl",
    resultVersion = "8.0.1-1.fc40",
  }
}
