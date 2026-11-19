// Identify the inputs to the signing UI independent of how they are staged.
const { execFileSync } = require("node:child_process");
const { createHash } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

function ceremonyInputDigest(config, plan, commit) {
  const required = [config, plan, "package.json"].map((file) => path.relative(".", file));
  const listing = commit
    ? ["ls-tree", "-r", "-z", "--name-only", commit, "--", "deploy-ui"]
    : ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "deploy-ui"];
  const ui = execFileSync("git", listing, { encoding: "utf8" }).split("\0").filter((file) =>
    file && file !== "deploy-ui/README.md" && file !== "deploy-ui/.gitignore"
  );
  const hash = createHash("sha256");
  for (const file of [...new Set([...required, ...ui])].sort()) {
    // An unstaged deletion represents the same UI as the committed deletion.
    if (!commit && !required.includes(file) && !fs.existsSync(file)) continue;
    const bytes = commit
      ? execFileSync("git", ["cat-file", "blob", `${commit}:${file}`], { maxBuffer: 32 * 1024 * 1024 })
      : fs.readFileSync(file);
    hash.update(file).update("\0").update(createHash("sha256").update(bytes).digest());
  }
  return hash.digest("hex");
}

if (require.main === module) {
  console.log(ceremonyInputDigest(...process.argv.slice(2)));
}
