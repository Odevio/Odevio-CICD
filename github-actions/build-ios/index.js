const core = require('@actions/core');
const fs = require('fs')
const archiver = require('archiver');
const EventSource = require("eventsource");

const baseUrl = "https://odevio.com";

async function run() {
  try {
    const apiKey = core.getInput("api-key");

    // Read .odevio file
    let odevioFile = null;
    if (fs.existsSync("./.odevio")) {
      odevioFile = fs.readFileSync("./.odevio", {encoding: "utf8", flag: "r"});
    }
    else if (core.getInput("directory") && fs.existsSync(core.getInput("directory")+"/.odevio")) {
      odevioFile = fs.readFileSync(core.getInput("directory")+"/.odevio", {encoding: "utf8", flag: "r"});
    }
    if (odevioFile) {
      odevioFile = odevioFile.split("\n").reduce((a, v) => ({...a, [v.split("=")[0]]: v.split("=")[1]}), {});
    }

    // Get parameters from inputs or .odevio file
    function getParameter(name) {
      if (core.getInput(name))
        return core.getInput(name);
      if (odevioFile && odevioFile[name])
        return odevioFile[name];
      return null;
    }
    const appKey = getParameter("app-key");
    const directory = getParameter("directory");
    const buildType = getParameter("build-type");
    const flutterVersion = getParameter("flutter");
    const minimalIosVersion = getParameter("minimal-ios-version");
    const appVersion = getParameter("app-version");
    const buildNumber = getParameter("build-number");
    const mode = getParameter("mode");
    const target = getParameter("target");
    const flavor = getParameter("flavor");
    const postBuildCommand = getParameter("post-build-command");

    // Verify parameters
    if (!appKey) {
      core.setFailed("App key not provided");
      return;
    }
    if (buildType == "publication")
      console.log("Publishing app with key "+appKey);
    else if (buildType == "ad-hoc")
      console.log("Building IPA of app with key "+appKey);
    else if (buildType == "validation")
      console.log("Validating app with key "+appKey);
    else {
      core.setFailed("Unsupported build type '"+buildType+"'")
      return;
    }

    // Zip directory
    /// Get excluded files and directories
    let excludedFiles = ["source.zip", ".app.zip", "odevio.patch"];
    let excludedDirs = ["build", "windows", "linux", "android", "web", ".dart_tool", ".pub-cache", ".pub", ".git", ".gradle"];
    let odevioIgnore = null;
    if (fs.existsSync("./.odevioignore")) {
      odevioIgnore = fs.readFileSync("./.odevioignore", {encoding: "utf8", flag: "r"});
    }
    else if (core.getInput("directory") && fs.existsSync(core.getInput("directory")+"/.odevioignore")) {
      odevioIgnore = fs.readFileSync(core.getInput("directory")+"/.odevioignore", {encoding: "utf8", flag: "r"});
    }
    if (odevioIgnore) {
      odevioIgnore.split("\n").forEach(line => {
        if (line == "") return;
        if (line.endsWith("/"))
          excludedDirs.push(line.slice(0, -1));
        else
          excludedFiles.push(line);
      });
    }
    /// Zip
    const archive = archiver("zip", {zlib: {level: 6}});
    const zipOutput = fs.createWriteStream(".app.zip");
    const zipped = new Promise((resolve, reject) => {
      zipOutput.on("close", resolve);
    });
    archive.on("warning", (w) => core.warning("Zip: "+err));
    archive.on("error", (e) => {throw e;});
    archive.pipe(zipOutput);
    const files = fs.readdirSync(directory ?? ".");
    files.forEach(file => {
      let path = file;
      if (directory)
        path = directory + "/" + file;
      if (fs.lstatSync(path).isDirectory()) {
        if (!excludedDirs.includes(file))
          archive.directory(path, file);
      }
      else {
        if (!excludedFiles.includes(file))
          archive.file(path, {name: file});
      }
    });
    archive.finalize();
    await zipped;
    /// Check size
    const size = fs.statSync(".app.zip").size;
    if (size >= 500000000) {
      core.setFailed("Zipped directory size exceeds 500MB, very large applications are not supported by Odevio. Make sure that all files and directories not needed to build are listed in .odevioignore");
      return;
    }

    // Set data to send
    let data = new FormData();
    data.append("application", appKey);
    data.append("build_type", buildType);
    data.append("source", await fs.openAsBlob(".app.zip"), "source.zip");
    if (flutterVersion)
      data.append("flutter_version", flutterVersion);
    if (minimalIosVersion)
      data.append("min_sdk", minimalIosVersion);
    if (appVersion)
      data.append("app_version", appVersion);
    if (buildNumber)
      data.append("build_number", parseInt(buildNumber));
    if (mode)
      data.append("mode", mode);
    if (target)
      data.append("target", target);
    if (flavor)
      data.append("flavor", flavor);
    if (postBuildCommand)
      data.append("post_build_commands", postBuildCommand);

    // Start build
    let res = await fetch(baseUrl+"/api/v1/builds/", {
      method: "POST",
      body: data,
      headers: {
        "Authorization": "Token "+apiKey,
        "Accept": "application/json",
      }
    });
    if (!res.ok) {
      core.setFailed("Error starting build (error code "+res.status+"): "+(await res.text()));
      return;
    }
    let build = await res.json();
    console.log("Build started with key "+build.key);

    while(true) {
      res = await fetch(baseUrl+"/api/v1/builds/"+build.key+"/", {headers: {
        "Authorization": "Token "+apiKey,
        "Accept": "application/json",
      }});
      build = await res.json();
      if (build.status_code == "succeeded") {
        console.log("Build succeeded");
        break;
      }
      if (build.status_code == "failed") {
        core.setFailed("Build failed: "+build.error_message);
        return;
      }
      if (build.status_code == "stopped") {
        core.setFailed("Build was manually stopped from somewhere else.");
        return;
      }
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
    if (buildType == "ad-hoc") {
      res = await fetch(baseUrl+"/api/v1/builds/"+build.key+"/ipa/", {headers: {
        "Authorization": "Token "+apiKey,
        "Accept": "application/json",
      }});
      ipa = await res.json();
      core.setOutput("ipa", ipa.url);
    }
  }
  catch (e) {
    core.setFailed(e.message);
  }
}

run();
