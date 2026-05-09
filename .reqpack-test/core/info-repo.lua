return {
  name = "rpm info falls back to dnf repo info",
  request = {
    action = "info",
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
      match = "rpm -qi 'jq'",
      exitCode = 1,
      stdout = "",
      stderr = "package jq is not installed\n",
      success = false,
    },
    {
      match = "command -v 'dnf' >/dev/null 2>&1",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "dnf info 'jq'",
      exitCode = 0,
      stdout = "Available Packages\nName         : jq\nVersion      : 1.7\nRelease      : 2.fc40\nArchitecture : x86_64\nRepository   : fedora\nLicense      : MIT\nSummary      : JSON processor\nURL          : https://jqlang.github.io/jq/\nDescription  : Command-line JSON processor\n             : with filters\n",
      stderr = "",
      success = true,
    }
  },
  expect = {
    success = true,
    commands = {
      "rpm -qi 'jq'",
      "command -v 'dnf' >/dev/null 2>&1",
      "dnf info 'jq'"
    },
    events = { "informed" },
    eventPayloads = {
      informed = "{architecture=x86_64, description=Command-line JSON processor\nwith filters, extraFields=<lua-value>, homepage=https://jqlang.github.io/jq/, installed=false, license=MIT, name=jq, packageId=jq.x86_64, packageType=rpm, repository=fedora, status=available, summary=JSON processor, type=package, version=1.7-2.fc40}",
    },
    resultCount = 1,
    resultName = "jq",
    resultVersion = "1.7-2.fc40",
  }
}
